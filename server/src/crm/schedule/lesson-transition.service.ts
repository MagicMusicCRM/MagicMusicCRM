import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import {
  LessonCancelCommandDto,
  LessonCancelPreviewDto,
  LessonRescheduleCommandDto,
  LessonReschedulePreviewDto,
} from "../dto/lesson-transition.dto";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import type { LessonCommandMetadata } from "./lesson-command.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import {
  CompleteLessonDraft,
  ExistingLessonDraft,
  LessonRequiredFieldValidator,
} from "./lesson-required-field.validator";
import { LessonTransitionFinancialService } from "./lesson-transition-financial.service";

interface TransitionLessonRow {
  id: string;
  version: number | string;
  lifecycle_state: "scheduled" | "successfully_completed" | "cancelled" | "rescheduled";
  student_id: string | null;
  lead_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string;
  duration_minutes: number | string;
  is_trial: boolean;
  notes: string | null;
  snapshot_client_type: "lead" | "student" | null;
  snapshot_client_id: string | null;
  completion_type: string | null;
  client_charge_type: "subscription" | "personal_account" | "none" | null;
  client_charge_value: number | string | null;
  teacher_compensation_type: "fixed" | "hourly" | "none" | null;
  teacher_compensation_value: number | string | null;
  subscription_id: string | null;
  snapshot_trial: boolean | null;
  validation_state: "valid" | "legacy_incomplete" | null;
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
    private readonly financial: LessonTransitionFinancialService,
  ) {}

  async previewReschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonReschedulePreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertReason(dto.reasonCode);
    const source = await this.loadSource(lessonId);
    this.assertSource(source, dto.expectedVersion);
    const successor = this.successorDraft(dto, source);
    const validation = await this.constraints.validate({
      clientRef: successor.clientRef,
      teacherId: successor.teacherId,
      branchId: successor.branchId,
      roomId: successor.roomId,
      startAt: successor.scheduledAt,
      endAt: successor.endAt,
      excludeLessonId: lessonId,
    });
    return {
      operation: "reschedule",
      source: this.sourceProjection(source),
      successor: this.draftProjection(successor),
      financialDecision: dto.financialDecision,
      violations: validation.violations,
      canConfirm: validation.valid,
      confirmRequired: true,
    };
  }

  async previewCancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelPreviewDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertReason(dto.reasonCode);
    const source = await this.loadSource(lessonId);
    this.assertSource(source, dto.expectedVersion);
    return {
      operation: "cancel",
      source: this.sourceProjection(source),
      financialDecision: dto.financialDecision,
      violations: [],
      canConfirm: true,
      confirmRequired: true,
    };
  }

  reschedule(
    actor: ActorContext,
    lessonId: string,
    dto: LessonRescheduleCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    this.assertConfirmed(dto.confirm);
    return this.execute(actor, lessonId, dto, metadata, "rescheduled");
  }

  cancel(
    actor: ActorContext,
    lessonId: string,
    dto: LessonCancelCommandDto,
    metadata: LessonCommandMetadata,
  ) {
    this.assertConfirmed(dto.confirm);
    return this.execute(actor, lessonId, dto, metadata, "cancelled");
  }

  private async execute(
    actor: ActorContext,
    lessonId: string,
    dto: LessonRescheduleCommandDto | LessonCancelCommandDto,
    metadata: LessonCommandMetadata,
    toState: "rescheduled" | "cancelled",
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.assertReason(dto.reasonCode);
    const successorId =
      toState === "rescheduled"
        ? this.stableId(
            `schedule.lesson.reschedule\0${lessonId}\0${actor.userId}\0${metadata.idempotencyKey}`,
          )
        : null;
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      operation: `schedule.lesson.${toState}`,
      idempotencyKey: metadata.idempotencyKey,
      payload: { lessonId, dto },
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action:
          toState === "rescheduled"
            ? "crm.lesson_rescheduled"
            : "crm.lesson_cancelled",
        entityType: "lesson",
        entityId: lessonId,
        reason: dto.reasonCode,
        beforeRef: { lessonId, version: dto.expectedVersion, state: "scheduled" },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { entityId: lessonId, state: toState },
      },
      mutate: async (client, nextVersion) => {
        const source = await this.loadSource(lessonId, client, true);
        this.assertSource(source, dto.expectedVersion);
        let successor: CompleteLessonDraft | null = null;
        if (toState === "rescheduled") {
          successor = this.successorDraft(
            dto as LessonRescheduleCommandDto,
            source,
          );
          await this.acquireLocks(client, source, successor);
          const validation = await this.constraints.validate(
            {
              clientRef: successor.clientRef,
              teacherId: successor.teacherId,
              branchId: successor.branchId,
              roomId: successor.roomId,
              startAt: successor.scheduledAt,
              endAt: successor.endAt,
              excludeLessonId: lessonId,
            },
            client,
          );
          if (!validation.valid) {
            throw new UnprocessableEntityException({
              code: "LESSON_CONSTRAINT_VIOLATIONS",
              message: "Successor lesson violates schedule constraints.",
              violations: validation.violations,
            });
          }
          await this.insertSuccessor(
            client,
            successorId!,
            lessonId,
            successor,
            actor.userId,
          );
        }
        const transition = await this.lifecycle.appendTransition(client, {
          lessonId,
          toState,
          reasonCode: dto.reasonCode,
          reasonText: dto.reasonText?.trim() || undefined,
          actorUserId: actor.userId,
          successorId: successorId ?? undefined,
          financialDecision: {
            chargeClient: dto.financialDecision.chargeClient,
            compensateTeacher: dto.financialDecision.compensateTeacher,
          },
        });
        await this.financial.apply(client, {
          lessonId,
          decision: dto.financialDecision,
        });
        const updated = await client.query<{ version: number | string }>(
          `
            update app.lessons
            set lifecycle_state = $3,
                successor_id = $4,
                updated_at = now()
            where id = $1
              and version = $2
              and lifecycle_state = 'scheduled'
            returning version
          `,
          [lessonId, dto.expectedVersion, toState, successorId],
        );
        if (!updated.rows[0] || Number(updated.rows[0].version) !== nextVersion) {
          throw new ConflictException({
            code: "STALE_LESSON_VERSION",
            expectedVersion: dto.expectedVersion,
          });
        }
        return {
          lessonId,
          state: toState,
          successorId,
          transitionId: String(transition.rows[0]!.id),
        };
      },
    });
    return {
      source: { id: lessonId, state: toState, version: mutation.version },
      successor:
        successorId === null ? null : { id: successorId, state: "scheduled", version: 1 },
      transitionId: mutation.resultRef.transitionId as string,
      financialDecision: dto.financialDecision,
      replayed: mutation.replayed,
    };
  }

  private successorDraft(
    dto: LessonReschedulePreviewDto,
    source: ExistingLessonDraft,
  ) {
    if (dto.successor.status && dto.successor.status !== "scheduled") {
      throw new UnprocessableEntityException({
        code: "INVALID_LESSON_INITIAL_STATE",
        message: "A successor lesson must start in scheduled state.",
        fields: ["successor.status"],
      });
    }
    return this.validator.update(dto.successor, source);
  }

  private async insertSuccessor(
    client: PoolClient,
    successorId: string,
    sourceId: string,
    draft: CompleteLessonDraft,
    actorUserId: string,
  ) {
    await client.query(
      `
        insert into app.lessons (
          id, student_id, lead_id, teacher_id, branch_id, room_id,
          scheduled_at, duration_minutes, status, is_trial, notes,
          teacher_rate, predecessor_id, created_by
        )
        values (
          $1,
          case when $2 = 'student' then $3::uuid else null end,
          case when $2 = 'lead' then $3::uuid else null end,
          $4, $5, $6, $7, $8, 'scheduled', $9, $10, $11, $12, $13
        )
      `,
      [
        successorId,
        draft.clientRef.type,
        draft.clientRef.id,
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

  private async acquireLocks(
    client: PoolClient,
    source: ExistingLessonDraft,
    successor: CompleteLessonDraft,
  ) {
    const keys = [
      `branch:${successor.branchId}`,
      `client:${successor.clientRef.type}:${successor.clientRef.id}`,
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

  private async loadSource(
    lessonId: string,
    client?: PoolClient,
    lock = false,
  ): Promise<ExistingLessonDraft & { lifecycleState: TransitionLessonRow["lifecycle_state"] }> {
    const query = client
      ? client.query.bind(client)
      : this.database.query.bind(this.database);
    const result = await query<TransitionLessonRow>(
      `
        select lesson.id, lesson.version, lesson.lifecycle_state,
          lesson.student_id, lesson.lead_id, lesson.teacher_id,
          lesson.branch_id, lesson.room_id, lesson.scheduled_at,
          lesson.duration_minutes, lesson.is_trial, lesson.notes,
          snapshot.client_type as snapshot_client_type,
          snapshot.client_id as snapshot_client_id,
          snapshot.completion_type, snapshot.client_charge_type,
          snapshot.client_charge_value, snapshot.teacher_compensation_type,
          snapshot.teacher_compensation_value, snapshot.subscription_id,
          snapshot.trial as snapshot_trial, snapshot.validation_state
        from app.lessons lesson
        left join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
        where lesson.id = $1 and lesson.deleted_at is null
        ${lock ? "for update of lesson" : ""}
      `,
      [lessonId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    return {
      id: row.id,
      version: Number(row.version),
      lifecycleState: row.lifecycle_state,
      studentId: row.student_id,
      leadId: row.lead_id,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      scheduledAt: row.scheduled_at,
      durationMinutes: Number(row.duration_minutes),
      isTrial: row.is_trial,
      notes: row.notes,
      snapshot:
        row.snapshot_client_type &&
        row.snapshot_client_id &&
        row.completion_type &&
        row.client_charge_type &&
        row.client_charge_value !== null &&
        row.teacher_compensation_type &&
        row.teacher_compensation_value !== null &&
        row.snapshot_trial !== null &&
        row.validation_state
          ? {
              clientType: row.snapshot_client_type,
              clientId: row.snapshot_client_id,
              completionType: row.completion_type,
              clientChargeType: row.client_charge_type,
              clientChargeValue: Number(row.client_charge_value),
              teacherCompensationType: row.teacher_compensation_type,
              teacherCompensationValue: Number(row.teacher_compensation_value),
              subscriptionId: row.subscription_id,
              trial: row.snapshot_trial,
              validationState: row.validation_state,
            }
          : null,
    };
  }

  private assertSource(
    source: ExistingLessonDraft & { lifecycleState?: TransitionLessonRow["lifecycle_state"] },
    expectedVersion: number,
  ) {
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
    if (!source.snapshot || source.snapshot.validationState !== "valid") {
      throw new UnprocessableEntityException({
        code: "LESSON_SNAPSHOT_INCOMPLETE",
        fields: ["snapshot"],
      });
    }
  }

  private sourceProjection(source: ExistingLessonDraft) {
    return { id: source.id, version: source.version, state: "scheduled" };
  }

  private draftProjection(draft: CompleteLessonDraft) {
    return {
      clientRef: draft.clientRef,
      teacherId: draft.teacherId,
      branchId: draft.branchId,
      roomId: draft.roomId,
      startAt: draft.scheduledAt,
      endAt: draft.endAt,
    };
  }

  private assertConfirmed(confirm: true) {
    if (confirm !== true) {
      throw new UnprocessableEntityException({
        code: "LESSON_TRANSITION_CONFIRMATION_REQUIRED",
      });
    }
  }

  private assertReason(reasonCode: string) {
    if (!/^[A-Za-z0-9._:-]{1,120}$/.test(reasonCode)) {
      throw new UnprocessableEntityException({
        code: "LESSON_TRANSITION_REASON_REQUIRED",
        fields: ["reasonCode"],
      });
    }
  }

  private assertMetadata(metadata: LessonCommandMetadata) {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new UnprocessableEntityException({
        code: "IDEMPOTENCY_KEY_REQUIRED",
      });
    }
    if (!metadata.requestId || metadata.requestId.length > 160) {
      throw new UnprocessableEntityException({ code: "REQUEST_ID_REQUIRED" });
    }
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
