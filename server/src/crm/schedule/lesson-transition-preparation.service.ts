import {
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import {
  LESSON_SETTLEMENT_PORT,
  type LessonSettlementPort,
} from "../commerce/lesson-settlement.port";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import type { LessonDraftInput } from "./lesson-draft.contracts";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonTransitionFinancialService } from "./lesson-transition-financial.service";
import { groupTransitionSuccessorDraft } from "./lesson-transition-group-draft";
import {
  draftProjection,
  effectiveTransitionDto,
  hasTransitionClientCharge,
  legacyPlanTeacherSource,
  selectedTransitionSubscriptionIds,
  sourceProjection,
  transitionDecisionForResolution,
  transitionFinancialProjection,
  transitionFingerprint,
} from "./lesson-transition.rules";
import type {
  CalculatedTransitionPreview,
  ResolvedTransitionDto,
  TransitionLessonRow,
  TransitionOperation,
  TransitionPreviewDto,
  TransitionSource,
  TransitionSuccessor,
} from "./lesson-transition.types";

type CompleteCommonSnapshotRow = TransitionLessonRow & {
  completion_type: string;
  teacher_compensation_type: "fixed" | "hourly" | "none";
  teacher_compensation_value: number | string;
  snapshot_trial: boolean;
  validation_state: "valid" | "legacy_incomplete";
};

type CompleteIndividualSnapshotRow = TransitionLessonRow & {
  snapshot_group_id: null;
  snapshot_client_type: "lead" | "student";
  snapshot_client_id: string;
  client_charge_type: "subscription" | "personal_account" | "none";
  client_charge_value: number | string;
};

