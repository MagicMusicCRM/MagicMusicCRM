import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { acquireLessonSettlementCoordinationGate } from "../commerce/lesson-settlement-locks";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import type {
  LessonCancelCommandDto,
  LessonRescheduleCommandDto,
  LessonSettleCommandDto,
} from "../dto/lesson-transition.dto";
import { normalizeRescheduleDto } from "../dto/lesson-transition.dto";
import type { LessonCommandMetadata } from "./lesson-command-metadata";
import { LessonTransitionCommitService } from "./lesson-transition-commit.service";
import {
  assertTransitionConfirmed,
  assertTransitionMetadata,
  assertTransitionReason,
  stableTransitionId,
  targetTransitionState,
  transitionReasonCode,
} from "./lesson-transition.rules";
import type {
  CommittedTransition,
  LessonTransitionCommandResult,
  TransitionCommandDto,
  TransitionOperation,
} from "./lesson-transition.types";

@Injectable()
export class LessonTransitionCommandService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly commits: LessonTransitionCommitService,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  reschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonRescheduleCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<LessonTransitionCommandResult> {
    return this.execute(actor, lessonId, {
      ...normalizeRescheduleDto(dto),
      previewToken: dto.previewToken,
      confirm: dto.confirm,
    }, metadata);
  }

  cancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<LessonTransitionCommandResult> {
    return this.execute(actor, lessonId, {
      ...dto,
      operation: "cancel",
    }, metadata);
  }

  settle(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettleCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<LessonTransitionCommandResult> {
    return this.execute(actor, lessonId, {
      ...dto,
      operation: "settle",
    }, metadata);
  }

  private async execute(
    actor: ActorContext,
    lessonId: string,
    dto: TransitionCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<LessonTransitionCommandResult> {
    const operation: TransitionOperation = dto.operation;
    this.policy.assertCanWriteCrm(actor);
    assertTransitionConfirmed(dto.confirm);
    assertTransitionMetadata(metadata);
    assertTransitionReason(dto, operation);
    const toState = targetTransitionState(operation);
    const successorId =
      operation === "reschedule"
        ? stableTransitionId(
            `schedule.lesson.reschedule\0${lessonId}\0${actor.userId}\0${metadata.idempotencyKey}`,
          )
        : null;
    const mutation =
      await this.platform.executeVersionedMutation<CommittedTransition>({
        actorKey: `user:${actor.userId}`,
        actorUserId: actor.userId,
        authorization:
          this.policy.teacherCompensationMutationAuthorization(actor),
        operation: `schedule.lesson.${operation}`,
        idempotencyKey: metadata.idempotencyKey,
        payload: { lessonId, dto },
        aggregateType: "schedule:lesson",
        aggregateId: lessonId,
        expectedVersion: dto.expectedVersion,
        requestId: metadata.requestId,
        audit: {
          action:
            operation === "reschedule"
              ? "crm.lesson_rescheduled"
              : operation === "cancel"
                ? "crm.lesson_cancelled"
                : "crm.lesson_settled",
          entityType: "lesson",
          entityId: lessonId,
          reason: transitionReasonCode(dto),
          reasonText: dto.reasonText?.trim(),
          beforeRef: { lessonId, version: dto.expectedVersion },
        },
        outbox: {
          type: "schedule.lesson.changed",
          payload: {
            entityId: lessonId,
            action:
              operation === "reschedule"
                ? "rescheduled"
                : operation === "cancel"
                  ? "cancelled"
                  : "settled",
            state: toState,
            successorId,
          },
        },
        ...(operation === "reschedule"
          ? { beforeVersionAdvance: acquireLessonSettlementCoordinationGate }
          : {}),
        mutate: async (client, nextVersion) => {
          const signed = this.previewTokens.verifyLessonTransition(
            dto.previewToken,
          );
          this.assertSignedPreview(signed, actor, lessonId, dto, operation);
          return this.commitConfirmed(
            client,
            actor,
            lessonId,
            dto,
            successorId,
            nextVersion,
            signed.transitionFingerprint,
          );
        },
      });
    await this.reservations.publishLessonSettlementPostCommit(lessonId);
    if (successorId) {
      await this.reservations.publishLessonSettlementPostCommit(successorId);
    }
    const financialProjection = mutation.resultRef.state === "rescheduled"
      ? {
          financialDecision: mutation.resultRef.successorFinancialDecision,
          sourceFinancialDecision: mutation.resultRef.sourceFinancialDecision,
          successorFinancialDecision: mutation.resultRef.successorFinancialDecision,
        }
      : { financialDecision: mutation.resultRef.financialDecision };
    return {
      source: { id: lessonId, state: toState, version: mutation.version },
      successor:
        successorId === null
          ? null
          : { id: successorId, state: "scheduled", version: 1 },
      transitionId: mutation.resultRef.transitionId,
      clientFinancialFactIds: mutation.resultRef.clientFinancialFactIds,
      teacherFinancialFactId: mutation.resultRef.teacherFinancialFactId,
      ...financialProjection,
      replayed: mutation.replayed,
    };
  }

  private commitConfirmed(
    client: PoolClient,
    actor: ActorContext,
    lessonId: string,
    dto: TransitionCommandDto,
    successorId: string | null,
    nextVersion: number,
    expectedFingerprint: string,
  ): Promise<CommittedTransition> {
    const common = {
      actor,
      lessonId,
      nextVersion,
      expectedFingerprint,
    };
    if (dto.operation === "reschedule") {
      return this.commits.commit(client, {
        ...common,
        dto,
        operation: "reschedule",
        successorId: successorId!,
      });
    }
    return this.commits.commit(client, {
      ...common,
      dto,
      operation: dto.operation,
      successorId: null,
    });
  }

  private assertSignedPreview(
    signed: ReturnType<
      SubscriptionPreviewTokenService["verifyLessonTransition"]
    >,
    actor: ActorContext,
    lessonId: string,
    dto: TransitionCommandDto,
    operation: TransitionOperation,
  ): void {
    if (
      signed.actorUserId !== actor.userId ||
      signed.lessonId !== lessonId ||
      signed.expectedVersion !== dto.expectedVersion ||
      signed.operation !== operation
    ) {
      throw new UnprocessableEntityException({
        code: "LESSON_TRANSITION_PREVIEW_STALE",
        message: "Signed preview does not match this lesson command.",
      });
    }
  }
}
