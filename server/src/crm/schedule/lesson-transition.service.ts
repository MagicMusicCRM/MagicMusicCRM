import {
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import {
  LESSON_SETTLEMENT_PORT,
  LessonSettlementPort,
  LessonSettlementResult,
} from "../commerce/lesson-settlement.port";
import {
  LessonSettlementCoverageSnapshot,
  SubscriptionReservationService,
} from "../commerce/subscription-reservation.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { CrmPolicy } from "../crm.policy";
import {
  LessonCancelCommandDto,
  LessonCancelPreviewDto,
  LessonRescheduleCommandDto,
  LessonReschedulePreviewDto,
  LessonSettleCommandDto,
  LessonSettlePreviewDto,
} from "../dto/lesson-transition.dto";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import type { LessonCommandMetadata } from "./lesson-command.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import {
  CompleteLessonDraft,
  ExistingLessonDraft,
  LessonRequiredFieldValidator,
} from "./lesson-required-field.validator";

type TransitionOperation = "reschedule" | "cancel" | "settle";
type TransitionState =
  | "scheduled"
  | "successfully_completed"
  | "cancelled"
  | "rescheduled";

interface GroupParticipantSnapshot {
  studentId: string;
  chargeType: "subscription" | "personal_account" | "none";
  chargeValue: number;
  subscriptionId: string | null;
}

interface TransitionLessonRow {
  id: string;
  version: number | string;
  lifecycle_state: TransitionState;
  student_id: string | null;
  lead_id: string | null;
  lesson_group_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  notes: string | null;
  snapshot_client_type: "lead" | "student" | null;
  snapshot_client_id: string | null;
  snapshot_group_id: string | null;
  completion_type: string | null;
  client_charge_type: "subscription" | "personal_account" | "none" | null;
  client_charge_value: number | string | null;
  teacher_compensation_type: "fixed" | "hourly" | "none" | null;
  teacher_compensation_value: number | string | null;
  subscription_id: string | null;
  snapshot_trial: boolean | null;
  validation_state: "valid" | "legacy_incomplete" | null;
  participants: GroupParticipantSnapshot[];
}

interface GroupLessonDraft {
  kind: "group";
  groupId: string;
  teacherId: string;
  branchId: string;
  roomId: string;
  scheduledAt: string;
  durationMinutes: number;
  endAt: string;
  isTrial: boolean;
  notes: string | null;
  completionType: string;
  teacherCompensationType: "fixed" | "hourly" | "none";
  teacherCompensationValue: number;
  participants: GroupParticipantSnapshot[];
}

type TransitionSuccessor =
  | (CompleteLessonDraft & { kind: "individual" })
  | GroupLessonDraft;

type TransitionSource = ExistingLessonDraft & {
  lifecycleState: TransitionState;
  groupId: string | null;
  groupSnapshot: {
    completionType: string;
    teacherCompensationType: "fixed" | "hourly" | "none";
    teacherCompensationValue: number;
    trial: boolean;
    validationState: "valid" | "legacy_incomplete";
  } | null;
  participants: GroupParticipantSnapshot[];
};

type TransitionPreviewDto =
  | LessonCancelPreviewDto
  | LessonReschedulePreviewDto
  | LessonSettlePreviewDto;
type TransitionCommandDto =
  | LessonCancelCommandDto
  | LessonRescheduleCommandDto
  | LessonSettleCommandDto;

export interface LessonTransitionPreviewResult {
  operation: TransitionOperation;
  source: { id: string; version: number; state: string };
  successor: Record<string, unknown> | null;
  financialDecision: TransitionPreviewDto["financialDecision"];
  violations: unknown[];
  canConfirm: boolean;
  confirmRequired: true;
  financialPreview?: unknown;
  warnings?: string[];
  previewToken?: string;
  previewExpiresAt?: string;
}

@Injectable()
export class LessonTransitionService {
  constructor(
    private readonly database: DatabaseService,
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly validator: LessonRequiredFieldValidator,
    private readonly constraints: ScheduleConstraintEngine,
    private readonly lifecycle: LessonLifecycleRepository,
    @Inject(LESSON_SETTLEMENT_PORT)
    private readonly settlement: LessonSettlementPort,
    private readonly reservations: SubscriptionReservationService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
  ) {}

  previewReschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonReschedulePreviewDto,
  ) {
    return this.preview(actor, lessonId, dto, "reschedule");
  }

  previewCancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelPreviewDto,
  ) {
    return this.preview(actor, lessonId, dto, "cancel");
  }

  previewSettle(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettlePreviewDto,
  ) {
    return this.preview(actor, lessonId, dto, "settle");
  }

  reschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonRescheduleCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.execute(actor, lessonId, dto, metadata, "reschedule");
  }

  cancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.execute(actor, lessonId, dto, metadata, "cancel");
  }

  settle(
    actor: ActorContext,
    lessonId: string,
    dto: LessonSettleCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    return this.execute(actor, lessonId, dto, metadata, "settle");
  }

  private async preview(
    actor: ActorContext,
    lessonId: string,
    dto: TransitionPreviewDto,
    operation: TransitionOperation,
  ): Promise<LessonTransitionPreviewResult> {
    this.policy.assertCanWriteCrm(actor);
    this.assertReason(dto, operation);
    return this.database.transaction(async (client) => {
      const source = await this.loadSource(lessonId, client, true);
      this.assertSource(source, dto.expectedVersion);
      const successor = operation === "reschedule"
        ? this.successorDraft(
            (dto as LessonReschedulePreviewDto).successor,
            source,
          )
        : null;
      const validation = successor
        ? await this.validateSuccessor(client, lessonId, successor)
        : { valid: true, violations: [] };
      const base = {
        operation,
        source: this.sourceProjection(source),
        successor: successor ? this.draftProjection(successor) : null,
        financialDecision: dto.financialDecision,
        violations: validation.violations,
        canConfirm: validation.valid,
        confirmRequired: true as const,
      };
      if (!validation.valid) return base;

      const coverage = await this.reservations.lockSettlementCoverage(
        client,
        lessonId,
        this.selectedSubscriptionIds(dto),
      );
      const financial = await this.previewFinancial(
        client,
        lessonId,
        operation,
        dto,
      );
      const financialPreview = this.financialProjection(financial);
      const transitionFingerprint = this.transitionFingerprint({
        operation,
        source,
        successor,
        dto,
        coverage,
        financial: financialPreview,
      });
      const signed = this.previewTokens.issueLessonTransition({
        kind: "lesson.transition",
        operation,
        actorUserId: actor.userId,
        lessonId,
        expectedVersion: dto.expectedVersion,
        transitionFingerprint,
      });
      return {
        ...base,
        financialPreview,
        warnings: successor && this.hasClientCharge(financial)
          ? ["SUCCESSOR_MAY_CHARGE_AGAIN"]
          : [],
        previewToken: signed.token,
        previewExpiresAt: signed.expiresAt,
      };
    });
  }

  private async execute(
    actor: ActorContext,
    lessonId: string,
    dto: TransitionCommandDto,
    metadata: LessonCommandMetadata,
    operation: TransitionOperation,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertConfirmed(dto.confirm);
    this.assertMetadata(metadata);
    this.assertReason(dto, operation);
    const toState = this.targetState(operation);
    const successorId = operation === "reschedule"
      ? this.stableId(
          `schedule.lesson.reschedule\0${lessonId}\0${actor.userId}\0${metadata.idempotencyKey}`,
        )
      : null;
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      authorization: {
        actor,
        capabilityKey: "schedule.lesson.write",
      },
      operation: `schedule.lesson.${operation}`,
      idempotencyKey: metadata.idempotencyKey,
      payload: { lessonId, dto },
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: operation === "reschedule"
          ? "crm.lesson_rescheduled"
          : operation === "cancel"
            ? "crm.lesson_cancelled"
            : "crm.lesson_settled",
        entityType: "lesson",
        entityId: lessonId,
        reason: this.reasonCode(dto),
        reasonText: dto.reasonText?.trim(),
        beforeRef: { lessonId, version: dto.expectedVersion, state: "scheduled" },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { entityId: lessonId, state: toState },
      },
      mutate: async (client, nextVersion) => {
        const signed = this.previewTokens.verifyLessonTransition(dto.previewToken);
        this.assertSignedPreview(signed, actor, lessonId, dto, operation);
        const source = await this.loadSource(lessonId, client, true);
        this.assertSource(source, dto.expectedVersion);
        const successor = operation === "reschedule"
          ? this.successorDraft(
              (dto as LessonRescheduleCommandDto).successor,
              source,
            )
          : null;
        if (successor) {
          await this.acquireLocks(client, source, successor);
          const validation = await this.validateSuccessor(
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
        const coverage = await this.reservations.lockSettlementCoverage(
          client,
          lessonId,
          this.selectedSubscriptionIds(dto),
        );
        if (successor && successorId) {
          await this.insertSuccessor(
            client,
            successorId,
            lessonId,
            successor,
            actor.userId,
          );
        }
        await this.updateSource(
          client,
          lessonId,
          dto.expectedVersion,
          nextVersion,
          toState,
          successorId,
        );
        const settled = await this.settlement.settle(client, lessonId, {
          context: operation,
          decision: dto.financialDecision,
          reasonText: dto.reasonText?.trim(),
        });
        await this.reservations.terminalize(client, settled);
        const financial = this.financialProjection(settled);
        const actualFingerprint = this.transitionFingerprint({
          operation,
          source,
          successor,
          dto,
          coverage,
          financial,
        });
        if (signed.transitionFingerprint !== actualFingerprint) {
          throw new UnprocessableEntityException({
            code: "LESSON_TRANSITION_PREVIEW_STALE",
            message: "Lesson transition inputs changed after preview.",
          });
        }
        if (successor && successorId) {
          await this.allocateSuccessor(client, successorId, successor);
        }
        const transition = await this.lifecycle.appendTransition(client, {
          lessonId,
          toState,
          reasonCode: this.reasonCode(dto),
          reasonText: dto.reasonText?.trim(),
          actorUserId: actor.userId,
          successorId: successorId ?? undefined,
          financialDecision: this.normalizedDecision(dto),
          clientFinancialFactId: settled.clientFact.id,
          clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
          teacherFinancialFactId: settled.teacherFact.id,
        });
        return {
          lessonId,
          state: toState,
          successorId,
          transitionId: String(transition.rows[0]!.id),
          clientFinancialFactIds: settled.clientFacts.map((fact) => fact.id),
          teacherFinancialFactId: settled.teacherFact.id,
        };
      },
    });
    await this.reservations.publishLessonSettlementPostCommit(lessonId);
    return {
      source: { id: lessonId, state: toState, version: mutation.version },
      successor: successorId === null
        ? null
        : { id: successorId, state: "scheduled", version: 1 },
      transitionId: mutation.resultRef.transitionId as string,
      clientFinancialFactIds:
        mutation.resultRef.clientFinancialFactIds as string[],
      teacherFinancialFactId:
        mutation.resultRef.teacherFinancialFactId as string,
      financialDecision: dto.financialDecision,
      replayed: mutation.replayed,
    };
  }

  private async previewFinancial(
    client: PoolClient,
    lessonId: string,
    operation: TransitionOperation,
    dto: TransitionPreviewDto,
  ): Promise<LessonSettlementResult> {
    await client.query("savepoint lesson_transition_preview");
    try {
      await client.query(
        "update app.lessons set lifecycle_state = $2 where id = $1",
        [lessonId, this.targetState(operation)],
      );
      const settled = await this.settlement.settle(client, lessonId, {
        context: operation,
        decision: dto.financialDecision,
        reasonText: dto.reasonText?.trim(),
      });
      await this.reservations.terminalize(client, settled);
      return settled;
    } finally {
      await client.query("rollback to savepoint lesson_transition_preview");
      await client.query("release savepoint lesson_transition_preview");
    }
  }

  private successorDraft(
    dto: UpsertLessonDto,
    source: TransitionSource,
  ): TransitionSuccessor {
    if (source.groupId) return this.groupSuccessorDraft(dto, source);
    return { kind: "individual", ...this.validator.update(dto, source) };
  }

  private groupSuccessorDraft(
    dto: UpsertLessonDto,
    source: TransitionSource,
  ): GroupLessonDraft {
    const snapshot = source.groupSnapshot;
    if (!snapshot || snapshot.validationState !== "valid") {
      this.invalidDraft("LESSON_SNAPSHOT_INCOMPLETE", ["snapshot"]);
    }
    const immutableChanges = [
      dto.clientRef || dto.studentId || dto.leadId ? "clientRef" : null,
      dto.groupId !== undefined && dto.groupId !== source.groupId
        ? "groupId"
        : null,
      dto.status !== undefined ? "status" : null,
      dto.isTrial !== undefined && dto.isTrial !== snapshot!.trial
        ? "isTrial"
        : null,
      dto.completionType !== undefined &&
      dto.completionType.trim() !== snapshot!.completionType
        ? "completionType"
        : null,
      dto.clientChargeType !== undefined && dto.clientChargeType !== "none"
        ? "clientChargeType"
        : null,
      dto.clientChargeValue !== undefined && dto.clientChargeValue !== 0
        ? "clientChargeValue"
        : null,
      dto.subscriptionId !== undefined ? "subscriptionId" : null,
      dto.teacherCompensationType !== undefined &&
      dto.teacherCompensationType !== snapshot!.teacherCompensationType
        ? "teacherCompensationType"
        : null,
      dto.teacherCompensationValue !== undefined &&
      dto.teacherCompensationValue !== snapshot!.teacherCompensationValue
        ? "teacherCompensationValue"
        : null,
      dto.teacherRate !== undefined &&
      dto.teacherRate !== snapshot!.teacherCompensationValue
        ? "teacherRate"
        : null,
      dto.force === true ? "force" : null,
    ].filter((field): field is string => field !== null);
    if (immutableChanges.length > 0) {
      this.invalidDraft("IMMUTABLE_LESSON_SNAPSHOT", immutableChanges);
    }
    const teacherId = dto.teacherId ?? source.teacherId;
    const branchId = dto.branchId ?? source.branchId;
    const roomId = dto.roomId ?? source.roomId;
    if (!teacherId || !branchId || !roomId) {
      this.invalidDraft(
        "LESSON_REQUIRED_FIELDS",
        [
          !teacherId ? "teacherId" : null,
          !branchId ? "branchId" : null,
          !roomId ? "roomId" : null,
        ].filter((field): field is string => field !== null),
      );
    }
    const start = new Date(dto.scheduledAt ?? source.scheduledAt);
    const durationMinutes = dto.durationMinutes ?? source.durationMinutes;
    const end = new Date(start.getTime() + durationMinutes * 60_000);
    if (!Number.isFinite(start.getTime()) || start >= end) {
      this.invalidDraft("INVALID_INTERVAL", ["scheduledAt", "durationMinutes"]);
    }
    return {
      kind: "group",
      groupId: source.groupId!,
      teacherId: teacherId!,
      branchId: branchId!,
      roomId: roomId!,
      scheduledAt: start.toISOString(),
      durationMinutes,
      endAt: end.toISOString(),
      isTrial: snapshot!.trial,
      notes: dto.notes === undefined ? source.notes : dto.notes.trim() || null,
      completionType: snapshot!.completionType,
      teacherCompensationType: snapshot!.teacherCompensationType,
      teacherCompensationValue: snapshot!.teacherCompensationValue,
      participants: source.participants,
    };
  }

  private async validateSuccessor(
    client: PoolClient,
    lessonId: string,
    successor: TransitionSuccessor,
  ) {
    const clients = successor.kind === "individual"
      ? [successor.clientRef]
      : successor.participants.map((participant) => ({
          type: "student" as const,
          id: participant.studentId,
        }));
    const validations = await Promise.all(
      clients.map((clientRef) => this.constraints.validate(
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
      )),
    );
    const violations = Array.from(
      new Map(
        validations.flatMap((validation) => validation.violations)
          .map((violation) => [JSON.stringify(violation), violation]),
      ).values(),
    );
    return { valid: violations.length === 0, violations };
  }

  private async insertSuccessor(
    client: PoolClient,
    successorId: string,
    sourceId: string,
    draft: TransitionSuccessor,
    actorUserId: string,
  ) {
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

  private async allocateSuccessor(
    client: PoolClient,
    successorId: string,
    successor: TransitionSuccessor,
  ) {
    const allocations = successor.kind === "individual"
      ? [{
          clientType: successor.clientRef.type,
          clientId: successor.clientRef.id,
          chargeType: successor.clientChargeType,
          subscriptionId: successor.subscriptionId,
          units: successor.clientChargeValue,
        }]
      : successor.participants.map((participant) => ({
          clientType: "student" as const,
          clientId: participant.studentId,
          chargeType: participant.chargeType,
          subscriptionId: participant.subscriptionId,
          units: participant.chargeValue,
        }));
    for (const allocation of allocations) {
      await this.reservations.allocate(client, {
        lessonId: successorId,
        ...allocation,
      });
    }
  }

  private async acquireLocks(
    client: PoolClient,
    source: TransitionSource,
    successor: TransitionSuccessor,
  ) {
    const clientKeys = successor.kind === "individual"
      ? [`client:${successor.clientRef.type}:${successor.clientRef.id}`]
      : successor.participants.map(
          (participant) => `client:student:${participant.studentId}`,
        );
    const keys = [
      `branch:${successor.branchId}`,
      ...clientKeys,
      `room:${source.roomId}`,
      `room:${successor.roomId}`,
      `teacher:${source.teacherId}`,
      `teacher:${successor.teacherId}`,
    ]
      .filter((key) => !key.endsWith(":null"))
      .filter((key, index, values) => values.indexOf(key) === index)
      .sort();
    for (const key of keys) {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [key],
      );
    }
  }

  private async updateSource(
    client: PoolClient,
    lessonId: string,
    expectedVersion: number,
    nextVersion: number,
    toState: Exclude<TransitionState, "scheduled">,
    successorId: string | null,
  ) {
    const updated = await client.query<{ version: number | string }>(
      `
        update app.lessons
        set lifecycle_state = $3, successor_id = $4, updated_at = now()
        where id = $1 and version = $2 and lifecycle_state = 'scheduled'
        returning version
      `,
      [lessonId, expectedVersion, toState, successorId],
    );
    if (!updated.rows[0] || Number(updated.rows[0].version) !== nextVersion) {
      throw new ConflictException({
        code: "STALE_LESSON_VERSION",
        expectedVersion,
      });
    }
  }

  private async loadSource(
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
    const commonSnapshot =
      row.completion_type &&
      row.teacher_compensation_type &&
      row.teacher_compensation_value !== null &&
      row.snapshot_trial !== null &&
      row.validation_state
        ? {
            completionType: row.completion_type,
            teacherCompensationType: row.teacher_compensation_type,
            teacherCompensationValue: Number(row.teacher_compensation_value),
            trial: row.snapshot_trial,
            validationState: row.validation_state,
          }
        : null;
    return {
      id: row.id,
      version: Number(row.version),
      lifecycleState: row.lifecycle_state,
      studentId: row.student_id,
      leadId: row.lead_id,
      groupId: row.snapshot_group_id === row.lesson_group_id
        ? row.snapshot_group_id
        : null,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      scheduledAt: row.scheduled_at,
      durationMinutes: Number(row.duration_minutes),
      isTrial: row.is_trial,
      notes: row.notes,
      snapshot:
        !row.snapshot_group_id &&
        row.snapshot_client_type &&
        row.snapshot_client_id &&
        row.client_charge_type &&
        row.client_charge_value !== null &&
        commonSnapshot
          ? {
              clientType: row.snapshot_client_type,
              clientId: row.snapshot_client_id,
              ...commonSnapshot,
              clientChargeType: row.client_charge_type,
              clientChargeValue: Number(row.client_charge_value),
              subscriptionId: row.subscription_id,
            }
          : null,
      groupSnapshot: row.snapshot_group_id && commonSnapshot
        ? commonSnapshot
        : null,
      participants: (row.participants ?? []).map((participant) => ({
        ...participant,
        chargeValue: Number(participant.chargeValue),
      })),
    };
  }

  private assertSource(source: TransitionSource, expectedVersion: number) {
    if (source.version !== expectedVersion) {
      throw new ConflictException({
        code: "STALE_LESSON_VERSION",
        expectedVersion,
        currentVersion: source.version,
      });
    }
    if (source.lifecycleState !== "scheduled") {
      throw new ConflictException({
        code: "LESSON_ALREADY_TERMINAL",
        state: source.lifecycleState,
      });
    }
    const individualValid =
      source.snapshot?.validationState === "valid" && !source.groupId;
    const groupValid =
      source.groupSnapshot?.validationState === "valid" &&
      Boolean(source.groupId) &&
      source.participants.length > 0;
    if (!individualValid && !groupValid) {
      throw new UnprocessableEntityException({
        code: "LESSON_SNAPSHOT_INCOMPLETE",
        fields: ["snapshot"],
      });
    }
  }

  private transitionFingerprint(input: {
    operation: TransitionOperation;
    source: TransitionSource;
    successor: TransitionSuccessor | null;
    dto: TransitionPreviewDto;
    coverage: LessonSettlementCoverageSnapshot;
    financial: ReturnType<LessonTransitionService["financialProjection"]>;
  }) {
    return fingerprintPayload({
      operation: input.operation,
      source: this.sourceProjection(input.source),
      successor: input.successor
        ? this.draftProjection(input.successor)
        : null,
      reasonCode: this.reasonCode(input.dto),
      reasonText: input.dto.reasonText?.trim() ?? null,
      financialDecision: this.normalizedDecision(input.dto),
      coverage: input.coverage,
      financial: input.financial,
    });
  }

  private financialProjection(settled: LessonSettlementResult) {
    return {
      clientFacts: settled.clientFacts.map(({ id: _id, ...fact }) => fact),
      teacherFact: (({ id: _id, ...fact }) => fact)(settled.teacherFact),
    };
  }

  private normalizedDecision(dto: TransitionPreviewDto) {
    return {
      settlementTypeKey: dto.financialDecision.settlementTypeKey,
      clientDecisions: [...(dto.financialDecision.clientDecisions ?? [])]
        .sort((left, right) => left.clientId.localeCompare(right.clientId))
        .map((decision) => ({
          clientId: decision.clientId,
          settlementTypeKey: decision.settlementTypeKey ?? null,
          subscriptionId: decision.subscriptionId ?? null,
        })),
      teacherCompensationRuleKey:
        dto.financialDecision.teacherCompensationRuleKey,
      teacherCompensationValueMinor:
        dto.financialDecision.teacherCompensationValueMinor ?? null,
    };
  }

  private selectedSubscriptionIds(dto: TransitionPreviewDto) {
    return (dto.financialDecision.clientDecisions ?? [])
      .map((decision) => decision.subscriptionId)
      .filter((id): id is string => Boolean(id));
  }

  private sourceProjection(source: TransitionSource) {
    return { id: source.id, version: source.version, state: "scheduled" };
  }

  private draftProjection(draft: TransitionSuccessor) {
    return {
      subject: draft.kind === "individual"
        ? { type: draft.clientRef.type, id: draft.clientRef.id }
        : { type: "group", id: draft.groupId },
      teacherId: draft.teacherId,
      branchId: draft.branchId,
      roomId: draft.roomId,
      startAt: draft.scheduledAt,
      endAt: draft.endAt,
    };
  }

  private targetState(
    operation: TransitionOperation,
  ): Exclude<TransitionState, "scheduled"> {
    return operation === "reschedule"
      ? "rescheduled"
      : operation === "cancel"
        ? "cancelled"
        : "successfully_completed";
  }

  private reasonCode(dto: TransitionPreviewDto) {
    return dto.reasonCode?.trim() || "manual";
  }

  private assertReason(dto: TransitionPreviewDto, operation: TransitionOperation) {
    const reasonCode = this.reasonCode(dto);
    if (!/^[A-Za-z0-9._:-]{1,120}$/.test(reasonCode)) {
      throw new UnprocessableEntityException({
        code: "LESSON_TRANSITION_REASON_CODE_INVALID",
        fields: ["reasonCode"],
      });
    }
    const reasonText = dto.reasonText?.trim();
    if (
      (operation !== "settle" && !reasonText) ||
      (dto.reasonText !== undefined &&
        (!reasonText || reasonText.length > 500 || reasonText.includes("\0")))
    ) {
      throw new UnprocessableEntityException({
        code: "LESSON_TRANSITION_REASON_REQUIRED",
        fields: ["reasonText"],
      });
    }
  }

  private assertSignedPreview(
    signed: ReturnType<SubscriptionPreviewTokenService["verifyLessonTransition"]>,
    actor: ActorContext,
    lessonId: string,
    dto: TransitionCommandDto,
    operation: TransitionOperation,
  ) {
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

  private hasClientCharge(settled: LessonSettlementResult) {
    return settled.clientFacts.some(
      (fact) => BigInt(fact.amountMinor) > 0n || Number(fact.units) > 0,
    );
  }

  private assertConfirmed(confirm: true) {
    if (confirm !== true) {
      throw new UnprocessableEntityException({
        code: "LESSON_TRANSITION_CONFIRMATION_REQUIRED",
      });
    }
  }

  private assertMetadata(metadata: LessonCommandMetadata) {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new UnprocessableEntityException({ code: "IDEMPOTENCY_KEY_REQUIRED" });
    }
    if (!metadata.requestId || metadata.requestId.length > 160) {
      throw new UnprocessableEntityException({ code: "REQUEST_ID_REQUIRED" });
    }
  }

  private invalidDraft(code: string, fields: string[]): never {
    throw new UnprocessableEntityException({
      code,
      fields: [...new Set(fields)].sort(),
    });
  }

  private stableId(seed: string) {
    const bytes = createHash("sha256").update(seed).digest().subarray(0, 16);
    bytes[6] = (bytes[6]! & 0x0f) | 0x50;
    bytes[8] = (bytes[8]! & 0x3f) | 0x80;
    const hex = bytes.toString("hex");
    return [
      hex.slice(0, 8),
      hex.slice(8, 12),
      hex.slice(12, 16),
      hex.slice(16, 20),
      hex.slice(20),
    ].join("-");
  }
}
