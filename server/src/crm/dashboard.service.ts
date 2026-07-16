import { BadRequestException, Injectable } from "@nestjs/common";
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
  debt_students: string | number;
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
  created_at: Date | string;
}

@Injectable()
export class DashboardService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
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
            from app.tasks t
            where t.deleted_at is null and t.status in ('open', 'todo')
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
            from app.payments p, bounds b
            where p.deleted_at is null and p.payment_date >= b.month_start
          ) as revenue_month
      `,
      [],
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
    const result = await this.database.query<ManagerDashboardRow>(
      `
        select
          (
            select coalesce(sum(p.amount), 0)
            from app.payments p
            join app.students s on s.id = p.student_id and s.deleted_at is null
            where p.deleted_at is null
              and p.payment_date >= $1::timestamptz
              and p.payment_date < $2::timestamptz
              and ($3::uuid is null or ${branchIdExpr("s")} = $3::text)
          ) as revenue,
          (
            select coalesce(sum(ep.amount), 0)
            from app.expected_payments ep
            join app.students s on s.id = ep.student_id and s.deleted_at is null
            where ep.status in ('pending', 'open')
              and (ep.due_date is null or ep.due_date < $2::date)
              and ($3::uuid is null or ${branchIdExpr("s")} = $3::text)
          ) as expected_payments,
          (
            -- Live balance (paid − lesson costs + adjustments), mirroring
            -- FinanceService.listStudentBalances. The app.student_balances
            -- table is written by nothing, so counting it always showed
            -- «Должники: 0» while the drill-down listed real debtors.
            select count(*)
            from (
              select st.id,
                coalesce(pay.total_paid, 0) - coalesce(cost.total_cost, 0)
                  + coalesce(adj.total_adjustments, 0) as balance
              from app.students st
              left join (
                select p.student_id, sum(p.amount) as total_paid
                from app.payments p
                where p.deleted_at is null
                group by p.student_id
              ) pay on pay.student_id = st.id
              left join (
                select coalesce(l.student_id, lp.student_id) as student_id,
                  sum(
                    coalesce(
                      g.price_per_lesson,
                      case
                        when s2.custom_data->>'individualPrice' ~ '^[0-9]+(\\.[0-9]+)?$'
                          then (s2.custom_data->>'individualPrice')::numeric
                        when s2.custom_data->>'individual_price' ~ '^[0-9]+(\\.[0-9]+)?$'
                          then (s2.custom_data->>'individual_price')::numeric
                        else null
                      end,
                      0
                    )
                  ) as total_cost
                from app.lessons l
                left join app.lesson_participation lp on lp.lesson_id = l.id
                join app.students s2 on s2.id = coalesce(l.student_id, lp.student_id)
                left join app.groups g on g.id = l.group_id and g.deleted_at is null
                where l.deleted_at is null
                  and l.status in ('completed', 'done')
                  and coalesce(l.student_id, lp.student_id) is not null
                group by coalesce(l.student_id, lp.student_id)
              ) cost on cost.student_id = st.id
              left join (
                select adj.student_id, sum(adj.amount) as total_adjustments
                from app.account_adjustments adj
                where adj.deleted_at is null
                group by adj.student_id
              ) adj on adj.student_id = st.id
              where st.deleted_at is null
                and ($3::uuid is null or ${branchIdExpr("st")} = $3::text)
            ) b
            where b.balance < 0
          ) as debt_students,
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
            from app.tasks t
            where t.deleted_at is null
              and t.status in ('open', 'in_progress')
              and (t.due_at is null or (t.due_at >= $1::timestamptz and t.due_at < $2::timestamptz))
          ) as open_tasks,
          (
            select count(*)
            from app.tasks t
            where t.deleted_at is null
              and t.status in ('open', 'in_progress')
              and t.due_at < now()
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
      [bounds.from, bounds.to, query.branchId ?? null],
    );
    const row = result.rows[0];
    return {
      from: bounds.from,
      to: bounds.to,
      branchId: query.branchId ?? null,
      kpis: {
        // KVA-239: общешкольные денежные суммы видят только director/system_admin.
        revenue: this.policy.canReadSchoolFinance(actor)
          ? this.toNumericStat(row?.revenue)
          : null,
        expectedPayments: this.policy.canReadSchoolFinance(actor)
          ? this.toNumericStat(row?.expected_payments)
          : null,
        debtStudents: this.toNumericStat(row?.debt_students),
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
        revenue: "/crm/reports/finance",
        expectedPayments: "/crm/expected-payments",
        debtStudents: "/crm/student-balances?debtOnly=true",
        newLeads: "/crm/leads/board",
        tasks: "/crm/tasks",
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
          from app.payments p
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
        select ae.id, ae.actor_user_id, u.email as actor_email,
          u.role::text as actor_app_role, sm.role as actor_staff_role,
          sm.position as actor_position, p.first_name as actor_first_name,
          p.last_name as actor_last_name,
          coalesce(
            jsonb_agg(
              distinct jsonb_build_object('id', b.id, 'name', b.name)
            ) filter (where b.id is not null),
            '[]'::jsonb
          ) as actor_branches,
          ae.action, ae.entity_type, ae.entity_id, ae.metadata, ae.created_at
        from app.audit_events ae
        left join app.users u on u.id = ae.actor_user_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        left join app.staff_members sm on sm.profile_id = p.id and sm.deleted_at is null
        left join app.staff_branch_assignments sba
          on sba.staff_member_id = sm.id and sba.deleted_at is null
        left join app.branches b on b.id = sba.branch_id and b.deleted_at is null
        where (
            $1::text is null
            or lower(
              coalesce(ae.action, '') || ' ' ||
              coalesce(ae.entity_type, '') || ' ' ||
              coalesce(ae.entity_id, '') || ' ' ||
              coalesce(ae.metadata::text, '') || ' ' ||
              coalesce(p.first_name, '') || ' ' ||
              coalesce(p.last_name, '') || ' ' ||
              coalesce(u.email, '')
            ) like lower('%' || $1 || '%')
          )
          and ($2::uuid is null or ae.actor_user_id = $2)
          and ($3::text is null or ae.entity_type = $3)
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
        group by ae.id, u.id, p.id, sm.id
        order by ae.created_at desc, ae.id desc
        limit $10
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

    return { items: result.rows.map((row) => this.toActivityLogDto(row)) };
  }

  private toActivityLogDto(row: ActivityLogRow) {
    const metadata = row.metadata ?? {};
    const metadataString = (key: string) => {
      const value = metadata[key];
      return typeof value === "string" && value.trim().length > 0
        ? value
        : null;
    };
    const actorNameText = [row.actor_first_name, row.actor_last_name]
      .filter(Boolean)
      .join(" ")
      .trim();
    const actorName = actorNameText.length > 0 ? actorNameText : null;
    return {
      id: row.id,
      actorUserId: row.actor_user_id,
      actorName,
      actorEmail: row.actor_email,
      actorRole: row.actor_app_role,
      actorStaffRole: row.actor_staff_role,
      actorPosition: row.actor_position,
      actorBranches: row.actor_branches ?? [],
      action: row.action,
      entityType: row.entity_type,
      entityId: row.entity_id,
      historyType:
        metadataString("historyType") ??
        metadataString("history_type") ??
        metadataString("type") ??
        row.action,
      description:
        metadataString("description") ??
        metadataString("body") ??
        metadataString("comment") ??
        metadataString("notes") ??
        metadataString("reason"),
      branchId:
        metadataString("branchId") ?? metadataString("branch_id") ?? null,
      metadata,
      createdAt: row.created_at,
    };
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
