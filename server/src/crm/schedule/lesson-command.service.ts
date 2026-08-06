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
import { LessonRow, toLessonDto } from "../crm-mappers";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { LessonConstraintPreviewDto } from "../dto/lesson-constraint-preview.dto";
import { ClientReferenceService } from "../clients/client-reference.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import {
  CompleteLessonDraft,
  ExistingLessonDraft,
  LessonRequiredFieldValidator,
} from "./lesson-required-field.validator";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";

export interface LessonCommandMetadata {
  idempotencyKey: string;
  requestId: string;
}

interface CurrentLessonRow {
  id: string;
  version: number | string;
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
export class LessonCommandService {
  constructor(
    private readonly database: DatabaseService,
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly clients: ClientReferenceService,
    private readonly validator: LessonRequiredFieldValidator,
    private readonly constraints: ScheduleConstraintEngine,
    private readonly lifecycle: LessonLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  previewConstraints(actor: ActorContext, dto: LessonConstraintPreviewDto) {
    this.policy.assertCanWriteCrm(actor);
    const startAt = new Date(dto.scheduledAt);
    const endAt = new Date(startAt.getTime() + dto.durationMinutes * 60_000);
    return this.constraints.validate({
      clientRef: dto.clientRef,
      teacherId: dto.teacherId,
      branchId: dto.branchId,
      roomId: dto.roomId,
      startAt,
      endAt,
      excludeLessonId: dto.excludeLessonId,
    });
  }

  async create(
    actor: ActorContext,
    dto: UpsertLessonDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    const draft = this.validator.create(dto);
    await this.assertClientActive(actor, draft);
    const lessonId = this.stableCreateId(actor, metadata.idempotencyKey);
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      operation: "schedule.lesson.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: 0,
      requestId: metadata.requestId,
      audit: {
        action: "crm.lesson_created",
        entityType: "lesson",
        entityId: lessonId,
        afterRef: { lessonId },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { lessonId, action: "created" },
      },
      mutate: async (client) => {
        await this.acquireLocks(client, draft);
        await this.assertConstraints(draft, client);
        await this.assertLeadNotConverted(client, draft);
        await client.query(
          `
            insert into app.lessons (
              id, student_id, lead_id, teacher_id, branch_id, room_id,
              scheduled_at, duration_minutes, status, is_trial, notes,
              teacher_rate, created_by
            )
            values (
              $1,
              case when $2 = 'student' then $3::uuid else null end,
              case when $2 = 'lead' then $3::uuid else null end,
              $4, $5, $6, $7, $8, 'scheduled', $9, $10, $11, $12
            )
          `,
          [
            lessonId,
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
            actor.userId,
          ],
        );
        await this.lifecycle.createSnapshot(client, {
          lessonId,
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
        await this.reservations.allocate(client, {
          lessonId,
          clientType: draft.clientRef.type,
          clientId: draft.clientRef.id,
          chargeType: draft.clientChargeType,
          subscriptionId: draft.subscriptionId,
          units: draft.clientChargeValue,
        });
        return { lessonId };
      },
    });
    return this.response(lessonId, mutation.version, mutation.replayed);
  }

  async update(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    if (!dto.expectedVersion) {
      throw new UnprocessableEntityException({
        code: "EXPECTED_VERSION_REQUIRED",
        message: "expectedVersion is required for lesson updates.",
        fields: ["expectedVersion"],
      });
    }
    const before = await this.loadExisting(lessonId);
    const preview = this.validator.update(dto, before);
    await this.assertClientActive(actor, preview);
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      operation: "schedule.lesson.update",
      idempotencyKey: metadata.idempotencyKey,
      payload: { lessonId, dto },
      aggregateType: "schedule:lesson",
      aggregateId: lessonId,
      expectedVersion: dto.expectedVersion,
      requestId: metadata.requestId,
      audit: {
        action: "crm.lesson_updated",
        entityType: "lesson",
        entityId: lessonId,
        beforeRef: { lessonId, version: dto.expectedVersion },
      },
      outbox: {
        type: "schedule.lesson.changed",
        payload: { lessonId, action: "updated" },
      },
      mutate: async (client, nextVersion) => {
        const current = await this.loadExisting(lessonId, client, true);
        if (current.version !== dto.expectedVersion) {
          throw new ConflictException({
            code: "STALE_AGGREGATE_VERSION",
            expectedVersion: dto.expectedVersion,
            currentVersion: current.version,
          });
        }
        const draft = this.validator.update(dto, current);
        await this.acquireLocks(client, draft, current);
        await this.assertConstraints(draft, client, lessonId);
        await this.assertLeadNotConverted(client, draft);
        const updated = await client.query<{
          id: string;
          version: number | string;
        }>(
          `
            update app.lessons
            set teacher_id = $2,
                branch_id = $3,
                room_id = $4,
                original_scheduled_at = case
                  when $5::timestamptz <> scheduled_at and series_id is not null
                  then coalesce(original_scheduled_at, scheduled_at)
                  else original_scheduled_at
                end,
                scheduled_at = $5,
                duration_minutes = $6,
                notes = $7,
                updated_at = now()
            where id = $1
              and deleted_at is null
              and version = $8
            returning id, version
          `,
          [
            lessonId,
            draft.teacherId,
            draft.branchId,
            draft.roomId,
            draft.scheduledAt,
            draft.durationMinutes,
            draft.notes,
            dto.expectedVersion,
          ],
        );
        if (!updated.rows[0]) {
          throw new ConflictException({
            code: "STALE_AGGREGATE_VERSION",
            expectedVersion: dto.expectedVersion,
          });
        }
        if (Number(updated.rows[0].version) !== nextVersion) {
          throw new ConflictException({
            code: "LESSON_VERSION_DIVERGED",
            expectedVersion: nextVersion,
            currentVersion: Number(updated.rows[0].version),
          });
        }
        if (dto.scheduledAt !== undefined) {
          await client.query(
            "delete from app.lesson_reminders where lesson_id = $1",
            [lessonId],
          );
        }
        return { lessonId, version: nextVersion };
      },
    });
    return this.response(lessonId, mutation.version, mutation.replayed);
  }

