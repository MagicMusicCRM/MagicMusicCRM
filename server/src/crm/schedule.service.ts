import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import { AuditEventInput, AuditService } from "../audit/audit.service";
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
import { ScheduleConflictsQuery } from "./dto/schedule-conflicts.query";
import { ScheduleMatrixQuery } from "./dto/schedule-matrix.query";
import {
  CreateScheduleSeriesDto,
  UpdateScheduleSeriesDto,
} from "./dto/schedule-series.dto";
import { BulkLessonRateDto } from "./dto/bulk-lesson-rate.dto";
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";
import { LessonRow, formatLessonTimeMoscow, toLessonDto } from "./crm-mappers";
import { assertLessonPatchUsesTransition } from "./schedule/lesson-protected-patch.guard";
import { SubscriptionReservationService } from "./commerce/subscription-reservation.service";
import { ScheduleConstraintEngine } from "./schedule/constraint-engine.service";

interface SeriesConstraintClientRef {
  type: "lead" | "student";
  id: string;
}

interface SeriesConstraintCandidate {
  series_date: string;
  plan_id: string | null;
  group_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  starts_at: Date | string;
  ends_at: Date | string;
  client_refs: SeriesConstraintClientRef[] | null;
}

interface ScheduleLessonRow extends LessonRow {
  conflict_types: string[] | null;
  group_participants?: Array<{
    clientId: string;
    clientName: string | null;
  }> | null;
  // Partner lesson ids this lesson overlaps with, per conflict type. Used to
  // deduplicate the aggregated conflicts list to one entry per pair (KVA-166).
  room_overlap_ids?: string[] | null;
  teacher_overlap_ids?: string[] | null;
}

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

interface ScheduleQueryExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

