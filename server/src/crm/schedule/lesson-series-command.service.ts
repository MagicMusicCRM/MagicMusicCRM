import {
  Injectable,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { ClientReferenceService } from "../clients/client-reference.service";
import { CrmPolicy } from "../crm.policy";
import { ClientRefDto } from "../dto/client-ref.dto";
import { CreateScheduleSeriesDto } from "../dto/schedule-series.dto";
import { SchedulePlanRowDto } from "../dto/schedule-plan.dto";
import { UpsertLessonDto } from "../dto/upsert-lesson.dto";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import type { LessonCommandMetadata } from "./lesson-command.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import {
  CompleteLessonDraft,
  LessonRequiredFieldValidator,
} from "./lesson-required-field.validator";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";

interface SeriesOccurrenceRow {
  local_date: string;
  starts_at: Date | string;
  ends_at: Date | string;
  timezone_name: string;
}

interface SeriesOccurrence {
  index: number;
  localDate: string;
  startAt: string;
  endAt: string;
  timezone: string;
}

@Injectable()
export class LessonSeriesCommandService {
  private static readonly MAX_RANGE_DAYS = 365;
  private static readonly MATERIALIZATION_HORIZON_DAYS = 60;

  constructor(
    private readonly platform: PlatformIntegrityService,
    private readonly policy: CrmPolicy,
    private readonly clients: ClientReferenceService,
    private readonly validator: LessonRequiredFieldValidator,
    private readonly constraints: ScheduleConstraintEngine,
    private readonly lifecycle: LessonLifecycleRepository,
    private readonly reservations: SubscriptionReservationService,
  ) {}

  async create(
    actor: ActorContext,
    dto: CreateScheduleSeriesDto,
    metadata: LessonCommandMetadata,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertMetadata(metadata);
    this.assertFiniteRecurrence(dto);
    const clientRef = this.clientRef(dto);
    const resolved = await this.clients.resolve(actor, clientRef);
    if (resolved.tombstone) {
      throw new UnprocessableEntityException({
        code: "ARCHIVED_CLIENT_REFERENCE",
        message: "Archived client cannot be scheduled.",
        fields: ["clientRef"],
      });
    }

    const seriesId = this.stableId(
      `schedule.lesson-series.create\0${actor.userId}\0${metadata.idempotencyKey}`,
    );
    const mutation = await this.platform.executeVersionedMutation({
      actorKey: `user:${actor.userId}`,
      actorUserId: actor.userId,
      operation: "schedule.lesson-series.create",
      idempotencyKey: metadata.idempotencyKey,
      payload: dto,
      aggregateType: "schedule:lesson-series",
      aggregateId: seriesId,
      expectedVersion: 0,
      requestId: metadata.requestId,
      audit: {
        action: "crm.schedule_series_created",
        entityType: "schedule_series",
        entityId: seriesId,
        afterRef: { seriesId },
      },
      outbox: {
        type: "schedule.lesson-series.changed",
        payload: { entityId: seriesId, state: "created" },
      },
      mutate: async (client, nextVersion) => {
        const templateOccurrence = await this.templateOccurrence(client, dto);
        const templateDraft = this.validator.create(
          this.lessonDraft(dto, clientRef, templateOccurrence.startAt),
        );
        const occurrences = await this.expand(client, dto);
        const drafts = occurrences.map((occurrence) =>
          this.validator.create(
            this.lessonDraft(dto, clientRef, occurrence.startAt),
          ),
        );
        await this.acquireLocks(client, seriesId, templateDraft);
        await this.assertLeadNotConverted(client, clientRef);
        await this.validateEveryOccurrence(client, drafts, occurrences);

        await this.insertSeries(
          client,
          seriesId,
          actor.userId,
          dto,
          templateDraft,
          occurrences,
          templateOccurrence.timezone,
          nextVersion,
        );
        const lessonIds: string[] = [];
        for (const occurrence of occurrences) {
          const lessonId = this.stableId(
            `schedule.lesson-series.occurrence\0${seriesId}\0${occurrence.localDate}`,
          );
          lessonIds.push(lessonId);
          await this.insertOccurrence(
            client,
            lessonId,
            seriesId,
            occurrence,
            drafts[occurrence.index]!,
            actor.userId,
          );
        }
        return { seriesId, lessonIds, lessonsCreated: lessonIds.length };
      },
    });

    return {
      id: seriesId,
      lessonIds: mutation.resultRef.lessonIds as string[],
      lessonsCreated: mutation.resultRef.lessonsCreated as number,
      version: mutation.version,
      replayed: mutation.replayed,
    };
  }

