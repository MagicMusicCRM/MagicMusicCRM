import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { AuditEventInput, AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { audienceForLesson } from "./audience";
import { CrmPolicy } from "./crm.policy";
import {
  CreateScheduleSeriesDto,
  UpdateScheduleSeriesDto,
} from "./dto/schedule-series.dto";
import { BulkLessonRateDto } from "./dto/bulk-lesson-rate.dto";
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";
import { LessonRow, formatLessonTimeMoscow, toLessonDto } from "./crm-mappers";
import { assertLessonPatchUsesTransition } from "./schedule/lesson-protected-patch.guard";
import { ScheduleConflictService } from "./schedule/schedule-conflict.service";
import { ScheduleSeriesMaterializerService } from "./schedule/schedule-series-materializer.service";
import {
  acquireScheduleSeriesLock,
  ScheduleQueryExecutor,
} from "./schedule/schedule-locks";

// Pre-update snapshot used by updateLesson to detect a genuine reschedule
// (time / room / teacher delta) and resolve the assigned teacher (KVA-158).
interface RescheduleSnapshotRow {
  student_id: string | null;
  lead_id: string | null;
  teacher_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string | null;
  duration_minutes?: number | string | null;
  group_id?: string | null;
  is_trial: boolean;
  teacher_user_id: string | null;
}

interface ScheduleSeriesRow {
  id: string;
  client_type?: "lead" | "student" | null;
  client_id?: string | null;
  student_id: string | null;
  group_id: string | null;
  teacher_id: string | null;
  room_id: string | null;
  branch_id: string | null;
  weekday: number | string;
  begin_time: string;
  duration_minutes: number | string;
  // PostgreSQL DATE values are selected as text so the API contract is
  // calendar-date-only and cannot shift with the Node process timezone.
  valid_from: string;
  valid_until: string | null;
  notes: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  superseded_by?: string | null;
  teacher_name?: string | null;
  room_name?: string | null;
  branch_name?: string | null;
  timezone_name?: string | null;
  completion_type?: string | null;
  client_charge_type?: string | null;
  client_charge_value?: number | string | null;
  teacher_compensation_type?: string | null;
  teacher_compensation_value?: number | string | null;
  subscription_id?: string | null;
  trial?: boolean | null;
  occurrence_count?: number | string | null;
  version?: number | string;
}

@Injectable()
export class ScheduleService {
  private readonly logger = new Logger(ScheduleService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeBus,
    private readonly conflicts: ScheduleConflictService,
    private readonly materializer: ScheduleSeriesMaterializerService,
  ) {}

  private async notifyTrialBooked(
    lesson: LessonRow,
    affectedUserIds: string[],
  ): Promise<void> {
    if (!affectedUserIds.length) return;
    const whenLocal = formatLessonTimeMoscow(lesson.scheduled_at);
    await Promise.all(
      affectedUserIds.map((userId) =>
        this.notifications
          .notifyUser({
            userId,
            title: "Пробное занятие назначено",
            body: `Пробное занятие назначено на ${whenLocal} (по Москве). Подробности в приложении.`,
            data: {
              entityType: "lesson",
              entityId: lesson.id,
              eventType: "trial_lesson_booked",
            },
            channels: ["in_app", "push"],
          })
          .catch(() => undefined),
      ),
    );
  }

  private applyClientRef(dto: UpsertLessonDto): UpsertLessonDto {
    if (!dto.clientRef) return dto;
    const mapped: UpsertLessonDto = {
      ...dto,
      studentId: undefined,
      groupId: undefined,
      leadId: undefined,
      clientRef: undefined,
    };
    if (dto.clientRef.type === "lead") {
      mapped.leadId = dto.clientRef.id;
      mapped.studentId = undefined;
    } else {
      mapped.studentId = dto.clientRef.id;
      mapped.leadId = undefined;
    }
    return mapped;
  }

  private assertUnambiguousLessonSubject(
    dto: UpsertLessonDto,
    required: boolean,
  ): boolean {
    const selections = [
      dto.studentId != null,
      dto.groupId != null,
      dto.leadId != null,
    ].filter(Boolean).length;
    if (selections > 1) {
      throw new BadRequestException(
        "Для занятия можно выбрать только одного участника: ученика, группу или лида.",
      );
    }
    if (required && selections === 0) {
      throw new BadRequestException(
        "Укажите ученика, группу или лида для урока.",
      );
    }
    return selections === 1;
  }

  private assertLeadLessonIsTrial(
    leadId: string | null | undefined,
    isTrial: boolean | null | undefined,
  ): void {
    if (leadId && isTrial !== true) {
      throw new BadRequestException(
        "Занятие с лидом должно быть отмечено как пробное.",
      );
    }
  }

  async createLesson(actor: ActorContext, rawDto: UpsertLessonDto) {
    this.policy.assertCanWriteCrm(actor);
    const dto = this.applyClientRef(rawDto);
    if (dto.force === true) {
      throw new BadRequestException(
        "Обход конфликтов расписания запрещён для всех ролей.",
      );
    }
    this.assertUnambiguousLessonSubject(dto, true);
    if (!dto.scheduledAt) {
      throw new BadRequestException("Дата урока обязательна.");
    }
    this.assertScheduledAtWithinBookingWindow(dto.scheduledAt);
    if (!dto.studentId && !dto.groupId && !dto.leadId) {
      throw new BadRequestException(
        "Укажите ученика, группу или лид для урока.",
      );
    }
    this.assertLeadLessonIsTrial(dto.leadId, dto.isTrial);
    // Resource locks, conflict check and insert share one transaction.
    const result = await this.database.transaction(async (client) => {
      if (dto.leadId) {
        const conversion = await client.query<{ converted: boolean }>(
          `
            with locked_lead as (
              select pg_advisory_xact_lock(
                hashtextextended($1::uuid::text, 0)
              )
            )
            select exists (
              select 1
              from app.students student
              where student.lead_id = $1
                and student.deleted_at is null
            ) as converted
            from locked_lead
          `,
          [dto.leadId],
        );
        if (conversion.rows[0]?.converted) {
          throw new ConflictException(
            "Лид уже стал учеником; назначьте обычное занятие ученику.",
          );
        }
      }
      await this.conflicts.assertNoScheduleConflicts(
        {
          teacherId: dto.teacherId ?? null,
          roomId: dto.roomId ?? null,
          startsAt: dto.scheduledAt!,
          durationMinutes: dto.durationMinutes ?? 60,
          groupId: dto.groupId ?? null,
        },
        client as unknown as ScheduleQueryExecutor,
      );
      return client.query<LessonRow>(
        `
        insert into app.lessons (
          student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, teacher_rate
        )
        values ($1, $2, $3, $4, $5, $6, $7, coalesce($8, 60), coalesce($9, 'scheduled'), coalesce($10, false), $11, $12::numeric)
        returning id, student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, teacher_rate, null::uuid as student_user_id, null::uuid as teacher_user_id,
          null::text as student_name, null::text as lead_name, null::text as teacher_name, null::text as branch_name,
          null::text as room_name, null::text as group_name, null::numeric as group_price_per_lesson
      `,
        [
          dto.studentId ?? null,
          dto.groupId ?? null,
          dto.leadId ?? null,
          dto.teacherId ?? null,
          dto.branchId ?? null,
          dto.roomId ?? null,
          dto.scheduledAt,
          dto.durationMinutes ?? null,
          dto.status ?? null,
          dto.isTrial ?? null,
          dto.notes?.trim() || null,
          dto.teacherRate ?? null,
        ],
      );
    });
    const lesson = result.rows[0];
    await this.recordAuditSafe({
      actor,
      action: "crm.lesson_created",
      entityType: "lesson",
      entityId: lesson.id,
    });
    let affectedUserIds: string[] = [];
    try {
      affectedUserIds = await audienceForLesson(this.database, lesson);
    } catch (error) {
      // The lesson insert has already committed. Audience resolution is a
      // best-effort side effect; surfacing its failure as 500 would invite a
      // retry that creates a duplicate trial lesson.
      this.logger.warn(
        `Lesson ${lesson.id} created but audience resolution failed: ${String(error)}`,
      );
    }
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "created",
      id: lesson.id,
      branchId: lesson.branch_id ?? null,
      affectedUserIds,
    });
    if (lesson.is_trial) {
      await this.notifyTrialBooked(lesson, affectedUserIds);
    }
    return toLessonDto(lesson);
  }

  async listScheduleSeries(
    actor: ActorContext,
    query: {
      clientType?: "lead" | "student";
      clientId?: string;
      studentId?: string;
      groupId?: string;
      includeExpired?: boolean;
    },
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<ScheduleSeriesRow>(
      `
        select s.id, s.client_type, s.client_id,
          s.student_id, s.group_id, s.teacher_id, s.room_id,
          s.branch_id, s.weekday, s.begin_time, s.duration_minutes,
          s.valid_from::text as valid_from,
          s.valid_until::text as valid_until,
          s.notes, s.created_at, s.updated_at, s.timezone_name,
          s.completion_type, s.client_charge_type, s.client_charge_value,
          s.teacher_compensation_type, s.teacher_compensation_value,
          s.subscription_id, s.trial, s.occurrence_count, s.version,
          concat_ws(' ', tp.first_name, tp.last_name) as teacher_name,
          r.name as room_name, b.name as branch_name
        from app.schedule_series s
        left join app.teachers t on t.id = s.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.rooms r on r.id = s.room_id
        left join app.branches b on b.id = s.branch_id
        where s.deleted_at is null
          and (
            $1::text is null
            or (
              s.client_type = $1
              and s.client_id = $2::uuid
            )
          )
          and ($3::uuid is null or s.student_id = $3)
          and ($4::uuid is null or s.group_id = $4)
          and (
            $5::boolean
            or s.valid_until is null
            or s.valid_until >= (
              now() at time zone coalesce(
                s.timezone_name,
                b.timezone_name,
                'Europe/Moscow'
              )
            )::date
          )
        order by s.weekday, s.begin_time
      `,
      [
        query.clientType ?? null,
        query.clientId ?? null,
        query.studentId ?? null,
        query.groupId ?? null,
        query.includeExpired === true,
      ],
    );
    return { items: result.rows.map((row) => this.toScheduleSeriesDto(row)) };
  }

  async createScheduleSeries(
    actor: ActorContext,
    dto: CreateScheduleSeriesDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertSeriesDateWithinBookingWindow(dto.validFrom);
    const subjectCount =
      Number(dto.studentId != null) + Number(dto.groupId != null);
    if (subjectCount > 1) {
      throw new BadRequestException(
        "Для серии можно выбрать только одного участника: ученика или группу.",
      );
    }
    if (!dto.studentId && !dto.groupId) {
      throw new BadRequestException("Укажите ученика или группу.");
    }
    const { seriesId, created } = await this.database.transaction(
      async (client) => {
        const result = await client.query<{ id: string }>(
          `
        insert into app.schedule_series (
          student_id, group_id, teacher_id, room_id, branch_id,
          weekday, begin_time, duration_minutes, valid_from, valid_until,
          notes, created_by
        )
        values ($1, $2, $3, $4, $5, $6, $7::time, $8, $9::date, $10::date, $11, $12)
        returning id
      `,
          [
            dto.studentId ?? null,
            dto.groupId ?? null,
            dto.teacherId ?? null,
            dto.roomId ?? null,
            dto.branchId ?? null,
            dto.weekday,
            dto.beginTime,
            dto.durationMinutes ?? 60,
            dto.validFrom,
            dto.validUntil ?? null,
            dto.notes?.trim() || null,
            actor.userId,
          ],
        );
        const seriesId = result.rows[0].id;
        const created = await this.materializer.materializeSeries(
          seriesId,
          client as unknown as ScheduleQueryExecutor,
        );
        return { seriesId, created };
      },
    );
    await this.recordAuditSafe({
      actor,
      action: "crm.schedule_series_created",
      entityType: "schedule_series",
      entityId: seriesId,
      metadata: { lessonsCreated: created },
    });
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "created",
      id: seriesId,
    });
    return { id: seriesId, lessonsCreated: created };
  }

  /**
   * «Карандаш»: правка серии применяется «со следующей даты» (effectiveFrom):
   * старая серия закрывается (valid_until = effectiveFrom - 1), создаётся
   * продолжение с новыми параметрами; будущие НЕтронутые занятия старой серии
   * (scheduled, не перенесённые) с series_date >= effectiveFrom снимаются.
   */
  async updateScheduleSeries(
    actor: ActorContext,
    seriesId: string,
    dto: UpdateScheduleSeriesDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const effectiveFrom = (dto.effectiveFrom ?? this.moscowDate(1)).slice(
      0,
      10,
    );
    this.assertSeriesMutationDateNotPast(effectiveFrom);
    this.assertSeriesDateWithinBookingWindow(effectiveFrom);

    // Close-old / detach-future / insert-continuation must be atomic: a crash
    // in between would leave the series closed with no continuation (or future
    // lessons removed for a series that was never rewritten).
    const { newSeriesId, created } = await this.database.transaction(
      async (client) => {
        await acquireScheduleSeriesLock(
          client as unknown as ScheduleQueryExecutor,
          seriesId,
        );
        const existing = await client.query<ScheduleSeriesRow>(
          `select id, student_id, group_id, teacher_id, room_id, branch_id,
           weekday, begin_time, duration_minutes,
           valid_from::text as valid_from,
           valid_until::text as valid_until,
           notes, created_at, updated_at, superseded_by
         from app.schedule_series
         where id = $1 and deleted_at is null
         for update`,
          [seriesId],
        );
        const series = existing.rows[0];
        if (!series)
          throw new NotFoundException("Серия расписания не найдена.");
        if (series.superseded_by) {
          throw new ConflictException(
            "Серия уже изменена; обновите расписание и повторите для её продолжения.",
          );
        }
        const seriesValidFrom = series.valid_from;
        const inheritedValidUntil = series.valid_until;
        const continuationValidUntil = Object.prototype.hasOwnProperty.call(
          dto,
          "validUntil",
        )
          ? (dto.validUntil?.slice(0, 10) ?? null)
          : inheritedValidUntil;
        if (effectiveFrom < seriesValidFrom) {
          throw new BadRequestException(
            "Дата применения правки не может быть раньше начала серии.",
          );
        }
        if (
          continuationValidUntil !== null &&
          continuationValidUntil < effectiveFrom
        ) {
          throw new BadRequestException(
            "Дата окончания серии не может быть раньше даты применения правки.",
          );
        }
        // Закрываем старую серию накануне effectiveFrom (если она уже шла).
        await client.query(
          `
        update app.schedule_series
        set valid_until = case
            when valid_from < $2::date then least(
              coalesce(valid_until, ($2::date - 1)::date),
              ($2::date - 1)::date
            )
            else valid_until
          end,
          deleted_at = case
            when valid_from >= $2::date then coalesce(deleted_at, now())
            else deleted_at
          end,
          updated_at = now()
        where id = $1
      `,
          [seriesId, effectiveFrom],
        );
        // Снимаем будущие нетронутые занятия старой серии.
        // Продолжение с новыми параметрами.
        const inserted = await client.query<{ id: string }>(
          `
        insert into app.schedule_series (
          student_id, group_id, teacher_id, room_id, branch_id,
          weekday, begin_time, duration_minutes, valid_from, valid_until,
          notes, created_by
        )
        values ($1, $2, $3, $4, $5, $6, $7::time, $8, $9::date, $10::date, $11, $12)
        returning id
      `,
          [
            series.student_id,
            series.group_id,
            dto.teacherId ?? series.teacher_id,
            dto.roomId ?? series.room_id,
            series.branch_id,
            dto.weekday ?? series.weekday,
            dto.beginTime ?? String(series.begin_time).slice(0, 5),
            dto.durationMinutes ?? series.duration_minutes,
            effectiveFrom,
            continuationValidUntil,
            dto.notes?.trim() ?? series.notes,
            actor.userId,
          ],
        );
        const newSeriesId = inserted.rows[0].id;
        // Carry every future exception into the continuation before removing
        // untouched old occurrences. Moved, cancelled and soft-deleted dates act
        // as lineage tombstones, so materialization cannot resurrect them under
        // the continuation's new series id.
        await client.query(
          `update app.lessons
         set series_id = $2, updated_at = now()
         where series_id = $1
           and series_date >= $3::date
           and (
             deleted_at is not null
             or status <> 'scheduled'
             or original_scheduled_at is not null
           )`,
          [seriesId, newSeriesId, effectiveFrom],
        );
        await client.query(
          `update app.lessons
         set deleted_at = now(), updated_at = now()
         where series_id = $1 and series_date >= $2::date
           and status = 'scheduled' and original_scheduled_at is null
           and deleted_at is null`,
          [seriesId, effectiveFrom],
        );
        await client.query(
          `update app.schedule_series
         set superseded_by = $2, updated_at = now()
         where id = $1 and superseded_by is null`,
          [seriesId, newSeriesId],
        );
        const created = await this.materializer.materializeSeries(
          newSeriesId,
          client as unknown as ScheduleQueryExecutor,
        );
        return { newSeriesId, created };
      },
    );
    await this.recordAuditSafe({
      actor,
      action: "crm.schedule_series_updated",
      entityType: "schedule_series",
      entityId: seriesId,
      metadata: { continuationId: newSeriesId, effectiveFrom },
    });
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "updated",
      id: newSeriesId,
    });
    return { id: newSeriesId, previousId: seriesId, lessonsCreated: created };
  }

  /** Остановить серию: с from занятия снимаются, серия закрывается. */
  async deleteScheduleSeries(
    actor: ActorContext,
    seriesId: string,
    from?: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const stopFrom = (from ?? this.moscowDate()).slice(0, 10);
    this.assertSeriesMutationDateNotPast(stopFrom);
    this.assertSeriesDateWithinBookingWindow(stopFrom);
    // Closing the series and detaching its future lessons must be atomic.
    await this.database.transaction(async (client) => {
      await acquireScheduleSeriesLock(
        client as unknown as ScheduleQueryExecutor,
        seriesId,
      );
      const current = await client.query<{
        id: string;
        superseded_by: string | null;
      }>(
        `select id, superseded_by
         from app.schedule_series
         where id = $1 and deleted_at is null
         for update`,
        [seriesId],
      );
      if (!current.rows[0]) {
        throw new NotFoundException("Серия расписания не найдена.");
      }
      if (current.rows[0].superseded_by) {
        throw new ConflictException(
          "Серия уже изменена; остановите её актуальное продолжение.",
        );
      }
      const result = await client.query(
        `
        update app.schedule_series
        set valid_until = case
            when valid_from < $2::date then least(
              coalesce(valid_until, ($2::date - 1)::date),
              ($2::date - 1)::date
            )
            else valid_until
          end,
          deleted_at = case
            when $2::date <= (now() at time zone 'Europe/Moscow')::date
              or valid_from >= $2::date
            then coalesce(deleted_at, now())
            else deleted_at
          end,
          updated_at = now()
        where id = $1 and deleted_at is null and superseded_by is null
      `,
        [seriesId, stopFrom],
      );
      if (!result.rowCount) {
        throw new ConflictException("Состояние серии уже изменилось.");
      }
      await client.query(
        `
        update app.lessons
        set deleted_at = now(), updated_at = now()
        where series_id = $1
          and (scheduled_at at time zone 'Europe/Moscow')::date >= $2::date
          and status = 'scheduled'
          and deleted_at is null
      `,
        [seriesId, stopFrom],
      );
    });
    await this.recordAuditSafe({
      actor,
      action: "crm.schedule_series_stopped",
      entityType: "schedule_series",
      entityId: seriesId,
      metadata: { from: stopFrom },
    });
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "deleted",
      id: seriesId,
    });
    return { id: seriesId, stoppedFrom: stopFrom };
  }

  private toScheduleSeriesDto(row: ScheduleSeriesRow) {
    return {
      id: row.id,
      clientRef:
        row.client_type && row.client_id
          ? { type: row.client_type, id: row.client_id }
          : null,
      studentId: row.student_id,
      groupId: row.group_id,
      teacherId: row.teacher_id,
      teacherName: row.teacher_name?.trim() || null,
      roomId: row.room_id,
      roomName: row.room_name ?? null,
      branchId: row.branch_id,
      branchName: row.branch_name ?? null,
      weekday: Number(row.weekday),
      beginTime: String(row.begin_time).slice(0, 5),
      durationMinutes: Number(row.duration_minutes),
      validFrom: row.valid_from,
      validUntil: row.valid_until,
      timezone: row.timezone_name ?? null,
      completionType: row.completion_type ?? null,
      clientChargeType: row.client_charge_type ?? null,
      clientChargeValue:
        row.client_charge_value === null ||
        row.client_charge_value === undefined
          ? null
          : Number(row.client_charge_value),
      teacherCompensationType: row.teacher_compensation_type ?? null,
      teacherCompensationValue:
        row.teacher_compensation_value === null ||
        row.teacher_compensation_value === undefined
          ? null
          : Number(row.teacher_compensation_value),
      subscriptionId: row.subscription_id ?? null,
      trial: row.trial ?? null,
      occurrenceCount:
        row.occurrence_count === null || row.occurrence_count === undefined
          ? null
          : Number(row.occurrence_count),
      version: row.version === undefined ? null : Number(row.version),
      notes: row.notes,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  async updateLesson(
    actor: ActorContext,
    lessonId: string,
    rawDto: UpsertLessonDto,
  ) {
    const dto = this.applyClientRef(rawDto);
    if (dto.status !== undefined) {
      throw new BadRequestException({
        code: "MANUAL_LESSON_LIFECYCLE_FORBIDDEN",
        message: "Lesson lifecycle is server-managed.",
        fields: ["status"],
      });
    }
    if (
      actor.role === "teacher" &&
      Object.keys(dto).some(
        (field) => !["expectedVersion", "notes"].includes(field),
      )
    ) {
      this.policy.assertCanWriteCrm(actor);
    }
    assertLessonPatchUsesTransition(dto);
    const result = await this.database.transaction(async (client) => {
      const before = await client.query<RescheduleSnapshotRow>(
        `
          select l.student_id, l.group_id, l.lead_id, l.teacher_id,
            l.room_id, l.scheduled_at, l.duration_minutes, l.is_trial,
            tp.user_id as teacher_user_id
          from app.lessons l
          left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          where l.id = $1 and l.deleted_at is null
          limit 1
          for update of l
        `,
        [lessonId],
      );
      await this.assertCanUpdateLesson(
        actor,
        lessonId,
        dto,
        before.rows[0] ?? null,
      );
      return client.query<LessonRow>(
        `
          update app.lessons
          set notes = $2, updated_at = now()
          where id = $1 and deleted_at is null
          returning id, student_id, group_id, lead_id, teacher_id, branch_id,
            room_id, scheduled_at, duration_minutes, status, is_trial, notes,
            teacher_rate, null::uuid as student_user_id,
            null::uuid as teacher_user_id, null::text as student_name,
            null::text as lead_name, null::text as teacher_name,
            null::text as branch_name, null::text as room_name,
            null::text as group_name, null::numeric as group_price_per_lesson
        `,
        [lessonId, dto.notes!.trim() || null],
      );
    });
    const lesson = result.rows[0];
    if (!lesson) throw new NotFoundException("Урок не найден.");
    await this.recordAuditSafe({
      actor,
      action: "crm.lesson_updated",
      entityType: "lesson",
      entityId: lesson.id,
    });
    const affectedUserIds = await audienceForLesson(this.database, lesson);
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "updated",
      id: lesson.id,
      branchId: lesson.branch_id ?? null,
      affectedUserIds,
    });
    return toLessonDto(lesson);
  }

  /**
   * Client self-view: upcoming lessons across the caller's own students (direct
   * and via group membership), used by CrmService.getMySummary. Un-gated by
   * CrmPolicy — ownership is established upstream. Owns the lesson SQL that
   * previously lived inline in CrmService.
   */
  async listUpcomingLessonsForStudents(studentIds: string[]) {
    if (!studentIds.length) return [];
    const result = await this.database.query<LessonRow>(
      `
        select l.id, l.student_id, l.group_id, l.lead_id, l.teacher_id, l.branch_id, l.room_id, l.scheduled_at,
          l.duration_minutes, l.status, l.is_trial, l.notes, l.teacher_rate,
          sp.user_id as student_user_id, tp.user_id as teacher_user_id,
          trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
          trim(coalesce(ld.first_name, '') || ' ' || coalesce(ld.last_name, '')) as lead_name,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.name as group_name,
          g.price_per_lesson as group_price_per_lesson
        from app.lessons l
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.leads ld on ld.id = l.lead_id and ld.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = l.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        where l.deleted_at is null
          and l.scheduled_at >= now()
          and (
            l.student_id = any($1::uuid[])
            or exists (
              select 1
              from app.group_students gs
              where gs.group_id = l.group_id
                and gs.student_id = any($1::uuid[])
                and gs.left_at is null
            )
          )
        order by l.scheduled_at asc, l.id asc
        limit 20
      `,
      [studentIds],
    );
    return (result?.rows ?? []).map((row) => toLessonDto(row));
  }

  async deleteLesson(actor: ActorContext, lessonId: string) {
    // Only managers/admins may delete a lesson outright; teachers can update
    // status/notes via updateLesson but not remove a lesson from the schedule.
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<LessonRow>(
      `
        update app.lessons
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id, student_id, group_id, lead_id, teacher_id, branch_id,
          room_id, scheduled_at, duration_minutes, status, is_trial, notes,
          null::uuid as student_user_id, null::uuid as teacher_user_id,
          null::text as student_name, null::text as lead_name,
          null::text as teacher_name,
          null::text as branch_name, null::text as room_name,
          null::text as group_name, null::numeric as group_price_per_lesson
      `,
      [lessonId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    // Drop any pending reminder markers for the removed lesson.
    await this.database.query(
      "delete from app.lesson_reminders where lesson_id = $1",
      [lessonId],
    );
    await this.recordAuditSafe({
      actor,
      action: "crm.lesson_deleted",
      entityType: "lesson",
      entityId: row.id,
    });
    const affectedUserIds = await audienceForLesson(this.database, row);
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "deleted",
      id: row.id,
      branchId: row.branch_id ?? null,
      affectedUserIds,
    });
    return { success: true };
  }

  /**
   * Applies one per-lesson teacher rate to a bounded selection. Operational
   * roles may change only unsettled lessons. Director/system_admin may also
   * correct already-settled compensation: the previous fact remains intact
   * and a superseding payroll fact becomes effective.
   *
   * Unlike updateLesson this SETS rather than coalesces — clearing the override
   * (rate = null, fall back to the group/history rate) is a thing the caller
   * must be able to express, and coalesce cannot express it.
   */
  async setLessonsTeacherRate(actor: ActorContext, dto: BulkLessonRateDto) {
    // Manager+ only, deliberately stricter than updateLesson's per-lesson
    // teacher path: this writes payroll inputs across the schedule.
    this.policy.assertManagerOnly(actor);
    const rate = dto.teacherRate ?? null;
    const reasonText = dto.reasonText.trim();
    if (!reasonText) {
      throw new BadRequestException("Укажите причину изменения ставки.");
    }
    const canCorrectSettled =
      actor.role === "director" || actor.role === "system_admin";
    const result = await this.database.transaction(async (client) => {
      const targets = await client.query<{ id: string; locked: boolean }>(
        `
          select lesson.id,
            exists (
              select 1
              from app.lesson_teacher_compensation_facts_effective fact
              where fact.lesson_id = lesson.id
            ) as locked
          from app.lessons lesson
          where lesson.id = any($1::uuid[]) and lesson.deleted_at is null
          for update
        `,
        [dto.lessonIds],
      );
      if (targets.rows.length !== dto.lessonIds.length) {
        throw new BadRequestException(
          "Часть выбранных занятий не найдена или уже удалена.",
        );
      }
      const locked = targets.rows
        .filter((row) => row.locked)
        .map((row) => row.id);
      if (locked.length && !canCorrectSettled) {
        throw new ConflictException({
          code: "SETTLED_TEACHER_RATE_IMMUTABLE",
          message:
            "Расчёт завершённого занятия зафиксирован. Используйте корректировку расчёта в карточке занятия.",
          lessonIds: locked,
          canonicalAction: "lesson_settlement_correction",
        });
      }
      if (locked.length && rate === null) {
        throw new ConflictException({
          code: "SETTLED_TEACHER_RATE_REQUIRED",
          message:
            "Для исправления зафиксированных расчётов укажите конкретную ставку.",
          lessonIds: locked,
        });
      }
      const updated = await client.query<{ id: string }>(
        `
          update app.lessons
          set teacher_rate = $2::numeric,
            updated_at = now()
          where id = any($1::uuid[]) and deleted_at is null
          returning id
        `,
        [dto.lessonIds, rate],
      );
      if (locked.length) {
        await client.query(
          `insert into app.lesson_teacher_compensation_facts (
             lesson_id, teacher_id, compensation_type, snapshot_rate,
             rate_minor, duration_minutes, amount_minor, currency_code,
             compensation_rule_key, compensation_rule_label,
             compensation_mode, compensation_default_value,
             compensation_actual_value, compensation_override_reason,
             configuration_revision_id, supersedes_fact_id
           )
           select lesson.id, current_fact.teacher_id,
             case when $2::numeric = 0 then 'none' else 'hourly' end,
             $2::numeric, round($2::numeric * 100)::bigint,
             current_fact.duration_minutes,
             case when $2::numeric = 0 then 0 else
               round($2::numeric * 100 * current_fact.duration_minutes / 60)::bigint
             end,
             current_fact.currency_code,
             case when current_fact.configuration_revision_id is null
               then null else 'director.manual_rate_correction' end,
             case when current_fact.configuration_revision_id is null
               then null else 'Ручная коррекция ставки директором' end,
             case when current_fact.configuration_revision_id is null
               then null
               when $2::numeric = 0 then 'none' else 'hourly' end,
             case when current_fact.configuration_revision_id is null
               then null else round($2::numeric * 100)::bigint end,
             case when current_fact.configuration_revision_id is null
               then null else round($2::numeric * 100)::bigint end,
             case when current_fact.configuration_revision_id is null
               then null else $3 end,
             current_fact.configuration_revision_id,
             current_fact.id
           from app.lessons lesson
           join app.lesson_teacher_compensation_facts_effective current_fact
             on current_fact.lesson_id = lesson.id
           where lesson.id = any($1::uuid[])`,
          [locked, rate, reasonText],
        );
      }
      return {
        lessonIds: updated.rows.map((row) => row.id),
        correctedSettled: locked.length,
      };
    });
    await this.recordAuditSafe({
      actor,
      action: "crm.lessons_teacher_rate_bulk_set",
      entityType: "lesson",
      metadata: {
        teacherRate: rate,
        requested: dto.lessonIds.length,
        updated: result.lessonIds.length,
        correctedSettled: result.correctedSettled,
        reason: reasonText,
      },
    });
    // One event for the batch: 500 per-lesson events would just make every
    // connected client refetch 500 times.
    this.realtime.emitCrmChanged({ entity: "lesson", action: "updated" });
    return {
      updated: result.lessonIds.length,
      correctedSettled: result.correctedSettled,
      lessonIds: result.lessonIds,
    };
  }

  private async assertCanUpdateLesson(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
    lockedSnapshot?: RescheduleSnapshotRow | null,
  ) {
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.role !== "teacher") {
      this.policy.assertCanWriteCrm(actor);
      return;
    }

    const attemptsRestrictedEdit =
      dto.studentId !== undefined ||
      dto.groupId !== undefined ||
      dto.leadId !== undefined ||
      dto.teacherId !== undefined ||
      dto.branchId !== undefined ||
      dto.roomId !== undefined ||
      dto.scheduledAt !== undefined ||
      dto.durationMinutes !== undefined ||
      // teacher_rate is what the school PAYS the teacher. Without this a
      // teacher could set the rate on their own lesson — a self-granted raise —
       // even though the read service will not let them READ the applied rate
      // (canReadSchoolFinance is director/system_admin only).
      dto.teacherRate !== undefined ||
      dto.isTrial !== undefined;
    if (attemptsRestrictedEdit) {
      this.policy.assertCanWriteCrm(actor);
      return;
    }

    let row: { teacher_user_id: string | null } | null | undefined =
      lockedSnapshot;
    if (lockedSnapshot === undefined) {
      const result = await this.database.query<{
        teacher_user_id: string | null;
      }>(
        `
          select tp.user_id as teacher_user_id
          from app.lessons l
          left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          where l.id = $1 and l.deleted_at is null
          limit 1
        `,
        [lessonId],
      );
      row = result.rows[0] ?? null;
    }
    if (!row) throw new NotFoundException("Урок не найден.");
    if (row.teacher_user_id === actor.userId) return;
    throw new NotFoundException("Урок не найден.");
  }


  private assertSeriesDateWithinBookingWindow(value: string): void {
    if (
      value.slice(0, 10) >
      this.moscowDate(
        ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS,
      )
    ) {
      throw new BadRequestException(
        `Schedule date cannot be more than ${ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS} days ahead.`,
      );
    }
  }

  private assertSeriesMutationDateNotPast(value: string): void {
    if (value.slice(0, 10) < this.moscowDate()) {
      throw new BadRequestException(
        "Past schedule-series occurrences cannot be changed.",
      );
    }
  }

  private assertScheduledAtWithinBookingWindow(value: string): void {
    const scheduledAt = new Date(value);
    const upperBound =
      Date.now() +
      (ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS + 1) *
        24 *
        60 *
        60 *
        1000;
    if (
      !Number.isFinite(scheduledAt.getTime()) ||
      scheduledAt.getTime() > upperBound
    ) {
      throw new BadRequestException(
        `Lesson cannot be scheduled more than ${ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS} days ahead.`,
      );
    }
  }

  /** Business dates in schedule_series/series_date are Europe/Moscow dates. */
  private moscowDate(offsetDays = 0): string {
    // Moscow has no DST, but Intl keeps this correct if the runtime timezone is
    // UTC or the server is ever moved. Add whole instants before formatting so
    // 00:00-02:59 MSK never falls back to the previous UTC calendar date.
    const date = new Date(Date.now() + offsetDays * 24 * 60 * 60 * 1000);
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "Europe/Moscow",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(date);
    const value = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((part) => part.type === type)?.value;
    return `${value("year")}-${value("month")}-${value("day")}`;
  }

  private async recordAuditSafe(event: AuditEventInput): Promise<void> {
    try {
      await this.audit.record(event);
    } catch (error) {
      // Schedule writes have already committed when this helper is called.
      // Do not return a false 5xx that makes clients retry a persisted lesson.
      this.logger.error(
        `Audit write failed for ${event.action}/${event.entityId ?? "batch"}: ${String(error)}`,
      );
    }
  }
}