// One busy-slot hit for the conflicts endpoint / 409 payload (contracts 1-2).
interface ConflictRow {
  lesson_id: string;
  title: string;
  starts_at: Date | string;
  ends_at: Date | string;
  room_name: string | null;
  teacher_name: string | null;
  teacher_hit: boolean;
  room_hit: boolean;
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
    private readonly constraints: ScheduleConstraintEngine,
    private readonly reservations?: SubscriptionReservationService,
  ) {}

  async getScheduleMatrix(actor: ActorContext, query: ScheduleMatrixQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 300, 500);
    const bounds = this.scheduleMatrixBounds(query);
    const groupBy = query.groupBy ?? "room";
    const result = await this.database.query<ScheduleLessonRow>(
      `
        with scoped as (
          select l.id, l.version, l.lifecycle_state, l.student_id, l.group_id, l.lead_id, l.teacher_id,
            l.branch_id, l.room_id, l.scheduled_at, l.duration_minutes,
            l.status, l.is_trial, l.notes,
            case when ${managerAdminRolesSql("$10")}
              then plan.failure_code else null end as settlement_failure_code,
            sp.user_id as student_user_id, tp.user_id as teacher_user_id,
            trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
            trim(coalesce(ld.first_name, '') || ' ' || coalesce(ld.last_name, '')) as lead_name,
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
          left join app.leads ld on ld.id = l.lead_id and ld.deleted_at is null
          left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          left join app.branches b on b.id = l.branch_id and b.deleted_at is null
          left join app.rooms r on r.id = l.room_id and r.deleted_at is null
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          left join app.lesson_settlement_plans plan on plan.lesson_id = l.id
          where l.deleted_at is null
            and l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
            and l.scheduled_at >= $1::timestamptz
            and l.scheduled_at < $2::timestamptz
            and ($3::uuid is null or l.branch_id = $3 or g.branch_id = $3 or r.branch_id = $3)
            and ($4::uuid is null or l.room_id = $4)
            and ($5::uuid is null or l.teacher_id = $5)
            and ($6::uuid is null or l.student_id = $6)
            and ($7::uuid is null or l.lead_id = $7)
            and ($8::boolean is null or l.is_trial = $8)
            and ($10::text <> 'teacher' or tp.user_id = $11::uuid)
          order by l.scheduled_at asc, l.id asc
          limit $9
        )
        select scoped.id, scoped.version, scoped.lifecycle_state, scoped.settlement_failure_code,
          scoped.student_id, scoped.group_id, scoped.lead_id,
          scoped.teacher_id, scoped.branch_id, scoped.room_id,
          scoped.scheduled_at, scoped.duration_minutes, scoped.status,
          scoped.is_trial, scoped.notes, scoped.student_user_id,
          scoped.teacher_user_id, scoped.student_name, scoped.lead_name,
          scoped.teacher_name,
          scoped.branch_name, scoped.room_name, scoped.group_name,
          scoped.group_price_per_lesson,
          coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'clientId', participant.student_id,
                'clientName', nullif(trim(
                  coalesce(participant_profile.first_name, '') || ' ' ||
                  coalesce(participant_profile.last_name, '')
                ), '')
              )
              order by participant_profile.last_name,
                participant_profile.first_name, participant.student_id
            )
            from app.lesson_snapshot_participants participant
            join app.students participant_student
              on participant_student.id = participant.student_id
            left join app.profiles participant_profile
              on participant_profile.id = participant_student.profile_id
            where participant.lesson_id = scoped.id
              and not exists (
                select 1
                from app.lesson_participant_exclusions exclusion
                where exclusion.lesson_id = participant.lesson_id
                  and exclusion.student_id = participant.student_id
              )
          ), '[]'::jsonb) as group_participants,
          array_remove(array[
            case when scoped.teacher_id is null then 'missing_teacher' end,
            case when scoped.room_id is not null and scoped.branch_id is not null
              and scoped.room_branch_id is not null and scoped.branch_id <> scoped.room_branch_id
              then 'branch_mismatch' end,
            case when scoped.room_id is not null and exists (
              select 1
              from app.lessons other_room
              where other_room.deleted_at is null
                and other_room.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
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
                and other_teacher.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
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
              and other_room.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
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
              and other_teacher.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
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
        query.studentId ?? null,
        query.leadId ?? null,
        query.isTrial ?? null,
        limit,
        actor.role,
        actor.userId,
      ],
    );
    const items = result.rows.map((row) => ({
      ...toLessonDto(row),
      groupParticipants: row.group_participants ?? [],
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
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where l.deleted_at is null
          and l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
          and l.scheduled_at >= $1::timestamptz
          and l.scheduled_at <  $2::timestamptz
          and ($3::uuid is null or l.branch_id = $3 or r.branch_id = $3)
          and ($4::text <> 'teacher' or tp.user_id = $5::uuid)
        group by 1
        order by 1
      `,
      [
        bounds.from,
        bounds.to,
        query.branchId ?? null,
        actor.role,
        actor.userId,
      ],
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
    // Gated: this endpoint serves clients and teachers too (see the note
    // above), so the rate is selected only for staff who may see it — everyone
    // else gets null rather than a leak. Per the owner's 16.07 decision a
    // per-lesson rate is NOT school-wide finance, so admin/manager see it;
    // the aggregate revenue view stays director-only (canReadSchoolFinance).
    const canSeeRates = this.policy.canReadTeacherRates(actor);
    const appliedRateSql = canSeeRates
      ? `coalesce(
            l.teacher_rate,
            g.teacher_rate,
            (
              select tr.rate
              from app.teacher_rates tr
              where tr.teacher_id = l.teacher_id
                and tr.deleted_at is null
                and tr.effective_from <= l.scheduled_at::date
              order by tr.effective_from desc, tr.created_at desc
              limit 1
            ),
            0
          )`
      : `null::numeric`;
    // «Оплаты по дням» (✔ владелец 17.07): сколько пришло за ЭТОТ день.
    //
    // Намеренно без coalesce(…, 0): пустая сумма — это «за этот день платежа
    // нет», а не «оплачено 0». Разница существенная, потому что платёж к
    // занятию привязывать не обязательно (аванс на счёт, абонемент, импорт из
    // HolliHop — там такой связи нет вовсе), и рисовать всем этим дням
    // уверенный ноль значило бы называть их неоплаченными.
    //
    // Гейт: педагогу деньги клиента не показываем. Клиент видит свои — выборка
    // выше и так отдаёт ему только его занятия.
    const canSeePayments =
      this.policy.canReadStudentFinance(actor) || actor.role === "client";
    const clientChargeSnapshotSql = canSeePayments
      ? "snapshot.client_charge_type"
      : "null::text";
    const clientChargeValueSnapshotSql = canSeePayments
      ? "snapshot.client_charge_value"
      : "null::numeric";
    const subscriptionSnapshotSql = canSeePayments
      ? "snapshot.subscription_id"
      : "null::uuid";
    const teacherCompensationSnapshotSql = canSeeRates
      ? "snapshot.teacher_compensation_type"
      : "null::text";
    const teacherCompensationValueSnapshotSql = canSeeRates
      ? "snapshot.teacher_compensation_value"
      : "null::numeric";
    // Closed enum from the DTO (@IsIn) — never raw user input. desc serves the
    // client «История»: with limit 50 the OLD asc order returned the 50 oldest
    // imported lessons and hid everything recent.
    const sortDir = query.order === "desc" ? "desc" : "asc";
    const paidSql = canSeePayments
      ? `(
            select sum(pay.amount)
            from app.commerce_ordinary_payments pay
            where pay.lesson_id = l.id and pay.deleted_at is null
          )`
      : `null::numeric`;
    const settlementFailureSql = isManagerOrAdminRole(actor.role)
      ? "plan.failure_code"
      : "null::text";
    const result = await this.database.query<LessonRow>(
      `
        select l.id, l.version, l.lifecycle_state,
          l.student_id, l.group_id, l.lead_id, l.teacher_id, l.branch_id, l.room_id, l.scheduled_at,
          l.duration_minutes, l.status, l.is_trial, l.notes, l.teacher_rate,
          snapshot.completion_type,
          ${clientChargeSnapshotSql} as client_charge_type,
          ${clientChargeValueSnapshotSql} as client_charge_value,
          ${teacherCompensationSnapshotSql} as teacher_compensation_type,
          ${teacherCompensationValueSnapshotSql} as teacher_compensation_value,
          ${subscriptionSnapshotSql} as subscription_id,
          snapshot.trial as snapshot_trial,
          snapshot.validation_state as snapshot_validation_state,
          reservation.state as reservation_state,
          ${settlementFailureSql} as settlement_failure_code,
          ${appliedRateSql} as applied_teacher_rate,
          ${paidSql} as paid_amount,
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
        left join app.lesson_snapshots snapshot on snapshot.lesson_id = l.id
        left join app.lesson_settlement_plans plan on plan.lesson_id = l.id
        left join lateral (
          select lesson_reservation.state
          from app.lesson_reservations lesson_reservation
          where lesson_reservation.lesson_id = l.id
          order by lesson_reservation.updated_at desc, lesson_reservation.id desc
          limit 1
        ) reservation on true
        where l.deleted_at is null
          and (
            $3::uuid is not null
            or l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
          )
          and ($3::uuid is null or l.id = $3)
          and (
            $4::uuid is null
            or l.student_id = $4
            or exists (
              select 1
              from app.group_students filter_gs
              where filter_gs.group_id = l.group_id
                and filter_gs.student_id = $4
                and filter_gs.left_at is null
            )
          )
          and ($5::uuid is null or l.teacher_id = $5)
          and ($6::timestamptz is null or l.scheduled_at >= $6)
          and ($7::timestamptz is null or l.scheduled_at <= $7)
          and ($8::boolean is null or l.is_trial = $8)
          and (
            ${managerAdminRolesSql("$1")}
            or ($1::text = 'teacher' and tp.user_id = $2)
            or ($1::text = 'client' and ${this.clientLessonAccessSql("$2")})
          )
        order by l.scheduled_at ${sortDir}, l.id ${sortDir}
        limit $9
      `,
      [
        actor.role,
        actor.userId,
        query.lessonId ?? null,
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

  /**
   * Contract 1: busy-slot lookup for the lesson dialog pre-flight. Overlap
   * semantics mirror getScheduleMatrix: cancelled and soft-deleted lessons
   * never conflict, and two rows of the SAME group are one class, not a clash.
   */
  async getScheduleConflicts(
    actor: ActorContext,
    query: ScheduleConflictsQuery,
  ) {
    this.policy.assertManagerOnly(actor);
    const startsAt = new Date(query.startsAt);
    const endsAt = new Date(query.endsAt);
    if (
      Number.isNaN(startsAt.getTime()) ||
      Number.isNaN(endsAt.getTime()) ||
      startsAt.getTime() >= endsAt.getTime()
    ) {
      throw new BadRequestException(
        "Время окончания должно быть позже времени начала.",
      );
    }
    const rows = await this.queryConflicts({
      teacherId: query.teacherId ?? null,
      roomId: query.roomId ?? null,
      startsAt: startsAt.toISOString(),
      endsAt: endsAt.toISOString(),
      excludeLessonId: query.excludeLessonId ?? null,
      groupId: null,
    });
    return {
      teacherBusy: rows.some((row) => row.teacher_hit),
      roomBusy: rows.some((row) => row.room_hit),
      conflicts: rows.map((row) => this.toConflictDto(row)),
    };
  }

  private toConflictDto(row: ConflictRow) {
    return {
      lessonId: row.lesson_id,
      title: row.title,
      startsAt: row.starts_at,
      endsAt: row.ends_at,
      roomName: row.room_name ?? null,
      teacherName: row.teacher_name || null,
    };
  }

  /**
   * Shared overlap SQL for contract 1 (GET conflicts) and contract 2 (the
   * 409-on-busy guard). Sargable bounds lean on the partial indexes
   * lessons_teacher_active_overlap_idx / lessons_room_active_overlap_idx. The
   * lifecycle predicate removes terminal cancellation/reschedule sources; the
   * exact check is the tstzrange overlap. A lesson longer than 24h does not
   * exist (durationMinutes is capped at 360), so the cheap left bound of
   * «start > startsAt - 24h» is safe.
   */
  private async queryConflicts(
    params: {
      teacherId: string | null;
      roomId: string | null;
      startsAt: string | Date;
      endsAt: string | Date;
      excludeLessonId: string | null;
      groupId: string | null;
    },
    executor: ScheduleQueryExecutor = this.database,
  ): Promise<ConflictRow[]> {
    if (!params.teacherId && !params.roomId) return [];
    const result = await executor.query<ConflictRow>(
      `
        select l.id as lesson_id,
          l.scheduled_at as starts_at,
          l.scheduled_at + l.duration_minutes * interval '1 minute' as ends_at,
          ($1::uuid is not null and l.teacher_id = $1) as teacher_hit,
          ($2::uuid is not null and l.room_id = $2) as room_hit,
          r.name as room_name,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          coalesce(
            nullif(g.name, ''),
            nullif(trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')), ''),
            nullif(trim(coalesce(ld.first_name, '') || ' ' || coalesce(ld.last_name, '')), ''),
            'Занятие'
          ) as title
        from app.lessons l
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.leads ld on ld.id = l.lead_id and ld.deleted_at is null
        where l.deleted_at is null
          and l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
          and ($5::uuid is null or l.id <> $5)
          and l.scheduled_at < $4::timestamptz
          and l.scheduled_at > $3::timestamptz - interval '24 hours'
          and tstzrange(l.scheduled_at, l.scheduled_at + l.duration_minutes * interval '1 minute', '[)')
              && tstzrange($3::timestamptz, $4::timestamptz, '[)')
          -- Matrix semantics: the same group's rows share teacher and room by
          -- construction — that is one class, not a double-booking.
          and (l.group_id is null or $6::uuid is null or l.group_id <> $6)
          and (
            ($1::uuid is not null and l.teacher_id = $1)
            or ($2::uuid is not null and l.room_id = $2)
          )
        order by l.scheduled_at asc, l.id asc
        limit 20
      `,
      [
        params.teacherId,
        params.roomId,
        params.startsAt,
        params.endsAt,
        params.excludeLessonId,
        params.groupId,
      ],
    );
    return result.rows;
  }

  private async acquireScheduleResourceLocks(
    executor: ScheduleQueryExecutor,
    teacherId: string | null,
    roomId: string | null,
  ): Promise<void> {
    await this.acquireScheduleLockKeys(executor, [
      teacherId ? `teacher:${teacherId}` : null,
      roomId ? `room:${roomId}` : null,
    ]);
  }

  /**
   * Advisory locks are always acquired in lexical order. Besides making
   * create/update conflict checks atomic, the deterministic order prevents two
   * cross-resource moves (teacher A -> B and B -> A) from deadlocking.
   */
  private async acquireScheduleLockKeys(
    executor: ScheduleQueryExecutor,
    keys: Array<string | null | undefined>,
  ): Promise<void> {
    const resources = [
      ...new Set(
        keys
          .filter(
            (resource): resource is string => typeof resource === "string",
          )
          .map((resource) => resource.toLowerCase()),
      ),
    ].sort();
    for (const resource of resources) {
      await executor.query(
        "select pg_advisory_xact_lock(hashtextextended($1::text, 0))",
        [resource],
      );
    }
  }

  private acquireScheduleSeriesLock(
    executor: ScheduleQueryExecutor,
    seriesId: string,
  ): Promise<void> {
    return this.acquireScheduleLockKeys(executor, [`series:${seriesId}`]);
  }

  /**
   * Serialize aggregate Plan mutations with the horizon worker. Plan commands
   * live in SchedulePlanService, but must use the exact same per-series lock
   * keys as materializeSeries or a worker can add occurrences after impact was
   * calculated and before the Plan mutation commits.
   */
  lockSchedulePlanSeries(
    client: PoolClient,
    seriesIds: string[],
  ): Promise<void> {
    return this.acquireScheduleLockKeys(
      client,
      seriesIds.map((seriesId) => `series:${seriesId}`),
    );
  }

  /**
   * Contract 2: throw 409 {message, conflicts} when the teacher OR the room is
   * busy in the slot. No role may bypass a scheduling conflict.
   */
  private async assertNoScheduleConflicts(
    params: {
      teacherId: string | null;
      roomId: string | null;
      startsAt: string | Date;
      durationMinutes: number;
      excludeLessonId?: string | null;
      groupId?: string | null;
    },
    executor: ScheduleQueryExecutor,
  ): Promise<void> {
    await this.acquireScheduleResourceLocks(
      executor,
      params.teacherId,
      params.roomId,
    );
    if (!params.teacherId && !params.roomId) return;
    const startsAt = new Date(params.startsAt);
    if (Number.isNaN(startsAt.getTime())) return;
    const endsAt = new Date(
      startsAt.getTime() + params.durationMinutes * 60_000,
    );
    const rows = await this.queryConflicts(
      {
        teacherId: params.teacherId,
        roomId: params.roomId,
        startsAt: startsAt.toISOString(),
        endsAt: endsAt.toISOString(),
        excludeLessonId: params.excludeLessonId ?? null,
        groupId: params.groupId ?? null,
      },
      executor,
    );
    if (!rows.length) return;
    throw new ConflictException({
      message: "Преподаватель или аудитория заняты в это время.",
      conflicts: rows.map((row) => this.toConflictDto(row)),
    });
  }

  /**
   * Contract 7: map the pinned clientRef {type, id} onto the legacy
   * studentId/leadId fields. An explicit clientRef wins over both.
   */
  private clientLessonAccessSql(userIdExpression: string): string {
    return `(
      sp.user_id = ${userIdExpression}
      or exists (
        select 1
        from app.user_crm_links student_link
        where student_link.user_id = ${userIdExpression}
          and student_link.entity_type = 'student'
          and student_link.entity_id = l.student_id
          and student_link.deleted_at is null
      )
      or exists (
        select 1
        from app.profiles account_profile
        join app.family_members account_member
          on account_member.entity_type = 'profile'
         and account_member.entity_id = account_profile.id
         and account_member.role in ('parent', 'payer')
         and account_member.deleted_at is null
        join app.families family
          on family.id = account_member.family_id and family.deleted_at is null
        join app.family_members student_member
          on student_member.family_id = family.id
         and student_member.entity_type = 'student'
         and student_member.entity_id = l.student_id
         and student_member.deleted_at is null
        where account_profile.user_id = ${userIdExpression}
          and account_profile.deleted_at is null
      )
      or exists (
        select 1
        from app.user_crm_links lead_link
        where lead_link.user_id = ${userIdExpression}
          and lead_link.entity_type = 'lead'
          and lead_link.entity_id = l.lead_id
          and lead_link.deleted_at is null
      )
      or exists (
        select 1
        from app.profiles account_profile
        join app.family_members account_member
          on account_member.entity_type = 'profile'
         and account_member.entity_id = account_profile.id
         and account_member.role in ('parent', 'payer')
         and account_member.deleted_at is null
        join app.families family
          on family.id = account_member.family_id and family.deleted_at is null
        join app.family_members lead_member
          on lead_member.family_id = family.id
         and lead_member.entity_type = 'lead'
         and lead_member.entity_id = l.lead_id
         and lead_member.deleted_at is null
        where account_profile.user_id = ${userIdExpression}
          and account_profile.deleted_at is null
      )
      or exists (
        select 1
        from app.group_students actor_group_student
        join app.students actor_student
          on actor_student.id = actor_group_student.student_id
         and actor_student.deleted_at is null
        join app.profiles actor_profile
          on actor_profile.id = actor_student.profile_id
         and actor_profile.deleted_at is null
        where actor_group_student.group_id = l.group_id
          and actor_group_student.left_at is null
          and actor_profile.user_id = ${userIdExpression}
      )
      or exists (
        select 1
        from app.group_students actor_group_student
        join app.user_crm_links group_student_link
          on group_student_link.entity_type = 'student'
         and group_student_link.entity_id = actor_group_student.student_id
         and group_student_link.deleted_at is null
        where actor_group_student.group_id = l.group_id
          and actor_group_student.left_at is null
          and group_student_link.user_id = ${userIdExpression}
      )
      or exists (
        select 1
        from app.group_students actor_group_student
        join app.family_members group_student_member
          on group_student_member.entity_type = 'student'
         and group_student_member.entity_id = actor_group_student.student_id
         and group_student_member.deleted_at is null
        join app.families family
          on family.id = group_student_member.family_id and family.deleted_at is null
        join app.family_members account_member
          on account_member.family_id = family.id
         and account_member.entity_type = 'profile'
         and account_member.role in ('parent', 'payer')
         and account_member.deleted_at is null
        join app.profiles account_profile
          on account_profile.id = account_member.entity_id
         and account_profile.deleted_at is null
        where actor_group_student.group_id = l.group_id
          and actor_group_student.left_at is null
          and account_profile.user_id = ${userIdExpression}
      )
    )`;
  }

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
      await this.assertNoScheduleConflicts(
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

  // ── KVA-236: постоянное расписание (серии) ────────────────────────────────

  /** Горизонт материализации занятий серии, дней вперёд. */
  private static readonly MAX_BOOKING_AHEAD_DAYS = 365;
  private static readonly INDIVIDUAL_SERIES_HORIZON_DAYS = 60;
  private static readonly GROUP_SERIES_HORIZON_DAYS = 400;

  /**
   * Догенерировать занятия серии до горизонта. Идемпотентно: дата серии,
   * уже закрытая строкой lessons.series_date (включая перенесённые и
   * отменённые), повторно не создаётся.
   */
  private async seriesConstraintCandidates(
    seriesId: string,
    executor: ScheduleQueryExecutor = this.database,
  ): Promise<SeriesConstraintCandidate[]> {
    const result = await executor.query<SeriesConstraintCandidate>(
      `
        with target as (
          select s.*,
            coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow')
              as effective_timezone,
            timezone(
              coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              now()
            )::date as local_today
          from app.schedule_series s
          left join app.branches branch
            on branch.id = s.branch_id and branch.deleted_at is null
          where s.id = $1 and s.deleted_at is null
        ), candidates as (
          select s.id as series_id, s.plan_id, s.client_type, s.client_id,
            s.student_id, s.group_id, s.teacher_id, s.branch_id, s.room_id,
            d::date as series_date,
            (d::date + s.begin_time) at time zone s.effective_timezone
              as starts_at,
            (d::date + s.begin_time) at time zone s.effective_timezone
              + s.duration_minutes * interval '1 minute' as ends_at
          from target s
          cross join lateral generate_series(
            greatest(s.valid_from, s.local_today)::timestamp,
            least(
              coalesce(s.valid_until, s.local_today
                + case when s.plan_id is not null or s.group_id is null
                    then $2::int else $3::int end),
              s.local_today
                + case when s.plan_id is not null or s.group_id is null
                    then $2::int else $3::int end
            )::timestamp,
            interval '1 day'
          ) as d
          where extract(isodow from d) = s.weekday
            and not exists (
              select 1 from app.lessons lesson
              where lesson.series_id = s.id and lesson.series_date = d::date
            )
        )
        select candidate.series_date::text, candidate.plan_id,
          candidate.group_id, candidate.teacher_id, candidate.branch_id,
          candidate.room_id, candidate.starts_at, candidate.ends_at,
          case
            when candidate.client_type is not null
              and candidate.client_id is not null
              then jsonb_build_array(jsonb_build_object(
                'type', candidate.client_type,
                'id', candidate.client_id
              ))
            when candidate.student_id is not null
              then jsonb_build_array(jsonb_build_object(
                'type', 'student',
                'id', candidate.student_id
              ))
            when candidate.plan_id is not null then coalesce((
              select jsonb_agg(
                jsonb_build_object('type', 'student', 'id', participant.student_id)
                order by participant.student_id
              )
              from app.schedule_plan_participants participant
              where participant.plan_id = candidate.plan_id
                and participant.effective_from <= candidate.series_date
                and (participant.effective_until is null
                  or participant.effective_until >= candidate.series_date)
            ), '[]'::jsonb)
            when candidate.group_id is not null then coalesce((
              select jsonb_agg(
                jsonb_build_object('type', 'student', 'id', membership.student_id)
                order by membership.student_id
              )
              from app.group_students membership
              join app.students student
                on student.id = membership.student_id and student.deleted_at is null
              where membership.group_id = candidate.group_id
                and membership.left_at is null
            ), '[]'::jsonb)
            else '[]'::jsonb
          end as client_refs
        from candidates candidate
        order by candidate.series_date
      `,
      [
        seriesId,
        ScheduleService.INDIVIDUAL_SERIES_HORIZON_DAYS,
        ScheduleService.GROUP_SERIES_HORIZON_DAYS,
      ],
    );
    return result.rows;
  }

  private seriesConstraintLockKeys(candidates: SeriesConstraintCandidate[]) {
    return candidates.flatMap((candidate) => [
      candidate.plan_id ? `plan:${candidate.plan_id}` : null,
      candidate.branch_id ? `branch:${candidate.branch_id}` : null,
      candidate.room_id ? `room:${candidate.room_id}` : null,
      candidate.teacher_id ? `teacher:${candidate.teacher_id}` : null,
      ...(candidate.client_refs ?? []).map(
        (clientRef) => `client:${clientRef.type}:${clientRef.id}`,
      ),
    ]);
  }

  private async assertNoScheduleSeriesConflicts(
    seriesId: string,
    executor: ScheduleQueryExecutor = this.database,
  ): Promise<void> {
    const beforeLock = await this.seriesConstraintCandidates(
      seriesId,
      executor,
    );
    const lockedKeys = this.seriesConstraintLockKeys(beforeLock);
    await this.acquireScheduleLockKeys(executor, lockedKeys);
    await this.acquireScheduleSeriesLock(executor, seriesId);

    // A Plan edit can finish while the worker waits for its locks. Re-read after
    // locking and fail closed if the series moved to resources we did not lock.
    const candidates = await this.seriesConstraintCandidates(
      seriesId,
      executor,
    );
    const normalizedLockedKeys = new Set(
      lockedKeys
        .filter((key): key is string => typeof key === "string")
        .map((key) => key.toLowerCase()),
    );
    if (
      this.seriesConstraintLockKeys(candidates).some(
        (key) => key != null && !normalizedLockedKeys.has(key.toLowerCase()),
      )
    ) {
      throw new ConflictException({
        code: "SCHEDULE_SERIES_RESOURCES_CHANGED",
        message: "Schedule series resources changed during materialization.",
      });
    }

    for (const candidate of candidates) {
      if (!candidate.teacher_id || !candidate.branch_id || !candidate.room_id) {
        throw new UnprocessableEntityException({
          code: "LESSON_SERIES_REQUIRED_RESOURCES_MISSING",
          message: "Lesson series requires teacher, branch and room.",
          occurrence: { localDate: candidate.series_date },
        });
      }
      const clientRefs = candidate.client_refs?.length
        ? candidate.client_refs
        : [
            {
              type: "student" as const,
              id: candidate.group_id ?? seriesId,
            },
          ];
      for (const clientRef of clientRefs) {
        const result = await this.constraints.validate(
          {
            clientRef,
            teacherId: candidate.teacher_id,
            branchId: candidate.branch_id,
            roomId: candidate.room_id,
            startAt: candidate.starts_at,
            endAt: candidate.ends_at,
            excludeScheduleSeriesIds: [seriesId],
          },
          executor as unknown as PoolClient,
        );
        if (!result.valid) {
          throw new UnprocessableEntityException({
            code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
            message: "Lesson series occurrence violates schedule constraints.",
            occurrence: {
              localDate: candidate.series_date,
              startAt: new Date(candidate.starts_at).toISOString(),
              endAt: new Date(candidate.ends_at).toISOString(),
            },
            clientRef,
            violations: result.violations,
          });
        }
      }
    }
  }

  private async materializeSeries(
    seriesId: string,
    executor: ScheduleQueryExecutor = this.database,
  ): Promise<number> {
    // The worker, edit and stop flows all serialize on the same key. Without
    // this lock a worker can commit old future lessons after an edit deleted
    // them, or two edits can create competing continuations.
    await this.assertNoScheduleSeriesConflicts(seriesId, executor);
    const result = await executor.query<{ id: string }>(
      `
        insert into app.lessons (
          student_id, group_id, teacher_id, branch_id, room_id,
          scheduled_at, duration_minutes, status, is_trial,
          series_id, series_date, created_by
        )
        select s.student_id, s.group_id, s.teacher_id, s.branch_id, s.room_id,
          (d::date + s.begin_time) at time zone
            coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
          s.duration_minutes, 'scheduled', false,
          s.id, d::date, s.created_by
        from app.schedule_series s
        left join app.branches branch
          on branch.id = s.branch_id and branch.deleted_at is null
        cross join lateral generate_series(
          greatest(
            s.valid_from,
            timezone(
              coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              now()
            )::date
          )::timestamp,
          least(
              coalesce(s.valid_until, timezone(
                coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
                now()
              )::date
                + case when s.plan_id is not null or s.group_id is null
                    then $2::int else $3::int end),
              timezone(
                coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
                now()
              )::date
                + case when s.plan_id is not null or s.group_id is null
                    then $2::int else $3::int end
          )::timestamp,
          interval '1 day'
        ) as d
        where s.id = $1 and s.deleted_at is null
          and extract(isodow from d) = s.weekday
          and not exists (
            select 1 from app.lessons l
            where l.series_id = s.id and l.series_date = d::date
          )
        on conflict (series_id, series_date) where deleted_at is null
        do nothing
        returning id
      `,
      [
        seriesId,
        ScheduleService.INDIVIDUAL_SERIES_HORIZON_DAYS,
        ScheduleService.GROUP_SERIES_HORIZON_DAYS,
      ],
    );
    const lessonIds = result.rows.map((row) => row.id);
    if (lessonIds.length === 0) return 0;
    await executor.query(
      `
        with candidate as (
          select lesson.id, lesson.scheduled_at, lesson.duration_minutes,
                 series.client_type, series.client_id, series.completion_type,
                 series.client_charge_type, series.client_charge_value,
                 series.teacher_compensation_type,
                 series.teacher_compensation_value, series.subscription_id,
                 series.trial,
                 case
                   when student.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                     then (student.custom_data->>'individualPrice')::numeric
                   when student.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                     then (student.custom_data->>'individual_price')::numeric
                   else null
                 end as personal_price,
                 row_number() over (order by lesson.scheduled_at, lesson.id) as position
            from app.lessons lesson
            join app.schedule_series series on series.id = lesson.series_id
            left join app.students student
              on series.client_type = 'student' and student.id = series.client_id
           where lesson.id = any($1::uuid[]) and series.client_type is not null
        ), capacity as (
          select subscription.id,
                 greatest(0,
                   subscription.lessons_total - subscription.lessons_used
                   - coalesce((select sum(reservation.units)
                       from app.lesson_reservations reservation
                       where reservation.subscription_id = subscription.id
                         and reservation.state = 'reserved'), 0)
                   - coalesce((select sum(fact.units)
                       from app.lesson_client_charge_facts_effective fact
                       where fact.subscription_id = subscription.id
                         and fact.charge_type = 'subscription'), 0)
                 ) as available
            from app.subscriptions subscription
           where subscription.id = (
             select subscription_id from candidate limit 1
           )
             and subscription.status = 'active'
             and subscription.commercial_snapshot is not null
        ), resolved as (
          select candidate.*,
                 case
                   when candidate.client_charge_type = 'subscription'
                     and exists (
                       select 1 from capacity
                       where capacity.available >= candidate.position
                         * candidate.client_charge_value
                     )
                     and exists (
                       select 1 from app.subscriptions subscription
                       where subscription.id = candidate.subscription_id
                         and (subscription.starts_at is null
                           or subscription.starts_at <= candidate.scheduled_at::date)
                         and (subscription.expires_at is null
                           or subscription.expires_at >= candidate.scheduled_at::date)
                     ) then 'subscription'
                   when candidate.client_charge_type = 'subscription'
                     then 'personal_account'
                   else candidate.client_charge_type
                 end as resolved_charge_type
            from candidate
        )
        insert into app.lesson_snapshots (
          lesson_id, client_type, client_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          subscription_id, trial, duration_minutes
        )
        select id, client_type, client_id, completion_type,
               resolved_charge_type,
               case when resolved_charge_type = 'personal_account'
                      and client_charge_type = 'subscription'
                    then personal_price
                    else client_charge_value end,
               teacher_compensation_type, teacher_compensation_value,
               case when resolved_charge_type = 'subscription'
                    then subscription_id else null end,
               trial, duration_minutes
          from resolved
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_snapshots (
          lesson_id, client_type, client_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          subscription_id, trial, duration_minutes
        )
        select lesson.id, 'student', plan.student_id, 'scheduled',
          'subscription',
          round(
            lesson.duration_minutes::numeric
              * (settlement.item->>'hourShareBasisPoints')::numeric / 6000
          ) / 100,
          case when rate.value > 0 then 'fixed' else 'none' end,
          rate.value, plan.subscription_id, false, lesson.duration_minutes
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.schedule_plans plan on plan.id = series.plan_id
        join app.crm_configuration_revisions revision
          on revision.id = series.settlement_revision_id
        cross join lateral (
          select item
          from jsonb_array_elements(
            revision.effective_snapshot->'lessonSettlementTypes'
          ) item
          where item->>'stableKey' =
            series.planned_financial_decision->>'settlementTypeKey'
          limit 1
        ) settlement
        cross join lateral (
          select coalesce((
            select teacher_rate.rate
            from app.teacher_rates teacher_rate
            where teacher_rate.teacher_id = series.teacher_id
              and teacher_rate.deleted_at is null
              and teacher_rate.effective_from <= lesson.scheduled_at::date
            order by teacher_rate.effective_from desc, teacher_rate.created_at desc
            limit 1
          ), 0)::numeric as value
        ) rate
        where lesson.id = any($1::uuid[]) and plan.kind = 'individual'
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_snapshots (
          lesson_id, group_id, completion_type,
          client_charge_type, client_charge_value,
          teacher_compensation_type, teacher_compensation_value,
          trial, duration_minutes
        )
        select lesson.id, plan.group_id, 'scheduled', 'none', 0,
          case when rate.value > 0 then 'fixed' else 'none' end,
          rate.value, false, lesson.duration_minutes
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.schedule_plans plan on plan.id = series.plan_id
        join app.groups lesson_group on lesson_group.id = plan.group_id
        cross join lateral (
          select coalesce(lesson_group.teacher_rate, (
            select teacher_rate.rate
            from app.teacher_rates teacher_rate
            where teacher_rate.teacher_id = series.teacher_id
              and teacher_rate.deleted_at is null
              and teacher_rate.effective_from <= lesson.scheduled_at::date
            order by teacher_rate.effective_from desc, teacher_rate.created_at desc
            limit 1
          ), 0)::numeric as value
        ) rate
        where lesson.id = any($1::uuid[]) and plan.kind = 'group'
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_snapshot_participants (
          lesson_id, student_id, charge_type, charge_value, subscription_id
        )
        select lesson.id, participant.student_id, 'subscription',
          round(
            lesson.duration_minutes::numeric
              * (settlement.item->>'hourShareBasisPoints')::numeric / 6000
          ) / 100,
          participant.subscription_id
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.crm_configuration_revisions revision
          on revision.id = series.settlement_revision_id
        cross join lateral (
          select item
          from jsonb_array_elements(
            revision.effective_snapshot->'lessonSettlementTypes'
          ) item
          where item->>'stableKey' =
            series.planned_financial_decision->>'settlementTypeKey'
          limit 1
        ) settlement
        join app.schedule_plan_participants participant
          on participant.plan_id = series.plan_id
         and participant.effective_from <= lesson.series_date
         and (participant.effective_until is null
           or participant.effective_until >= lesson.series_date)
        where lesson.id = any($1::uuid[])
        on conflict (lesson_id, student_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_settlement_plans (
          lesson_id, decision, settlement_revision_id,
          compensation_revision_id, selected_by
        )
        select lesson.id, series.planned_financial_decision,
          series.settlement_revision_id, series.compensation_revision_id,
          series.created_by
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        where lesson.id = any($1::uuid[])
          and series.planned_financial_decision is not null
        on conflict (lesson_id) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_settlement_plan_revisions (
          lesson_id, version, decision, settlement_revision_id,
          compensation_revision_id, actor_user_id
        )
        select lesson.id, 1, series.planned_financial_decision,
          series.settlement_revision_id, series.compensation_revision_id,
          series.created_by
        from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        join app.lesson_settlement_plans plan on plan.lesson_id = lesson.id
        where lesson.id = any($1::uuid[])
          and series.planned_financial_decision is not null
        on conflict (lesson_id, version) do nothing
      `,
      [lessonIds],
    );
    await executor.query(
      `
        insert into app.lesson_reservations (lesson_id, subscription_id, units)
        select snapshot.lesson_id, snapshot.subscription_id,
               snapshot.client_charge_value
          from app.lesson_snapshots snapshot
          join app.lessons lesson on lesson.id = snapshot.lesson_id
          join app.schedule_series series on series.id = lesson.series_id
         where snapshot.lesson_id = any($1::uuid[])
           and snapshot.client_charge_type = 'subscription'
           and series.plan_id is null
        on conflict (lesson_id, subscription_id) do nothing
      `,
      [lessonIds],
    );
    const planCharges = await executor.query<{
      lesson_id: string;
      student_id: string;
      subscription_id: string;
      units: string;
    }>(
      `
        select snapshot.lesson_id, snapshot.client_id as student_id,
          snapshot.subscription_id, snapshot.client_charge_value::text as units
        from app.lesson_snapshots snapshot
        join app.lessons lesson on lesson.id = snapshot.lesson_id
        join app.schedule_series series on series.id = lesson.series_id
        where snapshot.lesson_id = any($1::uuid[])
          and series.plan_id is not null
          and snapshot.client_charge_type = 'subscription'
          and snapshot.client_charge_value > 0
        union all
        select participant.lesson_id, participant.student_id,
          participant.subscription_id, participant.charge_value::text
        from app.lesson_snapshot_participants participant
        join app.lessons lesson on lesson.id = participant.lesson_id
        join app.schedule_series series on series.id = lesson.series_id
        where participant.lesson_id = any($1::uuid[])
          and series.plan_id is not null
          and participant.charge_type = 'subscription'
          and participant.charge_value > 0
        order by subscription_id, lesson_id
      `,
      [lessonIds],
    );
    if (planCharges.rows.length && !this.reservations) {
      throw new Error(
        "SubscriptionReservationService is required for plan generation.",
      );
    }
    for (const charge of planCharges.rows) {
      await this.reservations!.allocate(executor as PoolClient, {
        lessonId: charge.lesson_id,
        clientType: "student",
        clientId: charge.student_id,
        chargeType: "subscription",
        subscriptionId: charge.subscription_id,
        units: Number(charge.units),
      });
    }
    await executor.query(
      `update app.schedule_series
       set occurrence_count = coalesce(occurrence_count, 0) + $2,
           updated_at = now()
       where id = $1 and client_type is not null`,
      [seriesId, lessonIds.length],
    );
    return lessonIds.length;
  }

  materializePlanSeries(client: PoolClient, seriesId: string): Promise<number> {
    return this.materializeSeries(seriesId, client);
  }

  /** Продлить все живые серии (вкл. «до бесконечности») — вызывается воркером. */
  async extendAllSeriesHorizon(): Promise<{
    series: number;
    created: number;
    failed: number;
  }> {
    const rows = await this.database.query<{ id: string }>(
      `
        select s.id
        from app.schedule_series s
        join app.branches branch on branch.id = s.branch_id
        where s.deleted_at is null
          and (
            s.valid_until is null
            or s.valid_until >= timezone(
              coalesce(s.timezone_name, branch.timezone_name, 'Europe/Moscow'),
              now()
            )::date
          )
      `,
    );
    let created = 0;
    let failed = 0;
    for (const row of rows.rows) {
      // Per-series isolation: one poison series must not starve every series
      // after it in the batch until the next worker tick.
      try {
        created += await this.database.transaction((client) =>
          this.materializeSeries(
            row.id,
            client as unknown as ScheduleQueryExecutor,
          ),
        );
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
        const created = await this.materializeSeries(
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
        await this.acquireScheduleSeriesLock(
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
        const created = await this.materializeSeries(
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
      await this.acquireScheduleSeriesLock(
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
      // even though listLessons will not even let them READ the applied rate
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

  private assertSeriesDateWithinBookingWindow(value: string): void {
    if (
      value.slice(0, 10) >
      this.moscowDate(ScheduleService.MAX_BOOKING_AHEAD_DAYS)
    ) {
      throw new BadRequestException(
        `Schedule date cannot be more than ${ScheduleService.MAX_BOOKING_AHEAD_DAYS} days ahead.`,
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
      (ScheduleService.MAX_BOOKING_AHEAD_DAYS + 1) * 24 * 60 * 60 * 1000;
    if (
      !Number.isFinite(scheduledAt.getTime()) ||
      scheduledAt.getTime() > upperBound
    ) {
      throw new BadRequestException(
        `Lesson cannot be scheduled more than ${ScheduleService.MAX_BOOKING_AHEAD_DAYS} days ahead.`,
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
