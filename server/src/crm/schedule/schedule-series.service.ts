import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { AuditEventInput, AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { assertActiveClientReferences } from "../clients/client-reference.service";
import { acquireLessonSettlementCoordinationGate } from "../commerce/lesson-settlement-locks";
import { CrmPolicy } from "../crm.policy";
import {
  CreateScheduleSeriesDto,
  UpdateScheduleSeriesDto,
} from "../dto/schedule-series.dto";
import {
  acquireScheduleLockKeys,
  acquireScheduleSeriesLock,
  ScheduleQueryExecutor,
} from "./schedule-locks";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

interface ScheduleSeriesRow {
  id: string;
  plan_id?: string | null;
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
  deleted_at?: Date | string | null;
  client_refs?: ScheduleSeriesClientRef[] | null;
}

interface ScheduleSeriesClientRef {
  type: "lead" | "student";
  id: string;
}

@Injectable()
export class ScheduleSeriesService {
  private readonly logger = new Logger(ScheduleSeriesService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
    private readonly materializer: ScheduleSeriesMaterializerService,
  ) {}

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
    _dto: CreateScheduleSeriesDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    throw this.schedulePlanMutationRequired();
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
        await acquireLessonSettlementCoordinationGate(client);
        const beforeLock = await this.readLegacySeriesMutationSnapshot(
          client,
          seriesId,
        );
        if (!beforeLock) {
          throw new NotFoundException("Серия расписания не найдена.");
        }
        this.assertLegacySeriesMutationAllowed(beforeLock.plan_id);
        const beforeLockClientRefs = this.seriesClientRefs(beforeLock);
        await acquireScheduleLockKeys(client, [
          ...beforeLockClientRefs.map(
            (reference) => `client:${reference.type}:${reference.id}`,
          ),
          beforeLock.branch_id ? `branch:${beforeLock.branch_id}` : null,
          beforeLock.room_id ? `room:${beforeLock.room_id}` : null,
          dto.roomId ? `room:${dto.roomId}` : null,
          beforeLock.teacher_id ? `teacher:${beforeLock.teacher_id}` : null,
          dto.teacherId ? `teacher:${dto.teacherId}` : null,
        ]);
        await acquireScheduleSeriesLock(
          client as unknown as ScheduleQueryExecutor,
          seriesId,
        );
        const series = await this.readLegacySeriesMutationSnapshot(
          client,
          seriesId,
          true,
        );
        if (!series) {
          throw new NotFoundException("Серия расписания не найдена.");
        }
        if (
          this.legacySeriesMutationSnapshotKey(series) !==
          this.legacySeriesMutationSnapshotKey(beforeLock)
        ) {
          throw new ConflictException({
            code: "SCHEDULE_SERIES_VERSION_STALE",
            message: "Серия изменилась; обновите расписание и повторите.",
          });
        }
        const clientRefs = this.seriesClientRefs(series);
        await assertActiveClientReferences(client, clientRefs);
        if (series.deleted_at) {
          throw new NotFoundException("Серия расписания не найдена.");
        }
        this.assertLegacySeriesMutationAllowed(series.plan_id);
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
          client_type, client_id, student_id, group_id,
          teacher_id, room_id, branch_id,
          weekday, begin_time, duration_minutes, valid_from, valid_until,
          notes, timezone_name, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          subscription_id, trial, occurrence_count, created_by
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9::time, $10,
          $11::date, $12::date, $13, $14, $15, $16, $17, $18, $19,
          $20, $21, $22, $23)
        returning id
      `,
          [
            series.client_type ?? null,
            series.client_id ?? null,
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
            series.timezone_name ?? null,
            series.completion_type ?? null,
            series.client_charge_type ?? null,
            series.client_charge_value ?? null,
            series.teacher_compensation_type ?? null,
            series.teacher_compensation_value ?? null,
            series.subscription_id ?? null,
            series.trial ?? null,
            series.occurrence_count ?? null,
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
          `with removed as (
             update app.lessons
                set deleted_at = now(), updated_at = now()
              where series_id = $1 and series_date >= $2::date
                and status = 'scheduled' and original_scheduled_at is null
                and deleted_at is null
              returning id
           )
           update app.lesson_reservations reservation
              set state = 'released', financial_fact_id = null,
                  updated_at = now()
            where reservation.lesson_id in (select id from removed)
              and reservation.state = 'reserved'`,
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

  private async readLegacySeriesMutationSnapshot(
    client: ScheduleQueryExecutor,
    seriesId: string,
    forUpdate = false,
  ): Promise<ScheduleSeriesRow | undefined> {
    const result = await client.query<ScheduleSeriesRow>(
      `select s.id, s.plan_id, s.client_type, s.client_id,
         s.student_id, s.group_id, s.teacher_id, s.room_id, s.branch_id,
         s.weekday, s.begin_time, s.duration_minutes,
         s.valid_from::text as valid_from,
         s.valid_until::text as valid_until,
         s.notes, s.created_at, s.updated_at, s.superseded_by, s.deleted_at,
         s.timezone_name, s.completion_type,
         s.client_charge_type, s.client_charge_value,
         s.teacher_compensation_type, s.teacher_compensation_value,
         s.subscription_id, s.trial, s.occurrence_count, s.version,
         case
           when s.client_type is not null and s.client_id is not null
             then jsonb_build_array(jsonb_build_object(
               'type', s.client_type, 'id', s.client_id
             ))
           when s.student_id is not null
             then jsonb_build_array(jsonb_build_object(
               'type', 'student', 'id', s.student_id
             ))
           when s.group_id is not null then coalesce((
             select jsonb_agg(
               jsonb_build_object('type', 'student', 'id', membership.student_id)
               order by membership.student_id
             )
             from app.group_students membership
             join app.students student
               on student.id = membership.student_id
              and student.deleted_at is null
             where membership.group_id = s.group_id
               and membership.left_at is null
           ), '[]'::jsonb)
           else '[]'::jsonb
         end as client_refs
       from app.schedule_series s
       where s.id = $1
       ${forUpdate ? "for update of s" : ""}`,
      [seriesId],
    );
    return result.rows[0];
  }

  private seriesClientRefs(
    series: ScheduleSeriesRow,
  ): ScheduleSeriesClientRef[] {
    const references = Array.isArray(series.client_refs)
      ? series.client_refs
      : series.client_type && series.client_id
        ? [{ type: series.client_type, id: series.client_id }]
        : series.student_id
          ? [{ type: "student" as const, id: series.student_id }]
          : [];
    return [
      ...new Map(
        references.map((reference) => [
          `${reference.type}:${reference.id}`,
          reference,
        ]),
      ).values(),
    ].sort((left, right) =>
      `${left.type}:${left.id}`.localeCompare(`${right.type}:${right.id}`),
    );
  }

  private legacySeriesMutationSnapshotKey(series: ScheduleSeriesRow): string {
    return JSON.stringify({
      version: String(series.version ?? ""),
      planId: series.plan_id ?? null,
      clientType: series.client_type ?? null,
      clientId: series.client_id ?? null,
      studentId: series.student_id ?? null,
      groupId: series.group_id ?? null,
      teacherId: series.teacher_id ?? null,
      roomId: series.room_id ?? null,
      branchId: series.branch_id ?? null,
      weekday: Number(series.weekday),
      beginTime: String(series.begin_time),
      durationMinutes: Number(series.duration_minutes),
      validFrom: series.valid_from,
      validUntil: series.valid_until ?? null,
      notes: series.notes ?? null,
      timezoneName: series.timezone_name ?? null,
      completionType: series.completion_type ?? null,
      clientChargeType: series.client_charge_type ?? null,
      clientChargeValue: series.client_charge_value ?? null,
      teacherCompensationType: series.teacher_compensation_type ?? null,
      teacherCompensationValue: series.teacher_compensation_value ?? null,
      subscriptionId: series.subscription_id ?? null,
      trial: series.trial ?? null,
      occurrenceCount: series.occurrence_count ?? null,
      supersededBy: series.superseded_by ?? null,
      deletedAt: series.deleted_at == null ? null : String(series.deleted_at),
      clientRefs: this.seriesClientRefs(series),
    });
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
        plan_id: string | null;
        superseded_by: string | null;
      }>(
        `select id, plan_id, superseded_by
         from app.schedule_series
         where id = $1 and deleted_at is null
         for update`,
        [seriesId],
      );
      if (!current.rows[0]) {
        throw new NotFoundException("Серия расписания не найдена.");
      }
      this.assertLegacySeriesMutationAllowed(current.rows[0].plan_id);
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
        `with removed as (
           update app.lessons
              set deleted_at = now(), updated_at = now()
            where series_id = $1
              and (scheduled_at at time zone 'Europe/Moscow')::date >= $2::date
              and status = 'scheduled'
              and deleted_at is null
            returning id
         )
         update app.lesson_reservations reservation
            set state = 'released', financial_fact_id = null,
                updated_at = now()
          where reservation.lesson_id in (select id from removed)
            and reservation.state = 'reserved'`,
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

  private assertSeriesDateWithinBookingWindow(value: string): void {
    if (
      value.slice(0, 10) >
      this.moscowDate(ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS)
    ) {
      throw new BadRequestException(
        `Schedule date cannot be more than ${ScheduleSeriesMaterializerService.MAX_BOOKING_AHEAD_DAYS} days ahead.`,
      );
    }
  }

  private assertLegacySeriesMutationAllowed(planId?: string | null): void {
    if (!planId) return;
    throw this.schedulePlanMutationRequired();
  }

  private schedulePlanMutationRequired(): ConflictException {
    return new ConflictException({
      code: "SCHEDULE_PLAN_MUTATION_REQUIRED",
      message:
        "Эта серия управляется постоянным расписанием. Измените постоянное расписание целиком.",
    });
  }

  private assertSeriesMutationDateNotPast(value: string): void {
    if (value.slice(0, 10) < this.moscowDate()) {
      throw new BadRequestException(
        "Past schedule-series occurrences cannot be changed.",
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
