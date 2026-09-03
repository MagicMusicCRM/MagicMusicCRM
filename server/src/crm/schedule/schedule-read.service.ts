import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { LessonQuery } from "../dto/lesson.query";
import { ScheduleMatrixQuery } from "../dto/schedule-matrix.query";
import { LessonRow, toLessonDto } from "../crm-mappers";
import { currentActorRoleSql, managerBranchScopeSql } from "../branch-scope";

interface ScheduleLessonRow extends LessonRow {
  scheduled_utc_offset_minutes?: number | string | null;
  conflict_types: string[] | null;
  // Partner lesson ids this lesson overlaps with, per conflict type. Used to
  // deduplicate the aggregated conflicts list to one entry per pair (KVA-166).
  room_overlap_ids?: string[] | null;
  teacher_overlap_ids?: string[] | null;
}

@Injectable()
export class ScheduleReadService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
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
            reservation.state as reservation_state,
            (correction.decision is null and transition.financial_decision is null)
              as financial_decision_is_plan,
            case when ${managerAdminRolesSql(currentActorRoleSql("$11"))}
              then coalesce(correction.decision, transition.financial_decision, plan.decision)
              else null::jsonb end as financial_decision,
            case when ${managerAdminRolesSql(currentActorRoleSql("$11"))}
              then ${this.lessonClientFinancialBaselineSql("l.id")}
              else null::jsonb end as client_financial_baseline,
            case when ${managerAdminRolesSql(currentActorRoleSql("$11"))}
              then plan.failure_code else null end as settlement_failure_code,
            case when ${managerAdminRolesSql(currentActorRoleSql("$11"))}
              then coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'settlementTypeKey' else null end
              as settlement_type_key,
            case when ${managerAdminRolesSql(currentActorRoleSql("$11"))}
              then coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'teacherCompensationRuleKey' else null end
              as teacher_compensation_rule_key,
            case when ${managerAdminRolesSql(currentActorRoleSql("$11"))}
              then coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'teacherCompensationValueMinor' else null end
              as teacher_compensation_value_minor,
            extract(epoch from (
              timezone(coalesce(b.timezone_name, 'Europe/Moscow'), l.scheduled_at)
              - timezone('UTC', l.scheduled_at)
            )) / 60 as scheduled_utc_offset_minutes,
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
          left join app.rooms r on r.id = l.room_id and r.deleted_at is null
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          left join app.branches b
            on b.id = coalesce(l.branch_id, g.branch_id, r.branch_id)
           and b.deleted_at is null
          left join app.lesson_settlement_plans plan on plan.lesson_id = l.id
          left join lateral (
            select decision from app.lesson_settlement_corrections
            where lesson_id = l.id order by version desc limit 1
          ) correction on true
          left join lateral (
            select financial_decision from app.lesson_transitions
            where lesson_id = l.id and financial_decision <> '{}'::jsonb
            order by created_at desc, id desc limit 1
          ) transition on true
          left join lateral (
            select lesson_reservation.state
            from app.lesson_reservations lesson_reservation
            where lesson_reservation.lesson_id = l.id
            order by (lesson_reservation.state = 'reserved') desc,
              lesson_reservation.updated_at desc, lesson_reservation.id desc
            limit 1
          ) reservation on true
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
            and (
              $9::date is null
              or timezone(coalesce(b.timezone_name, 'Europe/Moscow'), l.scheduled_at)::date = $9::date
            )
            and (
              ${managerAdminRolesSql(currentActorRoleSql("$11"))}
              or (${currentActorRoleSql("$11")} = 'teacher' and tp.user_id = $11::uuid)
            )
            and ${managerBranchScopeSql({
              roleExpression: currentActorRoleSql("$11"),
              userIdExpression: "$11",
              branchExpression:
                "coalesce(l.branch_id::text, g.branch_id::text, r.branch_id::text)",
            })}
          order by l.scheduled_at asc, l.id asc
          limit $10
        )
        select scoped.id, scoped.version, scoped.lifecycle_state, scoped.settlement_failure_code,
          scoped.student_id, scoped.group_id, scoped.lead_id,
          scoped.teacher_id, scoped.branch_id, scoped.room_id,
          scoped.scheduled_at, scoped.scheduled_utc_offset_minutes,
          scoped.duration_minutes, scoped.status,
          scoped.is_trial, scoped.notes, scoped.student_user_id,
          scoped.teacher_user_id, scoped.student_name, scoped.lead_name,
          scoped.teacher_name,
          scoped.branch_name, scoped.room_name, scoped.group_name,
          scoped.group_price_per_lesson,
          scoped.settlement_type_key, scoped.teacher_compensation_rule_key,
          scoped.teacher_compensation_value_minor,
          scoped.reservation_state, scoped.financial_decision,
          scoped.client_financial_baseline,
          scoped.financial_decision_is_plan,
          ${this.lessonParticipantsSql("scoped.id")} as group_participants,
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
        query.localDate ?? null,
        limit,
        actor.userId,
      ],
    );
    const items = result.rows.map((row) => ({
      ...toLessonDto(row),
      scheduledUtcOffsetMinutes:
        row.scheduled_utc_offset_minutes == null
          ? null
          : Number(row.scheduled_utc_offset_minutes),
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
      scheduledUtcOffsetMinutes: number | null;
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
            scheduledUtcOffsetMinutes: item.scheduledUtcOffsetMinutes,
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
            scheduledUtcOffsetMinutes: item.scheduledUtcOffsetMinutes,
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
          to_char(
            timezone(coalesce(b.timezone_name, 'Europe/Moscow'), l.scheduled_at)::date,
            'YYYY-MM-DD'
          ) as day,
          count(*)::text as count,
          array_remove(array_agg(distinct l.room_id), null) as room_ids
        from app.lessons l
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.branches b
          on b.id = coalesce(l.branch_id, g.branch_id, r.branch_id)
         and b.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where l.deleted_at is null
          and l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
          and l.scheduled_at >= $1::timestamptz
          and l.scheduled_at <  $2::timestamptz
          and ($3::uuid is null or coalesce(l.branch_id, g.branch_id, r.branch_id) = $3)
          and (
            ${managerAdminRolesSql(currentActorRoleSql("$4"))}
            or (${currentActorRoleSql("$4")} = 'teacher' and tp.user_id = $4::uuid)
          )
          and ${managerBranchScopeSql({
            roleExpression: currentActorRoleSql("$4"),
            userIdExpression: "$4",
            branchExpression:
              "coalesce(l.branch_id::text, g.branch_id::text, r.branch_id::text)",
          })}
        group by 1
        order by 1
      `,
      [bounds.from, bounds.to, query.branchId ?? null, actor.userId],
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
    // Projection authorization must use the role currently stored in the
    // database. JWTs can outlive a role downgrade; using actor.role here would
    // keep financial columns visible until the stale token expires even though
    // the row predicate below already applies the current role.
    const currentRoleExpression = currentActorRoleSql("$1");
    const canSeeRatesSql = managerAdminRolesSql(currentRoleExpression);
    const canSeePaymentsSql = `(${managerAdminRolesSql(currentRoleExpression)}
      or ${currentRoleExpression} = 'client')`;
    const appliedRateSql = `case when ${canSeeRatesSql} then coalesce(
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
          ) else null::numeric end`;
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
    const clientChargeSnapshotSql = `case when ${canSeePaymentsSql}
      then snapshot.client_charge_type else null::text end`;
    const clientChargeValueSnapshotSql = `case when ${canSeePaymentsSql}
      then snapshot.client_charge_value else null::numeric end`;
    const subscriptionSnapshotSql = `case when ${canSeePaymentsSql}
      then snapshot.subscription_id else null::uuid end`;
    const teacherCompensationSnapshotSql = `case when ${canSeeRatesSql}
      then snapshot.teacher_compensation_type else null::text end`;
    const teacherCompensationValueSnapshotSql = `case when ${canSeeRatesSql}
      then snapshot.teacher_compensation_value else null::numeric end`;
    // Closed enum from the DTO (@IsIn) — never raw user input. desc serves the
    // client «История»: with limit 50 the OLD asc order returned the 50 oldest
    // imported lessons and hid everything recent.
    const sortDir = query.order === "desc" ? "desc" : "asc";
    const paidSql = `case when ${canSeePaymentsSql} then (
            select sum(pay.amount)
            from app.commerce_ordinary_payments pay
            where pay.lesson_id = l.id and pay.deleted_at is null
          ) else null::numeric end`;
    const settlementFailureSql = `case when ${canSeeRatesSql}
      then plan.failure_code else null::text end`;
    const settlementTypeKeySql = `case when ${canSeePaymentsSql}
      then coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'settlementTypeKey' else null::text end`;
    const compensationRuleKeySql = `case when ${canSeeRatesSql}
      then coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'teacherCompensationRuleKey' else null::text end`;
    const compensationValueMinorSql = `case when ${canSeeRatesSql}
      then coalesce(correction.decision, transition.financial_decision, plan.decision) ->> 'teacherCompensationValueMinor' else null::text end`;
    const result = await this.database.query<LessonRow>(
      `
        select l.id, l.version, l.lifecycle_state,
          l.student_id, l.group_id, l.lead_id, l.teacher_id, l.branch_id, l.room_id, l.scheduled_at,
          l.duration_minutes, l.status, l.is_trial, l.notes,
          case when ${canSeeRatesSql} then l.teacher_rate
            else null::numeric end as teacher_rate,
          snapshot.completion_type,
          ${clientChargeSnapshotSql} as client_charge_type,
          ${clientChargeValueSnapshotSql} as client_charge_value,
          ${teacherCompensationSnapshotSql} as teacher_compensation_type,
          ${teacherCompensationValueSnapshotSql} as teacher_compensation_value,
          ${subscriptionSnapshotSql} as subscription_id,
          ${settlementTypeKeySql} as settlement_type_key,
          ${compensationRuleKeySql} as teacher_compensation_rule_key,
          ${compensationValueMinorSql} as teacher_compensation_value_minor,
          (correction.decision is null and transition.financial_decision is null)
            as financial_decision_is_plan,
          case when ${canSeeRatesSql}
            then coalesce(correction.decision, transition.financial_decision, plan.decision)
            else null::jsonb end as financial_decision,
          case when ${canSeeRatesSql}
            then ${this.lessonClientFinancialBaselineSql("l.id")}
            else null::jsonb end as client_financial_baseline,
          case when ${canSeeRatesSql} or ${currentRoleExpression} = 'teacher'
            then ${this.lessonParticipantsSql("l.id")}
            else '[]'::jsonb end as group_participants,
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
          select decision from app.lesson_settlement_corrections
          where lesson_id = l.id order by version desc limit 1
        ) correction on true
        left join lateral (
          select financial_decision from app.lesson_transitions
          where lesson_id = l.id and financial_decision <> '{}'::jsonb
          order by created_at desc, id desc limit 1
        ) transition on true
        left join lateral (
          select lesson_reservation.state
          from app.lesson_reservations lesson_reservation
          where lesson_reservation.lesson_id = l.id
          order by (lesson_reservation.state = 'reserved') desc,
            lesson_reservation.updated_at desc, lesson_reservation.id desc
          limit 1
        ) reservation on true
        where l.deleted_at is null
          and (
            $2::uuid is not null
            or l.lifecycle_state in ('scheduled', 'settlement_pending', 'successfully_completed')
          )
          and ($2::uuid is null or l.id = $2)
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
            ${managerAdminRolesSql(currentActorRoleSql("$1"))}
            or (${currentActorRoleSql("$1")} = 'teacher' and tp.user_id = $1)
            or (${currentActorRoleSql("$1")} = 'client' and ${this.clientLessonAccessSql("$1")})
          )
          and ${managerBranchScopeSql({
            roleExpression: currentActorRoleSql("$1"),
            userIdExpression: "$1",
            branchExpression:
              "coalesce(l.branch_id::text, g.branch_id::text, r.branch_id::text)",
          })}
        order by l.scheduled_at ${sortDir}, l.id ${sortDir}
        limit $8
      `,
      [
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

  /** Upcoming lessons for the already actor-scoped student set. */
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

  private lessonClientFinancialBaselineSql(lessonIdExpression: string): string {
    return `(
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'clientId', selected.client_id, 'chargeType', selected.charge_type,
        'subscriptionId', selected.subscription_id,
        'payerStudentId', selected.payer_student_id,
        'basePriceMinor', selected.base_price_minor,
        'discount', selected.pricing_snapshot->'discount',
        'surcharge', selected.pricing_snapshot->'surcharge',
        'settlementTypeKey', selected.settlement_type_key,
        '_effectiveFact', selected.priority = 0
      )) order by selected.client_id), '[]'::jsonb)
      from (
        select distinct on (source.client_id) source.* from (
          select fact.client_id, fact.charge_type, fact.subscription_id,
            coalesce(fact.payer_student_id,
              case when fact.client_type = 'student' then fact.client_id end) as payer_student_id,
            coalesce(fact.pricing_snapshot->>'basePriceMinor',
              case when fact.charge_type = 'personal_account'
                then round(fact.snapshot_value * 100)::bigint::text end) as base_price_minor,
            fact.pricing_snapshot, fact.settlement_type_key, 0 as priority
          from app.lesson_client_charge_facts_effective fact
          where fact.lesson_id = ${lessonIdExpression}
          union all
          select participant.student_id, participant.charge_type, participant.subscription_id,
            participant.student_id,
            case when participant.charge_type = 'personal_account'
              then round(participant.charge_value * 100)::bigint::text end,
            null::jsonb, null::text, 1
          from app.lesson_snapshot_participants participant
          where participant.lesson_id = ${lessonIdExpression}
          union all
          select snapshot.client_id, snapshot.client_charge_type, snapshot.subscription_id,
            case when snapshot.client_type = 'student' then snapshot.client_id end,
            case when snapshot.client_charge_type = 'personal_account'
              then round(snapshot.client_charge_value * 100)::bigint::text end,
            null::jsonb, null::text, 2
          from app.lesson_snapshots snapshot
          where snapshot.lesson_id = ${lessonIdExpression}
            and snapshot.client_type in ('student', 'lead')
        ) source
        where not exists (
          select 1 from app.lesson_participant_exclusions exclusion
          where exclusion.lesson_id = ${lessonIdExpression}
            and exclusion.student_id = source.client_id
        )
        order by source.client_id, source.priority
      ) selected
    )`;
  }

  private lessonParticipantsSql(lessonIdExpression: string): string {
    return `coalesce((
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
      where participant.lesson_id = ${lessonIdExpression}
        and not exists (
          select 1 from app.lesson_participant_exclusions exclusion
          where exclusion.lesson_id = participant.lesson_id
            and exclusion.student_id = participant.student_id
        )
    ), '[]'::jsonb)`;
  }

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

  private scheduleMatrixBounds(query: ScheduleMatrixQuery) {
    if (query.localDate) {
      const localDay = new Date(`${query.localDate}T00:00:00.000Z`);
      return {
        // IANA zones range from UTC-12 through UTC+14. The SQL local-date
        // predicate below performs the exact branch-zone clipping; this guard
        // only keeps the indexed timestamptz scan bounded.
        from: new Date(localDay.getTime() - 14 * 60 * 60 * 1000).toISOString(),
        to: new Date(
          localDay.getTime() + (24 + 14) * 60 * 60 * 1000,
        ).toISOString(),
      };
    }
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