  async validatePlanRow(
    client: PoolClient,
    row: SchedulePlanRowDto,
    validFrom: string,
    validUntil: string | null,
    studentIds: string[],
  ): Promise<void> {
    const dto = Object.assign(new CreateScheduleSeriesDto(), {
      teacherId: row.teacherId,
      roomId: row.roomId,
      branchId: row.branchId,
      weekday: row.weekday,
      beginTime: row.beginTime,
      durationMinutes: row.durationMinutes ?? 60,
      validFrom,
      validUntil,
    });
    const occurrences = await this.expand(client, dto, true);
    const validationOccurrences = occurrences.length > 0
      ? occurrences
      : [await this.firstPlanOccurrence(client, dto)];
    for (const occurrence of validationOccurrences) {
      for (const studentId of studentIds) {
        const result = await this.constraints.validate(
          {
            clientRef: { type: "student", id: studentId },
            teacherId: row.teacherId,
            branchId: row.branchId,
            roomId: row.roomId,
            startAt: occurrence.startAt,
            endAt: occurrence.endAt,
          },
          client,
        );
        if (!result.valid) {
          throw new UnprocessableEntityException({
            code: "SCHEDULE_PLAN_CONSTRAINT_VIOLATIONS",
            message: "Schedule plan row violates schedule constraints.",
            occurrence,
            studentId,
            violations: result.violations,
          });
        }
      }
    }
  }

  private async firstPlanOccurrence(
    client: PoolClient,
    dto: CreateScheduleSeriesDto,
  ): Promise<SeriesOccurrence> {
    const result = await client.query<SeriesOccurrenceRow>(
      `select day::date::text as local_date,
          (day::date + $5::time) at time zone branch.timezone_name as starts_at,
          ((day::date + $5::time) at time zone branch.timezone_name
            + $6::int * interval '1 minute') as ends_at,
          branch.timezone_name
       from app.branches branch
       cross join lateral generate_series(
         $2::date,
         least(coalesce($3::date, $2::date + 6), $2::date + 6),
         interval '1 day'
       ) day
       where branch.id = $1 and branch.deleted_at is null
         and extract(isodow from day) = $4::int
       order by day limit 1`,
      [
        dto.branchId,
        dto.validFrom.slice(0, 10),
        dto.validUntil?.slice(0, 10) ?? null,
        dto.weekday,
        dto.beginTime,
        dto.durationMinutes ?? 60,
      ],
    );
    const row = result.rows[0];
    if (!row) {
      throw new UnprocessableEntityException({
        code: "SCHEDULE_PLAN_ROW_EMPTY",
        fields: ["rows", "activeFrom", "activeUntil"],
      });
    }
    return {
      index: 0,
      localDate: row.local_date,
      startAt: new Date(row.starts_at).toISOString(),
      endAt: new Date(row.ends_at).toISOString(),
      timezone: row.timezone_name,
    };
  }

  private assertFiniteRecurrence(dto: CreateScheduleSeriesDto) {
    const datePattern = /^\d{4}-\d{2}-\d{2}$/;
    if (
      !datePattern.test(dto.validFrom) ||
      !dto.validUntil ||
      !datePattern.test(dto.validUntil.slice(0, 10))
    ) {
      throw new UnprocessableEntityException({
        code: "LESSON_SERIES_FINITE_RANGE_REQUIRED",
        message: "Atomic series creation requires validFrom and validUntil.",
        fields: ["validFrom", "validUntil"],
      });
    }
  }

