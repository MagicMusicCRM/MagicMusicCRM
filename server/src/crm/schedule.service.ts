import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { managerAdminRolesSql } from "../common/security/role-sql";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { audienceForLesson } from "./audience";
import { CrmPolicy } from "./crm.policy";
import { LessonQuery } from "./dto/lesson.query";
import { ScheduleMatrixQuery } from "./dto/schedule-matrix.query";
import {
  CreateScheduleSeriesDto,
  UpdateScheduleSeriesDto,
} from "./dto/schedule-series.dto";
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";
import {
  LessonRow,
  formatLessonTimeMoscow,
  toLessonDto,
} from "./crm-mappers";

interface ScheduleLessonRow extends LessonRow {
  conflict_types: string[] | null;
  // Partner lesson ids this lesson overlaps with, per conflict type. Used to
  // deduplicate the aggregated conflicts list to one entry per pair (KVA-166).
  room_overlap_ids?: string[] | null;
  teacher_overlap_ids?: string[] | null;
}

// Pre-update snapshot used by updateLesson to detect a genuine reschedule
// (time / room / teacher delta) and resolve the assigned teacher (KVA-158).
interface RescheduleSnapshotRow {
  teacher_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string | null;
  teacher_user_id: string | null;
}

interface ScheduleSeriesRow {
  id: string;
  student_id: string | null;
  group_id: string | null;
  teacher_id: string | null;
  room_id: string | null;
  branch_id: string | null;
  weekday: number | string;
  begin_time: string;
  duration_minutes: number | string;
  valid_from: Date | string;
  valid_until: Date | string | null;
  notes: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  teacher_name?: string | null;
  room_name?: string | null;
  branch_name?: string | null;
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
  ) {}

  async getScheduleMatrix(actor: ActorContext, query: ScheduleMatrixQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 300, 500);
    const bounds = this.scheduleMatrixBounds(query);
    const groupBy = query.groupBy ?? "room";
    const result = await this.database.query<ScheduleLessonRow>(
      `
        with scoped as (
          select l.id, l.student_id, l.group_id, l.lead_id, l.teacher_id,
            l.branch_id, l.room_id, l.scheduled_at, l.duration_minutes,
            l.status, l.is_trial, l.notes,
            sp.user_id as student_user_id, tp.user_id as teacher_user_id,
            trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
            trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
            b.name as branch_name,
            r.name as room_name,
            r.branch_id as room_branch_id,
            g.name as group_name,
            g.branch_id as group_branch_id,
            g.price_per_lesson as group_price_per_lesson
          from app.lessons l
          left join app.students s on s.id = l.student_id and s.deleted_at is null
          left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
          left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          left join app.branches b on b.id = l.branch_id and b.deleted_at is null
          left join app.rooms r on r.id = l.room_id and r.deleted_at is null
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          where l.deleted_at is null
            and l.scheduled_at >= $1::timestamptz
            and l.scheduled_at < $2::timestamptz
            and ($3::uuid is null or l.branch_id = $3 or g.branch_id = $3 or r.branch_id = $3)
            and ($4::uuid is null or l.room_id = $4)
            and ($5::uuid is null or l.teacher_id = $5)
            and ($6::boolean is null or l.is_trial = $6)
          order by l.scheduled_at asc, l.id asc
          limit $7
        )
        select scoped.id, scoped.student_id, scoped.group_id, scoped.lead_id,
          scoped.teacher_id, scoped.branch_id, scoped.room_id,
          scoped.scheduled_at, scoped.duration_minutes, scoped.status,
          scoped.is_trial, scoped.notes, scoped.student_user_id,
          scoped.teacher_user_id, scoped.student_name, scoped.teacher_name,
          scoped.branch_name, scoped.room_name, scoped.group_name,
          scoped.group_price_per_lesson,
          array_remove(array[
            case when scoped.teacher_id is null then 'missing_teacher' end,
            case when scoped.room_id is not null and scoped.branch_id is not null
              and scoped.room_branch_id is not null and scoped.branch_id <> scoped.room_branch_id
              then 'branch_mismatch' end,
            case when scoped.room_id is not null and exists (
              select 1
              from app.lessons other_room
              where other_room.deleted_at is null
                and other_room.status <> 'cancelled'
                and other_room.id <> scoped.id
                and other_room.room_id = scoped.room_id
                and other_room.scheduled_at >= $1::timestamptz
                and other_room.scheduled_at < $2::timestamptz
                -- Same group sharing a room is not a conflict (see schedule_issues).
                and (scoped.group_id is null or other_room.group_id is null
                     or other_room.group_id <> scoped.group_id)
                and other_room.scheduled_at < scoped.scheduled_at + scoped.duration_minutes * interval '1 minute'
                and other_room.scheduled_at + other_room.duration_minutes * interval '1 minute' > scoped.scheduled_at
            ) then 'room_overlap' end,
            case when scoped.teacher_id is not null and exists (
              select 1
              from app.lessons other_teacher
              where other_teacher.deleted_at is null
                and other_teacher.status <> 'cancelled'
                and other_teacher.id <> scoped.id
                and other_teacher.teacher_id = scoped.teacher_id
                and other_teacher.scheduled_at >= $1::timestamptz
                and other_teacher.scheduled_at < $2::timestamptz
                -- One teacher running one group class spans many participant
                -- rows at the same time — not a teacher double-booking.
                and (scoped.group_id is null or other_teacher.group_id is null
                     or other_teacher.group_id <> scoped.group_id)
                and other_teacher.scheduled_at < scoped.scheduled_at + scoped.duration_minutes * interval '1 minute'
                and other_teacher.scheduled_at + other_teacher.duration_minutes * interval '1 minute' > scoped.scheduled_at
            ) then 'teacher_overlap' end
          ], null) as conflict_types,
          -- The id of every OTHER lesson this lesson collides with, per type.
          -- Used to deduplicate the aggregated conflicts list so each unordered
          -- overlapping PAIR is counted once instead of once per participant
          -- (KVA-166: prevents the "Конфликты: N" badge double-counting).
          (
            select coalesce(array_agg(other_room.id), '{}')
            from app.lessons other_room
            where scoped.room_id is not null
              and other_room.deleted_at is null
              and other_room.status <> 'cancelled'
              and other_room.id <> scoped.id
              and other_room.room_id = scoped.room_id
              and other_room.scheduled_at >= $1::timestamptz
              and other_room.scheduled_at < $2::timestamptz
              and (scoped.group_id is null or other_room.group_id is null
                   or other_room.group_id <> scoped.group_id)
              and other_room.scheduled_at < scoped.scheduled_at + scoped.duration_minutes * interval '1 minute'
              and other_room.scheduled_at + other_room.duration_minutes * interval '1 minute' > scoped.scheduled_at
          ) as room_overlap_ids,
          (
            select coalesce(array_agg(other_teacher.id), '{}')
            from app.lessons other_teacher
            where scoped.teacher_id is not null
              and other_teacher.deleted_at is null
              and other_teacher.status <> 'cancelled'
              and other_teacher.id <> scoped.id
              and other_teacher.teacher_id = scoped.teacher_id
              and other_teacher.scheduled_at >= $1::timestamptz
              and other_teacher.scheduled_at < $2::timestamptz
              and (scoped.group_id is null or other_teacher.group_id is null
                   or other_teacher.group_id <> scoped.group_id)
              and other_teacher.scheduled_at < scoped.scheduled_at + scoped.duration_minutes * interval '1 minute'
              and other_teacher.scheduled_at + other_teacher.duration_minutes * interval '1 minute' > scoped.scheduled_at
          ) as teacher_overlap_ids
        from scoped
        order by scoped.scheduled_at asc, scoped.id asc
      `,
      [
        bounds.from,
        bounds.to,
        query.branchId ?? null,
        query.roomId ?? null,
        query.teacherId ?? null,
        query.isTrial ?? null,
        limit,
      ],
    );
    const items = result.rows.map((row) => ({
      ...toLessonDto(row),
      conflictTypes: row.conflict_types ?? [],
    }));
    const groups = this.groupScheduleItems(items, groupBy);

    // KVA-166: each overlapping PAIR previously produced TWO conflict entries
    // (one keyed to lesson A because B overlaps it, one keyed to lesson B
    // because A overlaps it), so the "Конфликты: N" badge double-counted —
    // ~242 reported for ~199 real room overlaps. The per-lesson `conflictTypes`
    // above stays per-lesson (the red borders/tooltips need every participant
    // flagged); only the aggregated list is deduplicated to one entry per
    // unordered pair. `*_overlap_ids` give the partner lesson ids, so we key
    // each conflict by `type:minId:maxId` and emit it once, using the
    // earlier-scheduled (first-seen) lesson as the representative for the
    // existing scheduledAt/roomId/teacherId fields and per-day filtering.
    const seenPairs = new Set<string>();
    const conflicts: Array<{
      type: string;
      lessonId: string;
      scheduledAt: Date | string;
      roomId: string | null;
      teacherId: string | null;
    }> = [];
    const partnerIdsByType = (
      row: ScheduleLessonRow,
      type: string,
    ): string[] => {
      if (type === "room_overlap") return row.room_overlap_ids ?? [];
      if (type === "teacher_overlap") return row.teacher_overlap_ids ?? [];
      return [];
    };
    result.rows.forEach((row, index) => {
      const item = items[index];
      const conflictTypes = row.conflict_types ?? [];
      for (const type of conflictTypes) {
        const partners = partnerIdsByType(row, type);
        if (partners.length === 0) {
          // No partner ids surfaced (e.g. branch_mismatch / missing_teacher are
          // single-lesson issues): keep the per-lesson entry as before.
          conflicts.push({
            type,
            lessonId: item.id,
            scheduledAt: item.scheduledAt,
            roomId: item.roomId,
            teacherId: item.teacherId,
          });
          continue;
        }
        for (const partnerId of partners) {
          const [a, b] = [item.id, partnerId].sort();
          const key = `${type}:${a}:${b}`;
          if (seenPairs.has(key)) continue;
          seenPairs.add(key);
          conflicts.push({
            type,
            lessonId: item.id,
            scheduledAt: item.scheduledAt,
            roomId: item.roomId,
            teacherId: item.teacherId,
          });
        }
      }
    });

    return {
      from: bounds.from,
      to: bounds.to,
      groupBy,
      groups,
      items,
      conflicts,
    };
  }

  // Lightweight per-day aggregate for the month calendar: returns one row per
  // day with the lesson count and the distinct room ids (for the colored dots),
  // instead of shipping every lesson. Keeps the month view fast even for
  // branches with thousands of lessons per month.
  async getScheduleMonthSummary(
    actor: ActorContext,
    query: ScheduleMatrixQuery,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const bounds = this.scheduleMatrixBounds(query);
    const result = await this.database.query<{
      day: string;
      count: string;
      room_ids: string[] | null;
    }>(
      `
        select
          to_char((l.scheduled_at at time zone 'Europe/Moscow')::date, 'YYYY-MM-DD') as day,
          count(*)::text as count,
          array_remove(array_agg(distinct l.room_id), null) as room_ids
        from app.lessons l
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        where l.deleted_at is null
          and l.scheduled_at >= $1::timestamptz
          and l.scheduled_at <  $2::timestamptz
          and ($3::uuid is null or l.branch_id = $3 or r.branch_id = $3)
        group by 1
        order by 1
      `,
      [bounds.from, bounds.to, query.branchId ?? null],
    );
    return {
      from: bounds.from,
      to: bounds.to,
      items: result.rows.map((row) => ({
        day: row.day,
        count: Number(row.count),
        roomIds: row.room_ids ?? [],
      })),
    };
  }

  async listLessons(actor: ActorContext, query: LessonQuery) {
    // No CrmPolicy assert on purpose: this endpoint serves EVERY role, and the
    // row filter below ($1/$2 predicate) IS the authorization — staff see all,
    // a teacher only their own lessons, a client only their student/lead/group
    // lessons. Any new role must be added to that predicate or it sees nothing.
    const limit = Math.min(query.limit ?? 100, 200);
    // What the teacher is actually paid for this lesson. l.teacher_rate alone
    // is only the per-lesson OVERRIDE — null there means "inherit", so showing
    // it raw would read as "no rate" on most lessons. Precedence must stay in
    // step with computeLessonAccrual (payroll.service.ts): lesson → group →
    // the rate history entry in force on the lesson date → 0.
    //
    // Gated: this endpoint serves clients too (see the note above), and a
    // teacher's pay rate is school-finance data — KVA-239 keeps that to
    // director/system_admin, so everyone else gets null rather than a leak.
    const canSeeRates = this.policy.canReadSchoolFinance(actor);
    const appliedRateSql = canSeeRates
      ? `coalesce(
            l.teacher_rate,
            g.teacher_rate,
            (
              select tr.rate
              from app.teacher_rates tr
              where tr.teacher_id = l.teacher_id
                and tr.effective_from <= l.scheduled_at::date
              order by tr.effective_from desc, tr.created_at desc
              limit 1
            ),
            0
          )`
      : `null::numeric`;
    const result = await this.database.query<LessonRow>(
      `
        select l.id, l.student_id, l.group_id, l.lead_id, l.teacher_id, l.branch_id, l.room_id, l.scheduled_at,
          l.duration_minutes, l.status, l.is_trial, l.notes, l.teacher_rate,
          ${appliedRateSql} as applied_teacher_rate,
          sp.user_id as student_user_id, tp.user_id as teacher_user_id,
          trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.name as group_name,
          g.price_per_lesson as group_price_per_lesson
        from app.lessons l
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = l.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        where l.deleted_at is null
          and (
            $3::uuid is null
            or l.student_id = $3
            or exists (
              select 1
              from app.group_students filter_gs
              where filter_gs.group_id = l.group_id
                and filter_gs.student_id = $3
                and filter_gs.left_at is null
            )
          )
          and ($4::uuid is null or l.teacher_id = $4)
          and ($5::timestamptz is null or l.scheduled_at >= $5)
          and ($6::timestamptz is null or l.scheduled_at <= $6)
          and ($7::boolean is null or l.is_trial = $7)
          and (
            ${managerAdminRolesSql("$1")}
            or ($1::text = 'teacher' and tp.user_id = $2)
            or ($1::text = 'client' and sp.user_id = $2)
            or (
              $1::text = 'client'
              and exists (
                select 1
                from app.user_crm_links lead_link
                where lead_link.user_id = $2
                  and lead_link.entity_type = 'lead'
                  and lead_link.entity_id = l.lead_id
                  and lead_link.deleted_at is null
              )
            )
            or (
              $1::text = 'client'
              and exists (
                select 1
                from app.group_students actor_gs
                join app.students actor_student
                  on actor_student.id = actor_gs.student_id
                 and actor_student.deleted_at is null
                join app.profiles actor_profile
                  on actor_profile.id = actor_student.profile_id
                 and actor_profile.deleted_at is null
                where actor_gs.group_id = l.group_id
                  and actor_gs.left_at is null
                  and actor_profile.user_id = $2
              )
            )
          )
        order by l.scheduled_at asc, l.id asc
        limit $8
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.teacherId ?? null,
        query.from ?? null,
        query.to ?? null,
        query.isTrial ?? null,
        limit,
      ],
    );

    return { items: result.rows.map((row) => toLessonDto(row)) };
  }

  async createLesson(actor: ActorContext, dto: UpsertLessonDto) {
    this.policy.assertCanWriteCrm(actor);
    if (!dto.scheduledAt) {
      throw new BadRequestException("Дата урока обязательна.");
    }
    if (!dto.studentId && !dto.groupId && !dto.leadId) {
      throw new BadRequestException(
        "Укажите ученика, группу или лид для урока.",
      );
    }
    const result = await this.database.query<LessonRow>(
      `
        insert into app.lessons (
          student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, teacher_rate
        )
        values ($1, $2, $3, $4, $5, $6, $7, coalesce($8, 60), coalesce($9, 'scheduled'), coalesce($10, false), $11, $12::numeric)
        returning id, student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, teacher_rate, null::uuid as student_user_id, null::uuid as teacher_user_id,
          null::text as student_name, null::text as teacher_name, null::text as branch_name,
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
    const lesson = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.lesson_created",
      entityType: "lesson",
      entityId: lesson.id,
    });
    const affectedUserIds = await audienceForLesson(this.database, lesson);
    this.realtime.emitCrmChanged({
      entity: "lesson",
      action: "created",
      id: lesson.id,
      branchId: lesson.branch_id ?? null,
      affectedUserIds,
    });
    return toLessonDto(lesson);
  }

  // ── KVA-236: постоянное расписание (серии) ────────────────────────────────

  /** Горизонт материализации занятий серии, дней вперёд. */
  private static readonly SERIES_HORIZON_DAYS = 60;

  /**
   * Догенерировать занятия серии до горизонта. Идемпотентно: дата серии,
   * уже закрытая строкой lessons.series_date (включая перенесённые и
   * отменённые), повторно не создаётся.
   */
  private async materializeSeries(seriesId: string): Promise<number> {
    const result = await this.database.query(
      `
        insert into app.lessons (
          student_id, group_id, teacher_id, branch_id, room_id,
          scheduled_at, duration_minutes, status, is_trial,
          series_id, series_date, created_by
        )
        select s.student_id, s.group_id, s.teacher_id, s.branch_id, s.room_id,
          (d::date + s.begin_time) at time zone 'Europe/Moscow',
          s.duration_minutes, 'scheduled', false,
          s.id, d::date, s.created_by
        from app.schedule_series s
        cross join lateral generate_series(
          greatest(s.valid_from, current_date)::timestamp,
          least(
            coalesce(s.valid_until, current_date + $2::int),
            current_date + $2::int
          )::timestamp,
          interval '1 day'
        ) as d
        where s.id = $1 and s.deleted_at is null
          and extract(isodow from d) = s.weekday
          and not exists (
            select 1 from app.lessons l
            where l.series_id = s.id and l.series_date = d::date
          )
      `,
      [seriesId, ScheduleService.SERIES_HORIZON_DAYS],
    );
    return result.rowCount ?? 0;
  }

  /** Продлить все живые серии (вкл. «до бесконечности») — вызывается воркером. */
  async extendAllSeriesHorizon(): Promise<{
    series: number;
    created: number;
    failed: number;
  }> {
    const rows = await this.database.query<{ id: string }>(
      `
        select id from app.schedule_series
        where deleted_at is null
          and (valid_until is null or valid_until >= current_date)
      `,
    );
    let created = 0;
    let failed = 0;
    for (const row of rows.rows) {
      // Per-series isolation: one poison series must not starve every series
      // after it in the batch until the next worker tick.
      try {
        created += await this.materializeSeries(row.id);
      } catch (error) {
        failed += 1;
        this.logger.error(
          `Failed to materialize schedule series ${row.id}: ${String(error)}`,
        );
      }
    }
    return { series: rows.rows.length, created, failed };
  }

  async listScheduleSeries(
    actor: ActorContext,
    query: { studentId?: string; groupId?: string; includeExpired?: boolean },
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<ScheduleSeriesRow>(
      `
        select s.id, s.student_id, s.group_id, s.teacher_id, s.room_id,
          s.branch_id, s.weekday, s.begin_time, s.duration_minutes,
          s.valid_from, s.valid_until, s.notes, s.created_at, s.updated_at,
          concat_ws(' ', tp.first_name, tp.last_name) as teacher_name,
          r.name as room_name, b.name as branch_name
        from app.schedule_series s
        left join app.teachers t on t.id = s.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.rooms r on r.id = s.room_id
        left join app.branches b on b.id = s.branch_id
        where s.deleted_at is null
          and ($1::uuid is null or s.student_id = $1)
          and ($2::uuid is null or s.group_id = $2)
          and ($3::boolean or s.valid_until is null or s.valid_until >= current_date)
        order by s.weekday, s.begin_time
      `,
      [
        query.studentId ?? null,
        query.groupId ?? null,
        query.includeExpired === true,
      ],
    );
    return { items: result.rows.map((row) => this.toScheduleSeriesDto(row)) };
  }

  async createScheduleSeries(actor: ActorContext, dto: CreateScheduleSeriesDto) {
    this.policy.assertCanWriteCrm(actor);
    if (!dto.studentId && !dto.groupId) {
      throw new BadRequestException("Укажите ученика или группу.");
    }
    const result = await this.database.query<{ id: string }>(
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
    const created = await this.materializeSeries(seriesId);
    await this.audit.record({
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
    const existing = await this.database.query<ScheduleSeriesRow>(
      `select * from app.schedule_series where id = $1 and deleted_at is null`,
      [seriesId],
    );
    const series = existing.rows[0];
    if (!series) throw new NotFoundException("Серия расписания не найдена.");

    const effectiveFrom =
      dto.effectiveFrom ??
      new Date(Date.now() + 24 * 3600 * 1000).toISOString().slice(0, 10);

    // Close-old / detach-future / insert-continuation must be atomic: a crash
    // in between would leave the series closed with no continuation (or future
    // lessons removed for a series that was never rewritten).
    const newSeriesId = await this.database.transaction(async (client) => {
      // Закрываем старую серию накануне effectiveFrom (если она уже шла).
      await client.query(
        `
        update app.schedule_series
        set valid_until = least(
            coalesce(valid_until, ($2::date - 1)::date),
            ($2::date - 1)::date
          ),
          updated_at = now()
        where id = $1
      `,
        [seriesId, effectiveFrom],
      );
      // Снимаем будущие нетронутые занятия старой серии.
      await client.query(
        `
        update app.lessons
        set deleted_at = now(), updated_at = now()
        where series_id = $1 and series_date >= $2::date
          and status = 'scheduled' and original_scheduled_at is null
          and deleted_at is null
      `,
        [seriesId, effectiveFrom],
      );
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
          dto.validUntil ?? series.valid_until,
          dto.notes?.trim() ?? series.notes,
          actor.userId,
        ],
      );
      return inserted.rows[0].id;
    });
    const created = await this.materializeSeries(newSeriesId);
    await this.audit.record({
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
    const stopFrom = from ?? new Date().toISOString().slice(0, 10);
    // Closing the series and detaching its future lessons must be atomic.
    await this.database.transaction(async (client) => {
      const result = await client.query(
        `
        update app.schedule_series
        set valid_until = ($2::date - 1)::date,
          deleted_at = case when valid_from >= $2::date then now() else deleted_at end,
          updated_at = now()
        where id = $1 and deleted_at is null
      `,
        [seriesId, stopFrom],
      );
      if (!result.rowCount) throw new NotFoundException("Серия расписания не найдена.");
      await client.query(
        `
        update app.lessons
        set deleted_at = now(), updated_at = now()
        where series_id = $1 and series_date >= $2::date
          and status = 'scheduled' and original_scheduled_at is null
          and deleted_at is null
      `,
        [seriesId, stopFrom],
      );
    });
    await this.audit.record({
      actor,
      action: "crm.schedule_series_stopped",
      entityType: "schedule_series",
      entityId: seriesId,
      metadata: { from: stopFrom },
    });
    this.realtime.emitCrmChanged({ entity: "lesson", action: "deleted", id: seriesId });
    return { id: seriesId, stoppedFrom: stopFrom };
  }

  private toScheduleSeriesDto(row: ScheduleSeriesRow) {
    return {
      id: row.id,
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
      notes: row.notes,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  async updateLesson(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
  ) {
    await this.assertCanUpdateLesson(actor, lessonId, dto);
    // Snapshot the pre-update state so we can tell a genuine RESCHEDULE
    // (time / room / teacher change) from an ordinary save (e.g. notes or
    // status edit). The UPDATE ... RETURNING below cannot surface the OLD
    // values, so we read them first. Also resolves the currently-assigned
    // teacher's user_id for the reschedule notification (KVA-158).
    const before = await this.database.query<RescheduleSnapshotRow>(
      `
        select l.teacher_id, l.room_id, l.scheduled_at,
          tp.user_id as teacher_user_id
        from app.lessons l
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where l.id = $1 and l.deleted_at is null
        limit 1
      `,
      [lessonId],
    );
    const previous = before.rows[0] ?? null;
    const result = await this.database.query<LessonRow>(
      `
        update app.lessons
        set student_id = coalesce($2, student_id),
          group_id = coalesce($3, group_id),
          lead_id = coalesce($4, lead_id),
          teacher_id = coalesce($5, teacher_id),
          branch_id = coalesce($6, branch_id),
          room_id = coalesce($7, room_id),
          -- KVA-236: первый перенос занятия серии запоминает исходное время
          -- («перенесено с …»); SET читает СТАРОЕ значение scheduled_at.
          original_scheduled_at = case
            when $8::timestamptz is not null
              and $8::timestamptz <> scheduled_at
              and series_id is not null
            then coalesce(original_scheduled_at, scheduled_at)
            else original_scheduled_at
          end,
          scheduled_at = coalesce($8::timestamptz, scheduled_at),
          duration_minutes = coalesce($9, duration_minutes),
          status = coalesce($10, status),
          is_trial = coalesce($11, is_trial),
          notes = coalesce($12, notes),
          teacher_rate = coalesce($13::numeric, teacher_rate),
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, teacher_rate, null::uuid as student_user_id, null::uuid as teacher_user_id,
          null::text as student_name, null::text as teacher_name, null::text as branch_name,
          null::text as room_name, null::text as group_name, null::numeric as group_price_per_lesson
      `,
      [
        lessonId,
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
    const lesson = result.rows[0];
    if (!lesson) throw new NotFoundException("Урок не найден.");
    // If the lesson was rescheduled, clear its reminder markers so the
    // notification scheduler re-issues -24h/-1h reminders for the NEW time
    // instead of staying silent (markers are keyed by lesson + kind only).
    if (dto.scheduledAt) {
      await this.database.query(
        "delete from app.lesson_reminders where lesson_id = $1",
        [lesson.id],
      );
    }
    await this.notifyTeacherOfReschedule(lessonId, previous, lesson);
    await this.audit.record({
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

  // KVA-158: when a lesson is actually rescheduled — its time, room or
  // assigned teacher changes — push an in-app + FCM notification to the
  // ASSIGNED teacher. We deliberately do NOT fire on every save (status,
  // notes, etc.) so teachers are not spammed.
  private async notifyTeacherOfReschedule(
    lessonId: string,
    previous: RescheduleSnapshotRow | null,
    lesson: LessonRow,
  ): Promise<void> {
    if (!previous) return;
    const sameInstant = (a: Date | string | null, b: Date | string | null) => {
      if (a === null || b === null) return a === b;
      return new Date(a).getTime() === new Date(b).getTime();
    };
    const timeChanged = !sameInstant(previous.scheduled_at, lesson.scheduled_at);
    const roomChanged = previous.room_id !== lesson.room_id;
    const teacherChanged = previous.teacher_id !== lesson.teacher_id;
    if (!timeChanged && !roomChanged && !teacherChanged) return;

    // Notify the teacher who now owns the slot. If the teacher was swapped we
    // resolve the NEW teacher's user_id; otherwise reuse the snapshot value.
    const oldTeacherUserId = previous.teacher_user_id;
    let newTeacherUserId = oldTeacherUserId;
    if (teacherChanged) {
      newTeacherUserId = lesson.teacher_id
        ? await this.resolveTeacherUserId(lesson.teacher_id)
        : null;
    }

    const whenLocal = formatLessonTimeMoscow(lesson.scheduled_at);
    const reasons: string[] = [];
    if (timeChanged) reasons.push("время");
    if (roomChanged) reasons.push("аудитория");
    if (teacherChanged) reasons.push("назначение");
    const body =
      `Изменено: ${reasons.join(", ")}. ` +
      `Новое время — ${whenLocal} (по Москве).`;

    try {
      if (newTeacherUserId) {
        await this.notifications.notifyUser({
          userId: newTeacherUserId,
          title: "Перенос занятия",
          body,
          data: { type: "lesson_rescheduled", lessonId },
          channels: ["push", "in_app"],
        });
      }
      // On a teacher swap, also notify the REMOVED teacher so they know they
      // are no longer assigned. Guard against null and against old==new (e.g.
      // same person re-assigned: time-only reschedule leaves teacher unchanged).
      if (
        teacherChanged &&
        oldTeacherUserId &&
        oldTeacherUserId !== newTeacherUserId
      ) {
        const oldWhenLocal = formatLessonTimeMoscow(
          previous.scheduled_at,
        );
        await this.notifications.notifyUser({
          userId: oldTeacherUserId,
          title: "Занятие переназначено",
          body: `Вы откреплены от занятия ${oldWhenLocal} (по Москве) (передано другому преподавателю).`,
          data: { type: "lesson_reassigned", lessonId },
          channels: ["push", "in_app"],
        });
      }
    } catch {
      // A notification failure must never block the reschedule itself.
    }
  }

  private async resolveTeacherUserId(
    teacherId: string,
  ): Promise<string | null> {
    const result = await this.database.query<{ user_id: string | null }>(
      `
        select tp.user_id
        from app.teachers t
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where t.id = $1 and t.deleted_at is null
        limit 1
      `,
      [teacherId],
    );
    return result.rows[0]?.user_id ?? null;
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
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.name as group_name,
          g.price_per_lesson as group_price_per_lesson
        from app.lessons l
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
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
          null::text as student_name, null::text as teacher_name,
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
    await this.audit.record({
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

  private async assertCanUpdateLesson(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
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
      dto.isTrial !== undefined;
    if (attemptsRestrictedEdit) {
      this.policy.assertCanWriteCrm(actor);
      return;
    }

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
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Урок не найден.");
    if (row.teacher_user_id === actor.userId) return;
    throw new NotFoundException("Урок не найден.");
  }

  private scheduleMatrixBounds(query: ScheduleMatrixQuery) {
    const from = query.from
      ? new Date(query.from)
      : this.utcDayStart(new Date());
    const to = query.to
      ? new Date(query.to)
      : new Date(from.getTime() + 7 * 24 * 60 * 60 * 1000);
    return {
      from: from.toISOString(),
      to: to.toISOString(),
    };
  }

  private utcDayStart(date: Date) {
    return new Date(
      Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
    );
  }

  private groupScheduleItems(
    items: Array<Record<string, unknown>>,
    groupBy: "room" | "teacher" | "day",
  ) {
    const groups = new Map<
      string,
      { key: string; label: string; items: Array<Record<string, unknown>> }
    >();
    for (const item of items) {
      const scheduledAt = item.scheduledAt?.toString() ?? "";
      const key =
        groupBy === "teacher"
          ? item.teacherId?.toString() || "no-teacher"
          : groupBy === "day"
            ? scheduledAt.slice(0, 10) || "no-date"
            : item.roomId?.toString() || "no-room";
      const label =
        groupBy === "teacher"
          ? item.teacherName?.toString() || "Без преподавателя"
          : groupBy === "day"
            ? key
            : item.roomName?.toString() || "Без аудитории";
      const group = groups.get(key) ?? { key, label, items: [] };
      group.items.push(item);
      groups.set(key, group);
    }
    return Array.from(groups.values());
  }

}
