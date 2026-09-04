import {
  ConflictException,
  Injectable,
  NotFoundException,
  Optional,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import type {
  VersionedMutationCommand,
  VersionedMutationResult,
} from "../../platform/platform-integrity.types";
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
import { LessonActionableChainService } from "./lesson-actionable-chain.service";
import type { LessonActionableResolution } from "./lesson-actionable-chain.service";
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

type SignedTransitionPreview = ReturnType<
  SubscriptionPreviewTokenService["verifyLessonTransition"]
>;

interface VerifiedPreviewState {
  signed?: SignedTransitionPreview;
}

@Injectable()
export class LessonTransitionCommandService {
  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly previewTokens: SubscriptionPreviewTokenService,
    private readonly commits: LessonTransitionCommitService,
    private readonly reservations: SubscriptionReservationService,
    @Optional()
    private readonly actionableChains?: LessonActionableChainService,
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
    const resolution = await this.resolveInitial(actor, lessonId);
    const actionableLessonId = resolution.actionableLessonId;
    const successorId = this.successorIdFor(
      operation,
      actionableLessonId,
      actor.userId,
      metadata.idempotencyKey,
    );
    const verifiedPreview: VerifiedPreviewState = {};
    const mutationCommand = this.buildMutationCommand({
      actor,
      requestedLessonId: lessonId,
      actionableLessonId,
      resolution,
      dto,
      operation,
      metadata,
      successorId,
      verifiedPreview,
    });
    const mutation = await this.executeWithReplay(
      mutationCommand,
      dto,
      resolution,
      actionableLessonId,
    );
    return this.toCommandResult(mutation);
  }

  private buildMutationCommand(input: {
    actor: ActorContext;
    requestedLessonId: string;
    actionableLessonId: string;
    resolution: LessonActionableResolution;
    dto: TransitionCommandDto;
    operation: TransitionOperation;
    metadata: LessonCommandMetadata;
    successorId: string | null;
    verifiedPreview: VerifiedPreviewState;
  }): VersionedMutationCommand<CommittedTransition> {
    const {
      actor,
      requestedLessonId,
      actionableLessonId,
      resolution,
      dto,
      operation,
      metadata,
      successorId,
      verifiedPreview,
    } = input;
    return {
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization:
        this.policy.teacherCompensationMutationAuthorization(actor),
      operation: `schedule.lesson.${operation}`,
      idempotencyKey: metadata.idempotencyKey,
      payload: { lessonId: requestedLessonId, dto },
      aggregateType: "schedule:lesson",
      aggregateId: actionableLessonId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: operation === "reschedule"
          ? "crm.lesson_rescheduled"
          : operation === "cancel"
            ? "crm.lesson_cancelled"
            : "crm.lesson_settled",
        entityType: "lesson",
        entityId: actionableLessonId,
        reason: transitionReasonCode(dto),
        reasonText: dto.reasonText?.trim(),
        beforeRef: {
          requestedLessonId,
          lessonId: actionableLessonId,
          version: dto.expectedVersion,
        },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: {
          entityId: actionableLessonId,
          action: this.outboxAction(operation),
          state: targetTransitionState(operation),
          successorId,
        },
      },
      beforeVersionAdvance: async (client) => {
        verifiedPreview.signed = await this.revalidateAndVerify(
          client,
          actor,
          requestedLessonId,
          actionableLessonId,
          resolution,
          dto,
          operation,
        );
      },
      mutate: async (client, nextVersion) => {
        const signedPreview = this.requireSignedPreview(verifiedPreview);
        return this.commitConfirmed(
          client,
          actor,
          actionableLessonId,
          dto,
          successorId,
          nextVersion,
          signedPreview.transitionFingerprint,
        );
      },
    };
  }

  private async executeWithReplay(
    command: VersionedMutationCommand<CommittedTransition>,
    dto: TransitionCommandDto,
    resolution: LessonActionableResolution,
    actionableLessonId: string,
  ): Promise<VersionedMutationResult<CommittedTransition>> {
    try {
      return await this.executeWithReplayIdentity(
        command,
        dto,
        resolution,
        actionableLessonId,
      );
    } catch (error) {
      throw this.mapVersionConflict(error, dto.expectedVersion);
    }
  }

  private async executeWithReplayIdentity(
    command: VersionedMutationCommand<CommittedTransition>,
    dto: TransitionCommandDto,
    resolution: LessonActionableResolution,
    actionableLessonId: string,
  ): Promise<VersionedMutationResult<CommittedTransition>> {
    try {
      return await this.runVersionedMutation(command);
    } catch (error) {
      if (this.conflictCode(error) !== "IDEMPOTENCY_KEY_REUSED") throw error;
      const replayIdentity = this.previewTokens.verifyLessonTransition(
        dto.previewToken,
      );
      if (
        replayIdentity.lessonId === actionableLessonId ||
        !resolution.chainIds.includes(replayIdentity.lessonId)
      ) {
        throw error;
      }
      return this.runVersionedMutation({
        ...command,
        aggregateId: replayIdentity.lessonId,
      });
    }
  }

  private async toCommandResult(
    mutation: VersionedMutationResult<CommittedTransition>,
  ): Promise<LessonTransitionCommandResult> {
    const committedSourceId = mutation.resultRef.lessonId;
    const committedSuccessorId = mutation.resultRef.successorId;
    await this.reservations.publishLessonSettlementPostCommit(committedSourceId);
    if (committedSuccessorId) {
      await this.reservations.publishLessonSettlementPostCommit(
        committedSuccessorId,
      );
    }
    const financialProjection = this.financialProjection(mutation.resultRef);
    return {
      source: {
        id: committedSourceId,
        state: mutation.resultRef.state,
        version: mutation.version,
      },
      successor:
        committedSuccessorId === null
          ? null
          : { id: committedSuccessorId, state: "scheduled", version: 1 },
      transitionId: mutation.resultRef.transitionId,
      clientFinancialFactIds: mutation.resultRef.clientFinancialFactIds,
      teacherFinancialFactId: mutation.resultRef.teacherFinancialFactId,
      ...financialProjection,
      replayed: mutation.replayed,
    };
  }

  private async resolveInitial(
    actor: ActorContext,
    lessonId: string,
  ): Promise<LessonActionableResolution> {
    const identity = this.identityResolution(lessonId);
    if (!this.actionableChains) return identity;
    try {
      return await this.actionableChains.resolve(actor, lessonId);
    } catch (error) {
      if (error instanceof NotFoundException) return identity;
      throw error;
    }
  }

  private async revalidateAndVerify(
    client: PoolClient,
    actor: ActorContext,
    requestedLessonId: string,
    actionableLessonId: string,
    initialResolution: LessonActionableResolution,
    dto: TransitionCommandDto,
    operation: TransitionOperation,
  ): Promise<SignedTransitionPreview> {
    await acquireLessonSettlementCoordinationGate(client);
    const lockedResolution = this.actionableChains
      ? await this.actionableChains.resolve(actor, requestedLessonId, client)
      : initialResolution;
    if (lockedResolution.actionableLessonId !== actionableLessonId) {
      throw this.alreadyRescheduled(
        requestedLessonId,
        lockedResolution.actionableLessonId,
      );
    }
    const signed = this.previewTokens.verifyLessonTransition(dto.previewToken);
    if (
      signed.lessonId !== actionableLessonId &&
      lockedResolution.chainIds.includes(signed.lessonId)
    ) {
      throw this.alreadyRescheduled(requestedLessonId, actionableLessonId);
    }
    this.assertSignedPreview(signed, actor, actionableLessonId, dto, operation);
    return signed;
  }

  private identityResolution(lessonId: string): LessonActionableResolution {
    return {
      requestedLessonId: lessonId,
      actionableLessonId: lessonId,
      chainIds: [lessonId],
      redirected: false,
    };
  }

  private successorIdFor(
    operation: TransitionOperation,
    lessonId: string,
    actorUserId: string,
    idempotencyKey: string,
  ): string | null {
    if (operation !== "reschedule") return null;
    return stableTransitionId(
      `schedule.lesson.reschedule\0${lessonId}\0${actorUserId}\0${idempotencyKey}`,
    );
  }

  private outboxAction(operation: TransitionOperation): string {
    if (operation === "reschedule") return "rescheduled";
    if (operation === "cancel") return "cancelled";
    return "settled";
  }

  private requireSignedPreview(state: VerifiedPreviewState): SignedTransitionPreview {
    if (state.signed) return state.signed;
    throw new Error("Lesson transition preview was not verified.");
  }

  private alreadyRescheduled(
    requestedLessonId: string,
    actionableLessonId: string,
  ): ConflictException {
    return new ConflictException({
      code: "LESSON_ALREADY_RESCHEDULED",
      requestedLessonId,
      actionableLessonId,
    });
  }

  private mapVersionConflict(error: unknown, expectedVersion: number): unknown {
    const code = this.conflictCode(error);
    if (code !== "STALE_VERSION" && code !== "STALE_LESSON_VERSION") {
      return error;
    }
    return new ConflictException({
      code: "LESSON_VERSION_STALE",
      expectedVersion,
    });
  }

  private financialProjection(committed: CommittedTransition) {
    if (committed.state !== "rescheduled") {
      return { financialDecision: committed.financialDecision };
    }
    return {
      financialDecision: committed.successorFinancialDecision,
      sourceFinancialDecision: committed.sourceFinancialDecision,
      successorFinancialDecision: committed.successorFinancialDecision,
    };
  }

  private runVersionedMutation(
    command: VersionedMutationCommand<CommittedTransition>,
  ): Promise<VersionedMutationResult<CommittedTransition>> {
    return this.platform.executeVersionedMutation(command);
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

  private conflictCode(error: unknown): string | undefined {
    if (!(error instanceof ConflictException)) return undefined;
    const response = error.getResponse();
    return typeof response === "object" && response !== null &&
        "code" in response && typeof response.code === "string"
      ? response.code
      : undefined;
  }
}