  private clientRef(dto: CreateScheduleSeriesDto): ClientRefDto {
    const refs = [
      dto.clientRef,
      dto.studentId
        ? ({ type: "student", id: dto.studentId } as const)
        : undefined,
      dto.leadId ? ({ type: "lead", id: dto.leadId } as const) : undefined,
    ].filter((value): value is ClientRefDto => value !== undefined);
    if (refs.length !== 1 || dto.groupId !== undefined) {
      throw new UnprocessableEntityException({
        code: "LESSON_REQUIRED_FIELDS",
        message: "A single Lead or Student clientRef is required.",
        fields: ["clientRef"],
      });
    }
    return refs[0]!;
  }

  private async expand(
    client: PoolClient,
    dto: CreateScheduleSeriesDto,
    allowPlanRange = false,
  ): Promise<SeriesOccurrence[]> {
    const result = await client.query<SeriesOccurrenceRow>(
      `
        select
          day::date::text as local_date,
          (day::date + $5::time) at time zone branch.timezone_name as starts_at,
          (
            (day::date + $5::time) at time zone branch.timezone_name
            + $6::int * interval '1 minute'
          ) as ends_at,
          branch.timezone_name
        from app.branches branch
        cross join lateral generate_series(
          greatest(
            $2::date,
            timezone(branch.timezone_name, now())::date
          ),
          least(
            coalesce(
              $3::date,
              timezone(branch.timezone_name, now())::date + $8::int
            ),
            timezone(branch.timezone_name, now())::date + $8::int
          ),
          interval '1 day'
        ) day
        where branch.id = $1
          and branch.deleted_at is null
          and extract(isodow from day) = $4::int
          and (
            $9::boolean
            or ($3::date - $2::date) between 0 and $7::int
          )
        order by day
      `,
      [
        dto.branchId ?? null,
        dto.validFrom.slice(0, 10),
        dto.validUntil?.slice(0, 10) ?? null,
        dto.weekday,
        dto.beginTime,
        dto.durationMinutes ?? 60,
        LessonSeriesCommandService.MAX_RANGE_DAYS,
        LessonSeriesCommandService.MATERIALIZATION_HORIZON_DAYS,
        allowPlanRange,
      ],
    );
    return result.rows.map((row, index) => ({
      index,
      localDate: row.local_date,
      startAt: new Date(row.starts_at).toISOString(),
      endAt: new Date(row.ends_at).toISOString(),
      timezone: row.timezone_name,
    }));
  }

  private async templateOccurrence(
    client: PoolClient,
    dto: CreateScheduleSeriesDto,
  ): Promise<SeriesOccurrence> {
    const result = await client.query<SeriesOccurrenceRow>(
      `
        select
          $2::date::text as local_date,
          ($2::date + $3::time) at time zone branch.timezone_name as starts_at,
          (($2::date + $3::time) at time zone branch.timezone_name
            + $4::int * interval '1 minute') as ends_at,
          branch.timezone_name
        from app.branches branch
        where branch.id = $1 and branch.deleted_at is null
      `,
      [
        dto.branchId ?? null,
        dto.validFrom.slice(0, 10),
        dto.beginTime,
        dto.durationMinutes ?? 60,
      ],
    );
    const row = result.rows[0];
    if (!row) {
      throw new UnprocessableEntityException({
        code: "LESSON_SERIES_BRANCH_MISSING",
        message: "Lesson series branch is missing or archived.",
        fields: ["branchId"],
      });
    }
    return {
      index: 0,
      localDate: row.local_date,
      startAt: new Date(row.starts_at).toISOString(),
      endAt: new Date(row.ends_at).toISOString(),
      timezone: row.timezone_name,
    };
  }

  private lessonDraft(
    dto: CreateScheduleSeriesDto,
    clientRef: ClientRefDto,
    scheduledAt: string,
  ): UpsertLessonDto {
    return {
      clientRef,
      teacherId: dto.teacherId,
      branchId: dto.branchId,
      roomId: dto.roomId,
      scheduledAt,
      durationMinutes: dto.durationMinutes ?? 60,
      isTrial: dto.isTrial,
      completionType: dto.completionType,
      clientChargeType: dto.clientChargeType,
      clientChargeValue: dto.clientChargeValue,
      teacherCompensationType: dto.teacherCompensationType,
      teacherCompensationValue: dto.teacherCompensationValue,
      subscriptionId: dto.subscriptionId,
      notes: dto.notes,
    };
  }

