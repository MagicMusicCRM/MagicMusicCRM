import {
  ConflictException,
  Inject,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import {
  LESSON_SETTLEMENT_PORT,
  type LessonSettlementPort,
  type LessonSettlementResult,
} from "../commerce/lesson-settlement.port";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonTransitionFinancialService } from "./lesson-transition-financial.service";
import { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import {
  effectiveTransitionDto,
  normalizedTransitionDecision,
  selectedTransitionSubscriptionIds,
  stableTransitionId,
  targetTransitionState,
  transitionAdvisoryKeys,
  transitionFinancialProjection,
  transitionFingerprint,
  transitionReasonCode,
} from "./lesson-transition.rules";
import type {
  CommitTransitionInput,
  CommittedTransition,
  TerminalTransitionState,
  TransitionOperation,
  TransitionSource,
  TransitionSuccessor,
} from "./lesson-transition.types";

@Injectable()
export class LessonTransitionCommitService {
  constructor(
    private readonly preparation: LessonTransitionPreparationService,
    private readonly financial: LessonTransitionFinancialService,
    @Inject(LESSON_SETTLEMENT_PORT)
    private readonly settlement: LessonSettlementPort,
    private readonly reservations: SubscriptionReservationService,
    private readonly lifecycle: LessonLifecycleRepository,
  ) {}

  async commit(
    client: PoolClient,
    input: CommitTransitionInput,
  ): Promise<CommittedTransition> {
    const source = await this.preparation.loadSource(
      input.lessonId,
      client,
      true,
    );
    this.preparation.assertSource(
      source,
      input.dto.expectedVersion,
      input.operation,
    );
    await this.preparation.assertSettlementReviewPlan(
      client,
      input.lessonId,
      input.operation,
    );
    const authorizedDto = await this.preparation.authorizedTransitionDto(
      client,
      input.actor,
      source,
      input.dto,
    );
    const dto = effectiveTransitionDto(source, authorizedDto, input.operation);
    const successor =
      input.operation === "reschedule"
        ? this.preparation.successorDraft(authorizedDto.successor!, source)
        : null;
    if (successor) {
      await this.acquireLocks(client, source, successor);
      await this.assertValidSuccessor(client, input.lessonId, successor);
    }
    const coverage = await this.reservations.lockSettlementCoverage(
      client,
      input.lessonId,
      selectedTransitionSubscriptionIds(dto),
    );
    if (successor && input.successorId) {
      await this.insertSuccessor(
        client,
        input.successorId,
        input.lessonId,
        successor,
        input.actor.userId,
      );
    }
    const settled = await this.settleSource(client, input, source, dto);
    const fingerprint = transitionFingerprint({
      operation: input.operation,
      source,
      successor,
      dto,
      coverage,
      financial: transitionFinancialProjection(settled),
    });
    this.assertExpectedFingerprint(input.expectedFingerprint, fingerprint);
    if (successor && input.successorId) {
      await this.financial.cloneAndAllocateSuccessor(
        client,
        input.lessonId,
        input.successorId,
        input.actor,
        dto.reasonText,
        successor.branchId,
        dto.financialDecision,
      );
    }
    if (source.lifecycleState === "successfully_completed") {
      await this.updateCompletedSource(client, input);
    }
    const toState = targetTransitionState(input.operation);
    const transition = await this.lifecycle.appendTransition(client, {
      lessonId: input.lessonId,
      fromState: source.lifecycleState as
        "scheduled" | "settlement_pending" | "successfully_completed",
      toState,
      reasonCode: transitionReasonCode(dto),
      reasonText: dto.reasonText?.trim(),
      actorUserId: input.actor.userId,
      successorId: input.successorId ?? undefined,
      financialDecision: normalizedTransitionDecision(dto),
      clientFinancialFactId: settled.clientFact.id,
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
    });
    return {
      lessonId: input.lessonId,
      state: toState,
      successorId: input.successorId,
      transitionId: String(transition.rows[0]!.id),
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
      financialDecision: dto.financialDecision,
      transitionFingerprint: fingerprint,
    };
  }

  private async assertValidSuccessor(
    client: PoolClient,
    lessonId: string,
    successor: TransitionSuccessor,
  ): Promise<void> {
    const validation = await this.preparation.validateSuccessor(
      client,
      lessonId,
      successor,
    );
    if (!validation.valid) {
      throw new UnprocessableEntityException({
        code: "LESSON_CONSTRAINT_VIOLATIONS",
        message: "Successor lesson violates schedule constraints.",
        violations: validation.violations,
      });
    }
  }

  private async settleSource(
    client: PoolClient,
    input: CommitTransitionInput,
    source: TransitionSource,
    dto: CommitTransitionInput["dto"],
  ): Promise<LessonSettlementResult> {
    if (source.lifecycleState === "successfully_completed") {
      return this.financial.applyCompletedRescheduleCorrection(
        client,
        source,
        input.actor,
        dto,
        stableTransitionId(
          `schedule.lesson.completed-reschedule-correction\0${input.lessonId}\0${input.successorId}`,
        ),
      );
    }
    await this.updateSource(
      client,
      input.lessonId,
      input.dto.expectedVersion,
      input.nextVersion,
      targetTransitionState(input.operation),
      input.successorId,
      input.operation,
    );
    const settled = await this.settlement.settle(client, input.lessonId, {
      context: input.operation,
      decision: dto.financialDecision,
      reasonText: dto.reasonText?.trim(),
    });
    await this.reservations.terminalize(client, settled);
    if (input.operation === "settle") {
      await this.settlement.markPlanState(client, input.lessonId, "settled");
    }
    return settled;
  }

  private updateCompletedSource(
    client: PoolClient,
    input: CommitTransitionInput,
  ): Promise<void> {
    return this.updateSource(
      client,
      input.lessonId,
      input.dto.expectedVersion,
      input.nextVersion,
      targetTransitionState(input.operation),
      input.successorId,
      input.operation,
    );
  }

  private async acquireLocks(
    client: PoolClient,
    source: TransitionSource,
    successor: TransitionSuccessor,
  ): Promise<void> {
    for (const key of transitionAdvisoryKeys(source, successor)) {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [key],
      );
    }
  }

  private async insertSuccessor(
    client: PoolClient,
    successorId: string,
    sourceId: string,
    draft: TransitionSuccessor,
    actorUserId: string,
  ): Promise<void> {
    await client.query(
      `
        insert into app.lessons (
          id, student_id, lead_id, group_id, teacher_id, branch_id, room_id,
          scheduled_at, duration_minutes, status, is_trial, notes,
          teacher_rate, predecessor_id, created_by
        ) values (
          $1,
          case when $2 = 'student' then $3::uuid else null end,
          case when $2 = 'lead' then $3::uuid else null end,
          $4, $5, $6, $7, $8, $9, 'scheduled', $10, $11, $12, $13, $14
        )
      `,
      [
        successorId,
        draft.kind === "individual" ? draft.clientRef.type : null,
        draft.kind === "individual" ? draft.clientRef.id : null,
        draft.kind === "group" ? draft.groupId : null,
        draft.teacherId,
        draft.branchId,
        draft.roomId,
        draft.scheduledAt,
        draft.durationMinutes,
        draft.isTrial,
        draft.notes,
        draft.teacherCompensationType === "none"
          ? null
          : draft.teacherCompensationValue,
        sourceId,
        actorUserId,
      ],
    );
    await this.createSuccessorSnapshot(client, successorId, draft);
  }

  private async createSuccessorSnapshot(
    client: PoolClient,
    successorId: string,
    draft: TransitionSuccessor,
  ): Promise<void> {
    if (draft.kind === "group") {
      await this.lifecycle.createGroupSnapshot(client, {
        lessonId: successorId,
        groupId: draft.groupId,
        completionType: draft.completionType,
        teacherCompensationType: draft.teacherCompensationType,
        teacherCompensationValue: draft.teacherCompensationValue,
        trial: draft.isTrial,
        participants: draft.participants.map((participant) => ({
          studentId: participant.studentId,
          chargeType: participant.chargeType,
          chargeValue: participant.chargeValue,
          subscriptionId: participant.subscriptionId ?? undefined,
        })),
      });
      return;
    }
    await this.lifecycle.createSnapshot(client, {
      lessonId: successorId,
      clientType: draft.clientRef.type,
      clientId: draft.clientRef.id,
      completionType: draft.completionType,
      clientChargeType: draft.clientChargeType,
      clientChargeValue: draft.clientChargeValue,
      teacherCompensationType: draft.teacherCompensationType,
      teacherCompensationValue: draft.teacherCompensationValue,
      subscriptionId: draft.subscriptionId ?? undefined,
      trial: draft.isTrial,
    });
  }

  private async updateSource(
    client: PoolClient,
    lessonId: string,
    expectedVersion: number,
    nextVersion: number,
    toState: TerminalTransitionState,
    successorId: string | null,
    operation: TransitionOperation,
  ): Promise<void> {
    const updated = await client.query<{ version: number | string }>(
      `
        update app.lessons
        set lifecycle_state = $3, successor_id = $4, updated_at = now()
        where id = $1 and version = $2
          and (
            lifecycle_state in ('scheduled', 'settlement_pending')
            or ($5 = 'reschedule' and lifecycle_state = 'successfully_completed')
          )
        returning version
      `,
      [lessonId, expectedVersion, toState, successorId, operation],
    );
    if (!updated.rows[0] || Number(updated.rows[0].version) !== nextVersion) {
      throw new ConflictException({
        code: "STALE_LESSON_VERSION",
        expectedVersion,
      });
    }
  }

  private assertExpectedFingerprint(
    expected: string | undefined,
    actual: string,
  ): void {
    if (expected === undefined || expected === actual) return;
    throw new UnprocessableEntityException({
      code: "LESSON_TRANSITION_PREVIEW_STALE",
      message: "Lesson transition inputs changed after preview.",
    });
  }
}