  private async assertClientActive(
    actor: ActorContext,
    draft: CompleteLessonDraft,
  ) {
    const client = await this.clients.resolve(actor, draft.clientRef);
    if (client.tombstone) {
      throw new UnprocessableEntityException({
        code: "ARCHIVED_CLIENT_REFERENCE",
        message: "Archived client cannot be scheduled.",
        fields: ["clientRef"],
      });
    }
  }

  private async assertConstraints(
    draft: CompleteLessonDraft,
    client: PoolClient,
    excludeLessonId?: string,
  ) {
    const result = await this.constraints.validate(
      {
        clientRef: draft.clientRef,
        teacherId: draft.teacherId,
        branchId: draft.branchId,
        roomId: draft.roomId,
        startAt: draft.scheduledAt,
        endAt: draft.endAt,
        excludeLessonId,
      },
      client,
    );
    if (!result.valid) {
      throw new UnprocessableEntityException({
        code: "LESSON_CONSTRAINT_VIOLATIONS",
        message: "Lesson draft violates schedule constraints.",
        violations: result.violations,
      });
    }
  }

  private async acquireLocks(
    client: PoolClient,
    draft: CompleteLessonDraft,
    previous?: ExistingLessonDraft,
  ) {
    const keys = [
      `branch:${draft.branchId}`,
      `client:${draft.clientRef.type}:${draft.clientRef.id}`,
      `room:${draft.roomId}`,
      `teacher:${draft.teacherId}`,
      previous?.branchId ? `branch:${previous.branchId}` : null,
      previous?.roomId ? `room:${previous.roomId}` : null,
      previous?.teacherId ? `teacher:${previous.teacherId}` : null,
    ]
      .filter((key): key is string => key !== null)
      .filter((key, index, values) => values.indexOf(key) === index)
      .sort();
    for (const key of keys) {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [key],
      );
    }
  }

  private async assertLeadNotConverted(
    client: PoolClient,
    draft: CompleteLessonDraft,
  ) {
    if (draft.clientRef.type !== "lead") return;
    const conversion = await client.query<{ converted: boolean }>(
      `
        select exists (
          select 1
          from app.client_conversion_links link
          where link.lead_id = $1
        ) as converted
      `,
      [draft.clientRef.id],
    );
    if (conversion.rows[0]?.converted) {
      throw new ConflictException({
        code: "LEAD_ALREADY_CONVERTED",
        message: "Use the converted Student client reference.",
      });
    }
  }

  private async loadExisting(
    lessonId: string,
    client?: PoolClient,
    lock = false,
  ): Promise<ExistingLessonDraft> {
    const query = client
      ? client.query.bind(client)
      : this.database.query.bind(this.database);
    const result = await query<CurrentLessonRow>(
      `
        select
          lesson.id,
          lesson.version,
          lesson.student_id,
          lesson.lead_id,
          lesson.teacher_id,
          lesson.branch_id,
          lesson.room_id,
          lesson.scheduled_at,
          lesson.duration_minutes,
          lesson.is_trial,
          lesson.notes,
          snapshot.client_type as snapshot_client_type,
          snapshot.client_id as snapshot_client_id,
          snapshot.completion_type,
          snapshot.client_charge_type,
          snapshot.client_charge_value,
          snapshot.teacher_compensation_type,
          snapshot.teacher_compensation_value,
          snapshot.subscription_id,
          snapshot.trial as snapshot_trial,
          snapshot.validation_state
        from app.lessons lesson
        left join app.lesson_snapshots snapshot
          on snapshot.lesson_id = lesson.id
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

  private async response(lessonId: string, version: number, replayed: boolean) {
    const result = await this.database.query<LessonRow>(
      `
        select
          lesson.id, lesson.student_id, lesson.group_id, lesson.lead_id,
          lesson.teacher_id, lesson.branch_id, lesson.room_id,
          lesson.scheduled_at, lesson.duration_minutes, lesson.status,
          lesson.is_trial, lesson.notes, lesson.teacher_rate,
          null::uuid as student_user_id,
          null::uuid as teacher_user_id,
          null::text as student_name,
          null::text as lead_name,
          null::text as teacher_name,
          null::text as branch_name,
          null::text as room_name,
          null::text as group_name,
          null::numeric as group_price_per_lesson
        from app.lessons lesson
        where lesson.id = $1 and lesson.deleted_at is null
      `,
      [lessonId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    return {
      ...toLessonDto(row),
      clientRef: row.lead_id
        ? { type: "lead" as const, id: row.lead_id }
        : { type: "student" as const, id: row.student_id! },
      version,
      replayed,
    };
  }

  private assertMetadata(metadata: LessonCommandMetadata) {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new UnprocessableEntityException({
        code: "IDEMPOTENCY_KEY_REQUIRED",
        message: "Idempotency-Key must contain 8-160 safe characters.",
      });
    }
    if (!metadata.requestId || metadata.requestId.length > 160) {
      throw new UnprocessableEntityException({
        code: "REQUEST_ID_REQUIRED",
        message: "X-Request-Id is required and must not exceed 160 characters.",
      });
    }
  }

  private stableCreateId(actor: ActorContext, idempotencyKey: string) {
    const bytes = createHash("sha256")
      .update(`schedule.lesson.create\0${actor.userId}\0${idempotencyKey}`)
      .digest()
      .subarray(0, 16);
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