  private async validateEveryOccurrence(
    client: PoolClient,
    drafts: CompleteLessonDraft[],
    occurrences: SeriesOccurrence[],
  ) {
    for (const occurrence of occurrences) {
      const draft = drafts[occurrence.index]!;
      const result = await this.constraints.validate(
        {
          clientRef: draft.clientRef,
          teacherId: draft.teacherId,
          branchId: draft.branchId,
          roomId: draft.roomId,
          startAt: draft.scheduledAt,
          endAt: draft.endAt,
        },
        client,
      );
      if (!result.valid) {
        throw new UnprocessableEntityException({
          code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
          message: "Lesson series occurrence violates schedule constraints.",
          failedIndex: occurrence.index,
          occurrence,
          violations: result.violations,
        });
      }
    }
  }

  private async acquireLocks(
    client: PoolClient,
    seriesId: string,
    draft: CompleteLessonDraft,
  ) {
    const keys = [
      `branch:${draft.branchId}`,
      `client:${draft.clientRef.type}:${draft.clientRef.id}`,
      `room:${draft.roomId}`,
      `series:${seriesId}`,
      `teacher:${draft.teacherId}`,
    ].sort();
    for (const key of keys) {
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended($1, 0))",
        [key],
      );
    }
  }

  private async assertLeadNotConverted(
    client: PoolClient,
    clientRef: ClientRefDto,
  ) {
    if (clientRef.type !== "lead") return;
    const conversion = await client.query<{ converted: boolean }>(
      `
        select exists (
          select 1
          from app.client_conversion_links
          where lead_id = $1
        ) as converted
      `,
      [clientRef.id],
    );
    if (conversion.rows[0]?.converted) {
      throw new UnprocessableEntityException({
        code: "LEAD_ALREADY_CONVERTED",
        message: "Use the converted Student client reference.",
        fields: ["clientRef"],
      });
    }
  }

  private insertSeries(
    client: PoolClient,
    seriesId: string,
    actorUserId: string,
    dto: CreateScheduleSeriesDto,
    draft: CompleteLessonDraft,
    occurrences: SeriesOccurrence[],
    timezone: string,
    version: number,
  ) {
    return client.query(
      `
        insert into app.schedule_series (
          id, student_id, group_id, teacher_id, room_id, branch_id,
          weekday, begin_time, duration_minutes, valid_from, valid_until,
          notes, created_by, client_type, client_id, timezone_name,
          completion_type, client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          subscription_id, trial, occurrence_count, version
        )
        values (
          $1,
          case when $2 = 'student' then $3::uuid else null end,
          null,
          $4, $5, $6, $7, $8::time, $9, $10::date, $11::date,
          $12, $13, $2, $3, $14, $15, $16, $17, $18, $19, $20,
          $21, $22, $23
        )
      `,
      [
        seriesId,
        draft.clientRef.type,
        draft.clientRef.id,
        draft.teacherId,
        draft.roomId,
        draft.branchId,
        dto.weekday,
        dto.beginTime,
        draft.durationMinutes,
        dto.validFrom.slice(0, 10),
        dto.validUntil!.slice(0, 10),
        draft.notes,
        actorUserId,
        timezone,
        draft.completionType,
        draft.clientChargeType,
        draft.clientChargeValue,
        draft.teacherCompensationType,
        draft.teacherCompensationValue,
        draft.subscriptionId,
        draft.isTrial,
        occurrences.length,
        version,
      ],
    );
  }

  private async insertOccurrence(
    client: PoolClient,
    lessonId: string,
    seriesId: string,
    occurrence: SeriesOccurrence,
    draft: CompleteLessonDraft,
    actorUserId: string,
  ) {
    await client.query(
      `
        insert into app.lessons (
          id, student_id, lead_id, teacher_id, branch_id, room_id,
          scheduled_at, duration_minutes, status, is_trial, notes,
          teacher_rate, series_id, series_date, created_by
        )
        values (
          $1,
          case when $2 = 'student' then $3::uuid else null end,
          case when $2 = 'lead' then $3::uuid else null end,
          $4, $5, $6, $7, $8, 'scheduled', $9, $10, $11, $12, $13::date, $14
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
        seriesId,
        occurrence.localDate,
        actorUserId,
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
