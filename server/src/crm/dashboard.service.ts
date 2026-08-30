import { BadRequestException, Injectable } from "@nestjs/common";
import { AuditPresentationService } from "../audit/audit-presentation.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { branchIdExpr } from "./branch-scope";
import { CrmPolicy } from "./crm.policy";
import { ActivityLogQuery } from "./dto/activity-log.query";
import { ManagerDashboardQuery } from "./dto/manager-dashboard.query";
import { ReportQuery } from "./dto/report.query";

interface OverviewRow {
  students_count: string | number;
  teachers_count: string | number;
  branches_count: string | number;
  today_lessons_count: string | number;
  month_completed_lessons_count: string | number;
  open_tasks_count: string | number;
  new_leads_count: string | number;
  revenue_month: string | number | null;
}

interface ManagerDashboardRow {
  revenue: string | number | null;
  expected_payments: string | number | null;
  debt_students: string | number | null;
  active_students: string | number;
  new_leads: string | number;
  open_tasks: string | number;
  overdue_tasks: string | number;
  trial_lessons: string | number;
  schedule_issues: string | number;
  room_load_lessons: string | number;
  staff_activity: string | number;
}

interface FinanceReportMonthlyRow {
  month_start: Date | string;
  lessons_count: string | number;
  completed_lessons_count: string | number;
  new_students_count: string | number;
  revenue: string | number | null;
  expenses: string | number | null;
}

interface FinanceReportTeacherRow {
  teacher_id: string;
  teacher_name: string | null;
  completed_lessons_count: string | number;
  revenue: string | number | null;
}

interface FinanceReportRoomRow {
  room_id: string;
  room_name: string | null;
  lessons_count: string | number;
}

interface ActivityLogRow {
  id: string;
  actor_user_id: string | null;
  actor_email: string | null;
  actor_app_role: string | null;
  actor_staff_role: string | null;
  actor_position: string | null;
  actor_first_name: string | null;
  actor_last_name: string | null;
  actor_branches: Array<{ id: string; name: string }> | null;
  action: string;
  entity_type: string;
  entity_id: string | null;
  metadata: Record<string, unknown> | null;
  before_ref: Record<string, unknown> | null;
  after_ref: Record<string, unknown> | null;
  reason: string | null;
  reason_text: string | null;
  target_display_name: string | null;
  created_at: Date | string;
}