@Injectable()
export class LessonTransitionPreparationService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly validator: LessonRequiredFieldValidator,
    private readonly constraints: ScheduleConstraintEngine,
    @Inject(LESSON_SETTLEMENT_PORT)
    private readonly settlement: LessonSettlementPort,
    private readonly reservations: SubscriptionReservationService,
    private readonly financial: LessonTransitionFinancialService,
  ) {}

  async loadSource(
    lessonId: string,
    client?: PoolClient,
    lock = false,
  ): Promise<TransitionSource> {
    const query = client
      ? client.query.bind(client)
      : this.database.query.bind(this.database);
    const result = await query<TransitionLessonRow>(
      `
        select lesson.id, lesson.version, lesson.lifecycle_state,
          lesson.student_id, lesson.lead_id, lesson.group_id as lesson_group_id,
          lesson.teacher_id, lesson.branch_id, lesson.room_id,
          lesson.scheduled_at, lesson.duration_minutes, lesson.is_trial,
          lesson.notes, snapshot.client_type as snapshot_client_type,
          snapshot.client_id as snapshot_client_id,
          snapshot.group_id as snapshot_group_id, snapshot.completion_type,
          snapshot.client_charge_type, snapshot.client_charge_value,
          snapshot.teacher_compensation_type,
          snapshot.teacher_compensation_value, snapshot.subscription_id,
          snapshot.trial as snapshot_trial, snapshot.validation_state,
          coalesce((
            select jsonb_agg(jsonb_build_object(
              'studentId', participant.student_id,
              'chargeType', participant.charge_type,
              'chargeValue', participant.charge_value,
              'subscriptionId', participant.subscription_id
            ) order by participant.student_id)
            from app.lesson_snapshot_participants participant
            where participant.lesson_id = lesson.id
          ), '[]'::jsonb) as participants
        from app.lessons lesson
        left join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
        where lesson.id = $1 and lesson.deleted_at is null
        ${lock ? "for update of lesson" : ""}
      `,
      [lessonId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    return this.mapSource(row);
  }

  assertSource(
    source: TransitionSource,
    expectedVersion: number,
    operation: TransitionOperation,
  ): void {
    if (source.version !== expectedVersion) {
      throw new ConflictException({
        code: "STALE_LESSON_VERSION",
        expectedVersion,
        currentVersion: source.version,
      });
    }
    this.assertTransitionAllowed(source, operation);
    this.assertCompleteSnapshot(source);
  }

  async assertSettlementReviewPlan(
    client: PoolClient,
    lessonId: string,
    operation: TransitionOperation,
  ): Promise<void> {
    if (operation !== "settle") return;
    const plan = await this.settlement.loadPlan(client, lessonId, true);
    if (plan?.state !== "review_required") {
      throw new ConflictException({
        code: "LESSON_SETTLEMENT_REVIEW_NOT_REQUIRED",
        state: plan?.state ?? "missing",
      });
    }
  }

  successorDraft(
    dto: LessonDraftInput,
    source: TransitionSource,
  ): TransitionSuccessor {
    if (source.groupId) return groupTransitionSuccessorDraft(dto, source);
    return { kind: "individual", ...this.validator.update(dto, source) };
  }

  async validateSuccessor(
    client: PoolClient,
    lessonId: string,
    successor: TransitionSuccessor,
  ): Promise<{ valid: boolean; violations: unknown[] }> {
    const clients =
      successor.kind === "individual"
        ? [successor.clientRef]
        : successor.participants.map((participant) => ({
            type: "student" as const,
            id: participant.studentId,
          }));
    const validations = await Promise.all(
      clients.map((clientRef) =>
        this.constraints.validate(
          {
            clientRef,
            teacherId: successor.teacherId,
            branchId: successor.branchId,
            roomId: successor.roomId,
            startAt: successor.scheduledAt,
            endAt: successor.endAt,
            excludeLessonId: lessonId,
          },
          client,
        ),
      ),
    );
    const violations = Array.from(
      new Map(
        validations
          .flatMap((validation) => validation.violations)
          .map((violation) => [JSON.stringify(violation), violation]),
      ).values(),
    );
    return { valid: violations.length === 0, violations };
  }

  async calculatePreview(
    client: PoolClient,
    actor: ActorContext,
    lessonId: string,
    dto: TransitionPreviewDto,
    operation: TransitionOperation,
  ): Promise<CalculatedTransitionPreview> {
    const source = await this.loadSource(lessonId, client, true);
    this.assertSource(source, dto.expectedVersion, operation);
    await this.assertSettlementReviewPlan(client, lessonId, operation);
    const resolvedDto = await this.resolvedEffectiveTransitionDto(
      client,
      actor,
      source,
      operation,
      dto,
    );
    const successor =
      operation === "reschedule"
        ? this.successorDraft(dto.successor!, source)
        : null;
    const validation = successor
      ? await this.validateSuccessor(client, lessonId, successor)
      : { valid: true, violations: [] };
    const base: CalculatedTransitionPreview = {
      operation,
      source: sourceProjection(source),
      successor: successor ? draftProjection(successor) : null,
      financialDecision: resolvedDto.financialDecision,
      violations: validation.violations,
      canConfirm: validation.valid,
      confirmRequired: true,
    };
    if (!validation.valid) return base;
    const coverage = await this.reservations.lockSettlementCoverage(
      client,
      lessonId,
      selectedTransitionSubscriptionIds(resolvedDto),
    );
    const settled = await this.financial.previewFinancial(
      client,
      actor,
      source,
      lessonId,
      operation,
      resolvedDto,
    );
    const financial = transitionFinancialProjection(settled);
    return {
      ...base,
      financialPreview: financial,
      warnings:
        source.lifecycleState === "successfully_completed"
          ? ["COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED"]
          : successor && hasTransitionClientCharge(financial)
            ? ["SUCCESSOR_MAY_CHARGE_AGAIN"]
            : [],
      transitionFingerprint: transitionFingerprint({
        operation,
        source,
        successor,
        dto: resolvedDto,
        coverage,
        financial,
      }),
    };
  }

  async resolvedEffectiveTransitionDto(
    client: PoolClient,
    actor: ActorContext,
    source: TransitionSource,
    operation: TransitionOperation,
    dto: TransitionPreviewDto,
  ): Promise<ResolvedTransitionDto> {
    this.assertRawCompletedRescheduleTeacherDecision(
      actor,
      source,
      operation,
      dto,
    );
    return this.resolvedTransitionDto(
      client,
      actor,
      source,
      operation,
      effectiveTransitionDto(source, dto, operation),
    );
  }

  private assertRawCompletedRescheduleTeacherDecision(
    actor: ActorContext,
    source: TransitionSource,
    operation: TransitionOperation,
    dto: TransitionPreviewDto,
  ): void {
    if (!this.isCompletedReschedule(source, operation)) return;
    this.policy.assertCanSupplyTeacherCompensation(
      actor,
      dto.financialDecision,
    );
  }

  private async resolvedTransitionDto(
    client: PoolClient,
    actor: ActorContext,
    source: TransitionSource,
    operation: TransitionOperation,
    dto: TransitionPreviewDto,
  ): Promise<ResolvedTransitionDto> {
    const preservedTeacherDecision = await this.teacherDecisionToPreserve(
      client,
      actor,
      source,
      operation,
    );
    const prepared = await this.settlement.resolvePlannedPlan(client, {
      branchId: source.branchId!,
      durationMinutes: source.durationMinutes,
      decision: transitionDecisionForResolution(
        dto.financialDecision,
        Boolean(preservedTeacherDecision),
      ),
      actorUserId: actor.userId,
      authorization:
        this.policy.teacherCompensationMutationAuthorization(actor),
      reasonText: dto.reasonText,
      ...(preservedTeacherDecision ? { preservedTeacherDecision } : {}),
    });
    const teacherCompensationSource =
      prepared.decision.teacherCompensationSource;
    if (!teacherCompensationSource) {
      throw new ConflictException({
        code: "TEACHER_COMPENSATION_SOURCE_UNRESOLVED",
      });
    }
    return {
      ...dto,
      financialDecision: {
        ...prepared.decision,
        teacherCompensationSource,
      },
      configurationRevisionIds: {
        settlementRevisionId: prepared.settlementRevisionId,
        compensationRevisionId: prepared.compensationRevisionId,
      },
    };
  }

  private async teacherDecisionToPreserve(
    client: PoolClient,
    actor: ActorContext,
    source: TransitionSource,
    operation: TransitionOperation,
  ) {
    if (this.policy.canManageTeacherCompensation(actor)) return undefined;
    if (
      operation === "reschedule" &&
      source.lifecycleState === "successfully_completed"
    ) return undefined;
    return this.preservedTeacherDecision(client, source);
  }

  private async preservedTeacherDecision(
    client: PoolClient,
    source: TransitionSource,
  ): Promise<NonNullable<
    Parameters<LessonSettlementPort["resolvePlannedPlan"]>[1]["preservedTeacherDecision"]
  >> {
    const current = await this.settlement.loadPlan(client, source.id, true);
    if (current) {
      return {
        teacherCompensationRuleKey:
          current.decision.teacherCompensationRuleKey,
        teacherCompensationValueMinor:
          current.decision.teacherCompensationValueMinor,
        teacherCreditedDurationMinutes:
          current.decision.teacherCreditedDurationMinutes,
        teacherCompensationSource:
          current.decision.teacherCompensationSource ??
          legacyPlanTeacherSource(current.decision),
      };
    }
    const snapshot = source.groupId ? source.groupSnapshot : source.snapshot;
    return {
      teacherCompensationRuleKey:
        snapshot?.teacherCompensationType === "none" ? "none" : "standard",
      teacherCompensationSource: "automatic",
    };
  }

  private mapSource(row: TransitionLessonRow): TransitionSource {
    const commonSnapshot = this.commonSnapshot(row);
    return {
      id: row.id,
      version: Number(row.version),
      lifecycleState: row.lifecycle_state,
      studentId: row.student_id,
      leadId: row.lead_id,
      groupId:
        row.snapshot_group_id === row.lesson_group_id
          ? row.snapshot_group_id
          : null,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      scheduledAt: row.scheduled_at,
      durationMinutes: Number(row.duration_minutes),
      isTrial: row.is_trial,
      notes: row.notes,
      snapshot: this.individualSnapshot(row, commonSnapshot),
      groupSnapshot:
        row.snapshot_group_id && commonSnapshot ? commonSnapshot : null,
      participants: (row.participants ?? []).map((participant) => ({
        ...participant,
        chargeValue: Number(participant.chargeValue),
      })),
    };
  }

  private commonSnapshot(row: TransitionLessonRow) {
    if (!this.hasCommonSnapshot(row)) return null;
    return {
      completionType: row.completion_type,
      teacherCompensationType: row.teacher_compensation_type,
      teacherCompensationValue: Number(row.teacher_compensation_value),
      trial: row.snapshot_trial,
      validationState: row.validation_state,
    };
  }

  private individualSnapshot(
    row: TransitionLessonRow,
    common: ReturnType<LessonTransitionPreparationService["commonSnapshot"]>,
  ) {
    if (!common) return null;
    if (!this.hasIndividualSnapshot(row)) return null;
    return {
      clientType: row.snapshot_client_type,
      clientId: row.snapshot_client_id,
      ...common,
      clientChargeType: row.client_charge_type,
      clientChargeValue: Number(row.client_charge_value),
      subscriptionId: row.subscription_id,
    };
  }

  private hasCommonSnapshot(
    row: TransitionLessonRow,
  ): row is CompleteCommonSnapshotRow {
    if (!row.completion_type) return false;
    if (!row.teacher_compensation_type) return false;
    if (row.teacher_compensation_value === null) return false;
    if (row.snapshot_trial === null) return false;
    return Boolean(row.validation_state);
  }

  private hasIndividualSnapshot(
    row: TransitionLessonRow,
  ): row is CompleteIndividualSnapshotRow {
    if (row.snapshot_group_id) return false;
    if (!row.snapshot_client_type) return false;
    if (!row.snapshot_client_id) return false;
    if (!row.client_charge_type) return false;
    if (row.client_charge_value === null) return false;
    return true;
  }

  private assertTransitionAllowed(
    source: TransitionSource,
    operation: TransitionOperation,
  ): void {
    if (
      this.isSettleAllowed(source, operation) ||
      this.isOrdinaryTransitionAllowed(source, operation) ||
      this.isCompletedReschedule(source, operation)
    )
      return;
    throw new ConflictException({
      code:
        operation === "settle"
          ? "LESSON_SETTLEMENT_REVIEW_NOT_REQUIRED"
          : "LESSON_ALREADY_TERMINAL",
      state: source.lifecycleState,
    });
  }

  private isSettleAllowed(
    source: TransitionSource,
    operation: TransitionOperation,
  ): boolean {
    return (
      operation === "settle" && source.lifecycleState === "settlement_pending"
    );
  }

  private isOrdinaryTransitionAllowed(
    source: TransitionSource,
    operation: TransitionOperation,
  ): boolean {
    return (
      operation !== "settle" &&
      ["scheduled", "settlement_pending"].includes(source.lifecycleState)
    );
  }

  private isCompletedReschedule(
    source: TransitionSource,
    operation: TransitionOperation,
  ): boolean {
    return (
      operation === "reschedule" &&
      source.lifecycleState === "successfully_completed"
    );
  }

  private assertCompleteSnapshot(source: TransitionSource): void {
    const individualValid =
      source.snapshot?.validationState === "valid" && !source.groupId;
    const groupValid =
      source.groupSnapshot?.validationState === "valid" &&
      Boolean(source.groupId) &&
      source.participants.length > 0;
    if (individualValid || groupValid) return;
    throw new UnprocessableEntityException({
      code: "LESSON_SNAPSHOT_INCOMPLETE",
      fields: ["snapshot"],
    });
  }
}
