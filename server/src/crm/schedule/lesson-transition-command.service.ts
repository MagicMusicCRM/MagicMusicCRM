import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import type {
  LessonCancelCommandDto,
  LessonRescheduleCommandDto,
  LessonSettleCommandDto,
} from "../dto/lesson-transition.dto";
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
    return this.execute(actor, lessonId, dto, metadata, "reschedule");
  }

  cancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<LessonTransitionCommandResult> {
    return this.execute(actor, lessonId, dto, metadata, "cancel");
  }

  settle(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettleCommandDto,
    metadata: LessonCommandMetadata,
  ): Promise<LessonTransitionCommandResult> {
    return this.execute(actor, lessonId, dto, metadata, "settle");
  }

  private async execute(
    actor: ActorContext,
    lessonId: string,
    dto: TransitionCommandDto,
    metadata: LessonCommandMetadata,
    operation: TransitionOperation,
  ): Promise<LessonTransitionCommandResult> {
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
        authorization: { actor, capabilityKey: "schedule.lesson.write" },
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
        mutate: async (client, nextVersion) => {
          const signed = this.previewTokens.verifyLessonTransition(
            dto.previewToken,
          );
          this.assertSignedPreview(signed, actor, lessonId, dto, operation);
          return this.commits.commit(client, {
            actor,
            lessonId,
            dto,
            operation,
            successorId,
            nextVersion,
            expectedFingerprint: signed.transitionFingerprint,
          });
        },
      });
    await this.reservations.publishLessonSettlementPostCommit(lessonId);
    if (successorId) {
      await this.reservations.publishLessonSettlementPostCommit(successorId);
    }
    return {
      source: { id: lessonId, state: toState, version: mutation.version },
      successor:
        successorId === null
          ? null
          : { id: successorId, state: "scheduled", version: 1 },
      transitionId: mutation.resultRef.transitionId,
      clientFinancialFactIds: mutation.resultRef.clientFinancialFactIds,
      teacherFinancialFactId: mutation.resultRef.teacherFinancialFactId,
      financialDecision: mutation.resultRef.financialDecision,
      replayed: mutation.replayed,
    };
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