@Injectable()
export class DashboardService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly presenter: AuditPresentationService,
  ) {}

  async getOverview(actor: ActorContext) {
    this.policy.assertManagerOnly(actor);
    const result = await this.database.query<OverviewRow>(
      `
        with bounds as (
          select
            date_trunc('day', timezone('Europe/Moscow', now())) at time zone 'Europe/Moscow' as today_start,
            (date_trunc('day', timezone('Europe/Moscow', now())) + interval '1 day') at time zone 'Europe/Moscow' as tomorrow_start,
            date_trunc('month', timezone('Europe/Moscow', now())) at time zone 'Europe/Moscow' as month_start
        )
        select
          (select count(*) from app.students where deleted_at is null) as students_count,
          (select count(*) from app.teachers where deleted_at is null) as teachers_count,
          (select count(*) from app.branches where deleted_at is null) as branches_count,
          (
            select count(*)
            from app.lessons l, bounds b
            where l.deleted_at is null
              and l.scheduled_at >= b.today_start
              and l.scheduled_at < b.tomorrow_start
          ) as today_lessons_count,
          (
            select count(*)
            from app.lessons l, bounds b
            where l.deleted_at is null
              and l.status = 'completed'
              and l.scheduled_at >= b.month_start
          ) as month_completed_lessons_count,
          (
            select count(*)
            from app.shared_tasks t
            where t.deleted_at is null and t.state = 'open'
              and exists (
                select 1 from app.shared_task_visibility visibility
                where visibility.task_id = t.id and visibility.user_id = $1
              )
          ) as open_tasks_count,
          (
            select count(*)
            from app.leads l
            left join app.lead_statuses ls on ls.id = l.status_id
            where l.deleted_at is null
              and (
                l.status_id is null
                or lower(coalesce(ls.name, '')) in ('new', 'новый')
              )
          ) as new_leads_count,
          (
            select coalesce(sum(p.amount), 0)
            from app.commerce_ordinary_payments p, bounds b
            where p.deleted_at is null and p.payment_date >= b.month_start
          ) as revenue_month
      `,
      [actor.userId],
    );
    const row = result.rows[0];
    return {
      students: this.toNumericStat(row?.students_count),
      teachers: this.toNumericStat(row?.teachers_count),
      branches: this.toNumericStat(row?.branches_count),
      todayLessons: this.toNumericStat(row?.today_lessons_count),
      monthCompletedLessons: this.toNumericStat(
        row?.month_completed_lessons_count,
      ),
      openTasks: this.toNumericStat(row?.open_tasks_count),
      newLeads: this.toNumericStat(row?.new_leads_count),
      // KVA-239: общешкольная выручка скрыта от ролей без доступа к
      // общешкольным финансам (manager/admin видят null).
      revenueMonth: this.policy.canReadSchoolFinance(actor)
        ? this.toNumericStat(row?.revenue_month)
        : null,
    };
  }

  async getManagerDashboard(actor: ActorContext, query: ManagerDashboardQuery) {
    this.policy.assertManagerOnly(actor);
    const bounds = this.dashboardBounds(query);
    const canReadSchoolFinance = this.policy.canReadSchoolFinance(actor);
    const result = await this.database.query<ManagerDashboardRow>(
      `
        select
          case when $5::boolean then (
            select coalesce(sum(p.amount), 0)
            from app.commerce_ordinary_payments p
            join app.students s on s.id = p.student_id and s.deleted_at is null
            where p.deleted_at is null
              and p.payment_date >= $1::timestamptz
              and p.payment_date < $2::timestamptz
              and ($3::uuid is null or ${branchIdExpr("s")} = $3::text)
          ) else null end as revenue,
          case when $5::boolean then (
            select coalesce(sum(receivable.amount_minor), 0)::numeric / 100
            from app.commerce_receivable_schedule_projection receivable
            join app.students s
              on s.id = receivable.student_id and s.deleted_at is null
            where receivable.due_at < $2::timestamptz
              and ($3::uuid is null or ${branchIdExpr("s")} = $3::text)
          ) else null end as expected_payments,
          case when $5::boolean then (
            select count(distinct projection.student_id)
            from app.commerce_student_account_projection projection
            join app.students st
              on st.id = projection.student_id and st.deleted_at is null
            where projection.debt_minor > 0
              and ($3::uuid is null or ${branchIdExpr("st")} = $3::text)
          ) else null end as debt_students,
          (
            select count(*)
            from app.students s
            where s.deleted_at is null
              and s.status = 'active'
              and ($3::uuid is null or ${branchIdExpr("s")} = $3::text)
          ) as active_students,
          (
            select count(*)
            from app.leads l
            where l.deleted_at is null
              and l.created_at >= $1::timestamptz
              and l.created_at < $2::timestamptz
              and ($3::uuid is null or ${branchIdExpr("l")} = $3::text)
          ) as new_leads,
          (
            select count(*)
            from app.shared_tasks t
            where t.deleted_at is null
              and t.state = 'open'
              and exists (
                select 1 from app.shared_task_visibility visibility
                where visibility.task_id = t.id and visibility.user_id = $4
              )
          ) as open_tasks,
          (
            select count(*)
            from app.shared_tasks t
            where t.deleted_at is null
              and t.state = 'open'
              and t.start_at is not null
              and t.start_at < case
                when t.all_day then
                  date_trunc('day', timezone('Europe/Moscow', now()))
                    at time zone 'Europe/Moscow'
                else now()
              end
              and exists (
                select 1 from app.shared_task_visibility visibility
                where visibility.task_id = t.id and visibility.user_id = $4
              )
          ) as overdue_tasks,
          (
            select count(*)
            from app.lessons l
            where l.deleted_at is null
              and l.is_trial = true
              and l.scheduled_at >= $1::timestamptz
              and l.scheduled_at < $2::timestamptz
              and ($3::uuid is null or l.branch_id = $3)
          ) as trial_lessons,
          (
            select count(*)
            from app.lessons l
            left join app.rooms r on r.id = l.room_id and r.deleted_at is null
            where l.deleted_at is null
              and l.scheduled_at >= $1::timestamptz
              and l.scheduled_at < $2::timestamptz
              and ($3::uuid is null or l.branch_id = $3 or r.branch_id = $3)
              and (
                l.teacher_id is null
                or (l.room_id is not null and l.branch_id is not null and r.branch_id is not null and l.branch_id <> r.branch_id)
                or (l.room_id is not null and exists (
                  select 1
                  from app.lessons other_room
                  where other_room.deleted_at is null
                    and other_room.status <> 'cancelled'
                    and other_room.id <> l.id
                    and other_room.room_id = l.room_id
                    -- Bound the conflict candidate to the dashboard window so the
                    -- (room_id, scheduled_at) index drives the scan instead of a
                    -- per-lesson seq scan over all 47k lessons (6.3s -> ~40ms).
                    and other_room.scheduled_at >= $1::timestamptz
                    and other_room.scheduled_at < $2::timestamptz
                    -- Lessons of the SAME group share a room legitimately (one
                    -- group class = many participant rows). Only a different
                    -- group (or an individual lesson) is a real double-booking.
                    and (l.group_id is null or other_room.group_id is null
                         or other_room.group_id <> l.group_id)
                    and other_room.scheduled_at < l.scheduled_at + l.duration_minutes * interval '1 minute'
                    and other_room.scheduled_at + other_room.duration_minutes * interval '1 minute' > l.scheduled_at
                ))
              )
          ) as schedule_issues,
          (
            select count(*)
            from app.lessons l
            where l.deleted_at is null
              and l.room_id is not null
              and l.scheduled_at >= $1::timestamptz
              and l.scheduled_at < $2::timestamptz
              and ($3::uuid is null or l.branch_id = $3)
          ) as room_load_lessons,
          (
            select count(*)
            from app.audit_events audit
            where audit.created_at >= $1::timestamptz
              and audit.created_at < $2::timestamptz
              and audit.action like 'crm.%'
          ) as staff_activity
      `,
      [
        bounds.from,
        bounds.to,
        query.branchId ?? null,
        actor.userId,
        canReadSchoolFinance,
      ],
    );
    const row = result.rows[0];
    return {
      from: bounds.from,
      to: bounds.to,
      branchId: query.branchId ?? null,
      kpis: {
        // KVA-239: общешкольные денежные суммы видят только director/system_admin.
        revenue: canReadSchoolFinance
          ? this.toNumericStat(row?.revenue)
          : null,
        expectedPayments: canReadSchoolFinance
          ? this.toNumericStat(row?.expected_payments)
          : null,
        debtStudents: canReadSchoolFinance
          ? this.toNumericStat(row?.debt_students)
          : null,
        activeStudents: this.toNumericStat(row?.active_students),
        newLeads: this.toNumericStat(row?.new_leads),
        openTasks: this.toNumericStat(row?.open_tasks),
        overdueTasks: this.toNumericStat(row?.overdue_tasks),
        trialLessons: this.toNumericStat(row?.trial_lessons),
        scheduleIssues: this.toNumericStat(row?.schedule_issues),
        roomLoadLessons: this.toNumericStat(row?.room_load_lessons),
        staffActivity: this.toNumericStat(row?.staff_activity),
      },
      sources: {
        ...(canReadSchoolFinance
          ? {
              revenue: "/crm/reports/finance",
              expectedPayments: "/crm/expected-payments",
              debtStudents: "/crm/student-balances?debtOnly=true",
            }
          : {}),
        newLeads: "/crm/leads/board",
        tasks: "/crm/shared-tasks?state=open",
        schedule: "/crm/schedule/matrix",
        activity: "/crm/activity",
      },
    };
  }

  async getFinanceReport(actor: ActorContext, query: ReportQuery) {
    // KVA-239: общешкольный финансовый отчёт — только director/system_admin.
    this.policy.assertCanReadSchoolFinance(actor);
    const bounds = this.reportBounds(query);
    const monthly = await this.database.query<FinanceReportMonthlyRow>(
      `
        with months as (
          select generate_series(
            date_trunc('month', $1::timestamptz),
            date_trunc('month', $2::timestamptz),
            interval '1 month'
          ) as month_start
        ),
        lesson_stats as (
          select
            date_trunc('month', l.scheduled_at) as month_start,
            count(*) as lessons_count,
            count(*) filter (where l.status in ('completed', 'done')) as completed_lessons_count
          from app.lessons l
          where l.deleted_at is null
            and l.scheduled_at >= $1::timestamptz
            and l.scheduled_at < $2::timestamptz
          group by date_trunc('month', l.scheduled_at)
        ),
        payment_stats as (
          select
            date_trunc('month', p.payment_date) as month_start,
            coalesce(sum(p.amount), 0) as revenue
          from app.commerce_ordinary_payments p
          where p.deleted_at is null
            and p.payment_date >= $1::timestamptz
            and p.payment_date < $2::timestamptz
          group by date_trunc('month', p.payment_date)
        ),
        expense_stats as (
          select
            date_trunc('month', e.created_at) as month_start,
            coalesce(sum(e.amount), 0) as expenses
          from app.expenses e
          where e.deleted_at is null
            and e.created_at >= $1::timestamptz
            and e.created_at < $2::timestamptz
          group by date_trunc('month', e.created_at)
        ),
        student_stats as (
          select
            date_trunc('month', s.created_at) as month_start,
            count(*) as new_students_count
          from app.students s
          where s.deleted_at is null
            and s.created_at >= $1::timestamptz
            and s.created_at < $2::timestamptz
          group by date_trunc('month', s.created_at)
        )
        select
          m.month_start,
          coalesce(l.lessons_count, 0) as lessons_count,
          coalesce(l.completed_lessons_count, 0) as completed_lessons_count,
          coalesce(s.new_students_count, 0) as new_students_count,
          coalesce(p.revenue, 0) as revenue,
          coalesce(e.expenses, 0) as expenses
        from months m
        left join lesson_stats l on l.month_start = m.month_start
        left join payment_stats p on p.month_start = m.month_start
        left join expense_stats e on e.month_start = m.month_start
        left join student_stats s on s.month_start = m.month_start
        order by m.month_start asc
      `,
      [bounds.from, bounds.to],
    );
    const teachers = await this.database.query<FinanceReportTeacherRow>(
      `
        select
          l.teacher_id,
          nullif(trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')), '') as teacher_name,
          count(*) as completed_lessons_count,
          coalesce(sum(
            coalesce(
              g.price_per_lesson,
              case
                when s.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                  then (s.custom_data->>'individualPrice')::numeric
                when s.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                  then (s.custom_data->>'individual_price')::numeric
                else null
              end,
              0
            )
          ), 0) as revenue
        from app.lessons l
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        where l.deleted_at is null
          and l.teacher_id is not null
          and l.status in ('completed', 'done')
          and l.scheduled_at >= $1::timestamptz
          and l.scheduled_at < $2::timestamptz
        group by l.teacher_id, tp.first_name, tp.last_name
        order by revenue desc, completed_lessons_count desc, teacher_name asc
      `,
      [bounds.from, bounds.to],
    );
    const rooms = await this.database.query<FinanceReportRoomRow>(
      `
        select
          l.room_id,
          r.name as room_name,
          count(*) as lessons_count
        from app.lessons l
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        where l.deleted_at is null
          and l.room_id is not null
          and l.scheduled_at >= $1::timestamptz
          and l.scheduled_at < $2::timestamptz
        group by l.room_id, r.name
        order by lessons_count desc, room_name asc
      `,
      [bounds.from, bounds.to],
    );
    const monthlyItems = monthly.rows.map((row) => ({
      monthStart: row.month_start,
      lessons: this.toNumericStat(row.lessons_count),
      completedLessons: this.toNumericStat(row.completed_lessons_count),
      newStudents: this.toNumericStat(row.new_students_count),
      revenue: this.toNumericStat(row.revenue),
      expenses: this.toNumericStat(row.expenses),
    }));
    const totalLessons = monthlyItems.reduce(
      (sum, row) => sum + row.lessons,
      0,
    );
    const totalCompleted = monthlyItems.reduce(
      (sum, row) => sum + row.completedLessons,
      0,
    );
    const totalRevenue = monthlyItems.reduce(
      (sum, row) => sum + row.revenue,
      0,
    );

    return {
      from: bounds.from,
      to: bounds.to,
      summary: {
        attendance:
          totalLessons > 0 ? (totalCompleted / totalLessons) * 100 : 0,
        revenue: totalRevenue,
        totalLessons,
        totalCompleted,
      },
      monthly: monthlyItems,
      teachers: teachers.rows.map((row) => ({
        teacherId: row.teacher_id,
        teacherName: row.teacher_name || "Без имени",
        completedLessons: this.toNumericStat(row.completed_lessons_count),
        revenue: this.toNumericStat(row.revenue),
      })),
      rooms: rooms.rows.map((row) => ({
        roomId: row.room_id,
        roomName: row.room_name || "Без аудитории",
        lessons: this.toNumericStat(row.lessons_count),
      })),
    };
  }

  async listActivityLog(actor: ActorContext, query: ActivityLogQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<ActivityLogRow>(
      `
        with normalized_events as (
          select audit.*,
            case audit.entity_type
              when 'crm:student' then 'student'
              when 'crm:lead' then 'lead'
              when 'crm:comment' then 'comment'
              when 'shared_task' then 'task'
              else audit.entity_type
            end as presentation_entity_type,
            case
              when audit.entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                then audit.entity_id::uuid
              else null
            end as target_entity_uuid
          from app.audit_events audit
        ),
        candidate_events as materialized (
          select ae.id, ae.actor_user_id, u.email as actor_email,
            u.role::text as actor_app_role, sm.role as actor_staff_role,
            sm.position as actor_position, p.first_name as actor_first_name,
            p.last_name as actor_last_name,
            coalesce(actor_branches.branches, '[]'::jsonb) as actor_branches,
            ae.action, ae.entity_type, ae.presentation_entity_type, ae.entity_id,
            ae.target_entity_uuid, ae.metadata, ae.before_ref, ae.after_ref,
            ae.reason, ae.reason_text, ae.created_at
          from normalized_events ae
          left join app.users u on u.id = ae.actor_user_id and u.deleted_at is null
          left join app.profiles p on p.user_id = u.id and p.deleted_at is null
          left join app.staff_members sm on sm.profile_id = p.id and sm.deleted_at is null
          left join lateral (
            select jsonb_agg(distinct jsonb_build_object('id', b.id, 'name', b.name)) as branches
            from app.staff_branch_assignments sba
            join app.branches b on b.id = sba.branch_id and b.deleted_at is null
            where sba.staff_member_id = sm.id and sba.deleted_at is null
          ) actor_branches on true
          where (
              $1::text is null
              or lower(
                coalesce(ae.action, '') || ' ' ||
                coalesce(ae.entity_type, '') || ' ' ||
                coalesce(ae.presentation_entity_type, '') || ' ' ||
                coalesce(ae.entity_id, '') || ' ' ||
                coalesce(ae.metadata::text, '') || ' ' ||
                coalesce(p.first_name, '') || ' ' ||
                coalesce(p.last_name, '') || ' ' ||
                coalesce(u.email, '')
              ) like lower('%' || $1 || '%')
            )
            and ($2::uuid is null or ae.actor_user_id = $2)
            and (
              $3::text is null
              or ae.presentation_entity_type = $3
              or ae.entity_type = $3
            )
            and ($4::text is null or ae.entity_id = $4)
            and (
              $5::uuid is null
              or ae.metadata->>'branchId' = $5::text
              or ae.metadata->>'branch_id' = $5::text
              or exists (
                select 1
                from app.staff_branch_assignments branch_scope
                where branch_scope.staff_member_id = sm.id
                  and branch_scope.branch_id = $5
                  and branch_scope.deleted_at is null
              )
            )
            and (
              $6::text is null
              or u.role::text = $6
              or sm.role = $6
            )
            and (
              $7::text is null
              or ae.action = $7
              or ae.action like $7 || '.%'
              or ae.metadata->>'historyType' = $7
              or ae.metadata->>'history_type' = $7
              or ae.metadata->>'type' = $7
            )
            and ($8::timestamptz is null or ae.created_at >= $8)
            and ($9::timestamptz is null or ae.created_at < $9)
            and ae.action not like 'auth.%'
            and ae.action not ilike '%refresh%'
            and ae.action not ilike '%session%'
            and ae.presentation_entity_type not in ('session', 'refresh_session', 'auth_session')
            and coalesce(
              ae.metadata->>'historyType',
              ae.metadata->>'history_type',
              ae.metadata->>'type',
              ''
            ) not in ('session', 'refresh_session', 'auth_session')
          order by ae.created_at desc, ae.id desc
          limit $10
        )
        select ae.id, ae.actor_user_id, ae.actor_email,
          ae.actor_app_role, ae.actor_staff_role, ae.actor_position,
          ae.actor_first_name, ae.actor_last_name, ae.actor_branches,
          ae.action, ae.presentation_entity_type as entity_type, ae.entity_id, ae.metadata,
          ae.before_ref, ae.after_ref, ae.reason, ae.reason_text,
          case ae.presentation_entity_type
            when 'student' then nullif(btrim(concat_ws(' ', student_profile.first_name, student_profile.last_name)), '')
            when 'lead' then nullif(btrim(concat_ws(' ', target_lead.first_name, target_lead.last_name)), '')
            when 'lesson' then to_char(target_lesson.scheduled_at at time zone 'Europe/Moscow', 'DD.MM.YYYY HH24:MI')
            when 'staff' then nullif(btrim(concat_ws(' ', staff_profile.first_name, staff_profile.last_name)), '')
            when 'teacher' then nullif(btrim(concat_ws(' ', teacher_profile.first_name, teacher_profile.last_name)), '')
            when 'profile' then nullif(btrim(concat_ws(' ', target_profile.first_name, target_profile.last_name)), '')
            when 'group' then target_group.name
            when 'task' then shared_task.title
            when 'payment' then concat_ws(' ', target_payment.amount::text, target_payment.currency)
            when 'subscription' then concat('Абонемент на ', target_subscription.lessons_total, ' занятий')
            when 'homework' then target_homework.title
            else null
          end as target_display_name,
          ae.created_at
        from candidate_events ae
        left join lateral (
          select target_student_record.profile_id
          from app.students target_student_record
          where ae.presentation_entity_type = 'student'
            and target_student_record.id = ae.target_entity_uuid
            and target_student_record.deleted_at is null
          limit 1
        ) target_student on true
        left join app.profiles student_profile
          on student_profile.id = target_student.profile_id and student_profile.deleted_at is null
        left join app.leads target_lead
          on ae.presentation_entity_type = 'lead' and target_lead.id = ae.target_entity_uuid and target_lead.deleted_at is null
        left join app.lessons target_lesson
          on ae.presentation_entity_type = 'lesson' and target_lesson.id = ae.target_entity_uuid and target_lesson.deleted_at is null
        left join app.staff_members target_staff
          on ae.presentation_entity_type = 'staff' and target_staff.id = ae.target_entity_uuid and target_staff.deleted_at is null
        left join app.profiles staff_profile
          on staff_profile.id = target_staff.profile_id and staff_profile.deleted_at is null
        left join app.teachers target_teacher
          on ae.presentation_entity_type = 'teacher' and target_teacher.id = ae.target_entity_uuid and target_teacher.deleted_at is null
        left join app.profiles teacher_profile
          on teacher_profile.id = target_teacher.profile_id and teacher_profile.deleted_at is null
        left join app.profiles target_profile
          on ae.presentation_entity_type = 'profile' and target_profile.id = ae.target_entity_uuid and target_profile.deleted_at is null
        left join app.groups target_group
          on ae.presentation_entity_type = 'group' and target_group.id = ae.target_entity_uuid and target_group.deleted_at is null
        left join app.shared_tasks shared_task
          on ae.presentation_entity_type = 'task' and shared_task.id = ae.target_entity_uuid and shared_task.deleted_at is null
        left join app.payments target_payment
          on ae.presentation_entity_type = 'payment' and target_payment.id = ae.target_entity_uuid and target_payment.deleted_at is null
        left join app.subscriptions target_subscription
          on ae.presentation_entity_type = 'subscription' and target_subscription.id = ae.target_entity_uuid
        left join app.lesson_homeworks target_homework
          on ae.presentation_entity_type = 'homework' and target_homework.id = ae.target_entity_uuid and target_homework.deleted_at is null
        order by ae.created_at desc, ae.id desc
      `,
      [
        q || null,
        query.actorUserId ?? null,
        query.entityType ?? null,
        query.entityId ?? null,
        query.branchId ?? null,
        query.role ?? null,
        query.historyType ?? null,
        query.from ?? null,
        query.to ?? null,
        limit,
      ],
    );

    return {
      items: result.rows.map((row) =>
        this.presenter.present({
          id: row.id,
          actionKey: row.action,
          actor: {
            id: row.actor_user_id,
            name: [row.actor_first_name, row.actor_last_name]
              .filter(Boolean)
              .join(" "),
            role: row.actor_app_role ?? row.actor_staff_role,
          },
          target: {
            type: this.normalizedActivityEntityType(row.entity_type),
            id: row.entity_id,
            displayName: this.normalizedActivityEntityType(row.entity_type) === 'comment'
              ? null
              : row.target_display_name,
          },
          metadata: row.metadata,
          beforeRef: row.before_ref,
          afterRef: row.after_ref,
          reason: row.reason,
          reasonText: row.reason_text,
          occurredAt: row.created_at,
        }),
      ),
    };
  }

  private normalizedActivityEntityType(entityType: string): string {
    switch (entityType) {
      case "crm:student":
        return "student";
      case "crm:lead":
        return "lead";
      case "crm:comment":
        return "comment";
      case "shared_task":
        return "task";
      default:
        return entityType;
    }
  }

  private dashboardBounds(query: ManagerDashboardQuery) {
    const now = new Date();
    const monthStart = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
    );
    const from = query.from ? new Date(query.from) : monthStart;
    const to = query.to
      ? new Date(query.to)
      : new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth() + 1, 1));
    return {
      from: from.toISOString(),
      to: to.toISOString(),
    };
  }

  private reportBounds(query: ReportQuery) {
    const now = new Date();
    const defaultFrom = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 5, 1, 0, 0, 0, 0),
    );
    const from = query.from ? new Date(query.from) : defaultFrom;
    const to = query.to ? new Date(query.to) : now;
    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) {
      throw new BadRequestException("Некорректный период отчёта.");
    }
    if (from >= to) {
      throw new BadRequestException("Начало периода должно быть раньше конца.");
    }
    return {
      from: from.toISOString(),
      to: to.toISOString(),
    };
  }

  // ponytail: toNumericStat copied from crm.service (38 retained uses there).
  // Pure 3-line coercion — copy over shared-util churn.
  private toNumericStat(value: string | number | null | undefined): number {
    if (value === null || value === undefined) return 0;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }
}
