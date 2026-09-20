import {
  ConflictException,
  Inject,
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import { assertActiveClientReferences } from "../clients/client-reference.service";
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
  ResolvedTransitionDto,
  TerminalTransitionState,
  TransitionOperation,
  TransitionSource,
  TransitionSuccessor,
} from "./lesson-transition.types";

type CommittedTransitionFacts = Pick<
  CommittedTransition,
  | "lessonId"
  | "transitionId"
  | "clientFinancialFactIds"
  | "teacherFinancialFactId"
>;

const committedTransition = (
  facts: CommittedTransitionFacts,
  successorId: string | null,
  dto: ResolvedTransitionDto,
  fingerprint: string,
): CommittedTransition => dto.operation === "reschedule"
  ? {
      ...facts,
      state: "rescheduled",
      successorId: successorId!,
      financialDecision: dto.successorFinancialDecision,
      sourceFinancialDecision: dto.sourceFinancialDecision,
      successorFinancialDecision: dto.successorFinancialDecision,
      transitionFingerprint: fingerprint,
    }
  : {
      ...facts,
      state: dto.operation === "cancel" ? "cancelled" : "successfully_completed",
      successorId: null,
      financialDecision: dto.financialDecision,
      transitionFingerprint: fingerprint,
    };

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
    const successor =
      input.operation === "reschedule"
        ? this.preparation.successorDraft(input.dto.successor!, source)
        : null;
    if (successor) {
      await this.acquireLocks(client, source, successor);
      await assertActiveClientReferences(
        client,
        successor.kind === "individual"
          ? [successor.clientRef]
          : successor.participants.map((participant) => ({
              type: "student" as const,
              id: participant.studentId,
            })),
      );
      await this.assertValidSuccessor(client, input.lessonId, successor);
    }
    const dto = await this.preparation.resolvedEffectiveTransitionDto(
      client,
      input.actor,
      source,
      input.operation,
      input.dto,
    );
    const coverage = await this.reservations.lockSettlementCoverage(
      client,
      input.lessonId,
      selectedTransitionSubscriptionIds(dto),
    );
    if (successor) {
      await this.insertSuccessor(
        client,
        input.successorId!,
        input.lessonId,
        successor,
        input.actor.userId,
        dto.operation === "reschedule"
          ? dto.successorFinancialDecision.teacherRateSnapshot
          : undefined,
      );
    }
    let settled: LessonSettlementResult;
    if (dto.operation === "reschedule") {
      const rescheduleFinancials = await this.financial.commitRescheduleFinancials(
        client,
        source,
        input.successorId!,
        {
          actor: input.actor,
          reasonText: dto.reasonText,
          sourceFinancialDecision: dto.sourceFinancialDecision,
          successorFinancialDecision: dto.successorFinancialDecision,
          sourceConfigurationRevisionIds: dto.sourceConfigurationRevisionIds,
          successorConfigurationRevisionIds:
            dto.successorConfigurationRevisionIds,
          coverage,
          correctionId: stableTransitionId(
            `schedule.lesson.completed-reschedule-correction\0${input.lessonId}\0${input.successorId}`,
          ),
        },
      );
      settled = rescheduleFinancials.sourceSettlement;
    } else {
      settled = await this.settleSource(client, input, dto);
    }
    const fingerprint = transitionFingerprint({
      operation: input.operation,
      source,
      successor,
      dto,
      coverage,
      financial: transitionFinancialProjection(settled),
    });
    this.assertExpectedFingerprint(input.expectedFingerprint, fingerprint);
    if (dto.operation === "reschedule") {
      await this.updateSource(
        client,
        input.lessonId,
        input.dto.expectedVersion,
        input.nextVersion,
        targetTransitionState(input.operation),
        input.successorId,
        input.operation,
      );
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
    const committed = committedTransition({
      lessonId: input.lessonId,
      transitionId: String(transition.rows[0]!.id),
      clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
      teacherFinancialFactId: settled.teacherFact.id,
    }, input.successorId, dto, fingerprint);
    // Bulk validation reads the fingerprint before Platform Integrity serializes
    // the result. Keeping it non-enumerable preserves that reconciliation input
    // without copying the hash into audit or idempotency JSON.
    Object.defineProperty(committed, "transitionFingerprint", {
      value: fingerprint,
      enumerable: false,
      writable: false,
      configurable: false,
    });
    return committed;
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
    dto: ResolvedTransitionDto,
  ): Promise<LessonSettlementResult> {
    await this.updateSource(
      client,
      input.lessonId,
      input.dto.expectedVersion,
      input.nextVersion,
      targetTransitionState(input.operation),
      input.successorId,
      input.operation,
    );
    if (dto.operation === "reschedule") {
      throw new Error("Reschedule financials must use the atomic commit path.");
    }
    const decision = dto.financialDecision;
    const configurationRevisionIds = dto.configurationRevisionIds;
    const settled = await this.settlement.settle(client, input.lessonId, {
      context: input.operation,
      decision,
      reasonText: dto.reasonText?.trim(),
      configurationRevisionIds,
    });
    await this.reservations.terminalize(client, settled);
    if (input.operation === "settle") {
      await this.settlement.markPlanState(client, input.lessonId, "settled");
    }
    return settled;
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
    teacherRateSnapshot?: { type: "hourly"; value: string },
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
        teacherRateSnapshot?.value ?? (draft.teacherCompensationType === "none"
          ? null
          : draft.teacherCompensationValue),
        sourceId,
        actorUserId,
      ],
    );
    await this.createSuccessorSnapshot(
      client,
      successorId,
      draft,
      teacherRateSnapshot,
    );
  }

  private async createSuccessorSnapshot(
    client: PoolClient,
    successorId: string,
    draft: TransitionSuccessor,
    teacherRateSnapshot?: { type: "hourly"; value: string },
  ): Promise<void> {
    if (draft.kind === "group") {
      await this.lifecycle.createGroupSnapshot(client, {
        lessonId: successorId,
        groupId: draft.groupId,
        completionType: draft.completionType,
        teacherCompensationType:
          teacherRateSnapshot?.type ?? draft.teacherCompensationType,
        teacherCompensationValue: teacherRateSnapshot
          ? Number(teacherRateSnapshot.value)
          : draft.teacherCompensationValue,
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
      teacherCompensationType:
        teacherRateSnapshot?.type ?? draft.teacherCompensationType,
      teacherCompensationValue: teacherRateSnapshot
        ? Number(teacherRateSnapshot.value)
        : draft.teacherCompensationValue,
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
