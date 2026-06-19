import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isAdminRole,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { ActivityLogQuery } from "./dto/activity-log.query";
import { CommentQuery } from "./dto/comment.query";
import { UpdateBranchDto } from "./dto/update-branch.dto";
import { CreateCommentDto } from "./dto/create-comment.dto";
import { DuplicateCandidatesQuery } from "./dto/duplicate-candidates.query";
import { DuplicateDecisionDto } from "./dto/duplicate-decision.dto";
import { CreatePaymentDto } from "./dto/create-payment.dto";
import { CreateStaffDto } from "./dto/create-staff.dto";
import { CreateStudentDto } from "./dto/create-student.dto";
import { CreateTeacherDto } from "./dto/create-teacher.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { LessonQuery } from "./dto/lesson.query";
import { ManagerDashboardQuery } from "./dto/manager-dashboard.query";
import { PaymentQuery } from "./dto/payment.query";
import { ReportQuery } from "./dto/report.query";
import { RoomAvailabilityQuery } from "./dto/room-availability.query";
import { ScheduleMatrixQuery } from "./dto/schedule-matrix.query";
import { StaffListQuery } from "./dto/staff-list.query";
import { StudentBalanceQuery } from "./dto/student-balance.query";
import { StudentSearchQuery } from "./dto/student-search.query";
import { TaskBoardQuery } from "./dto/task-board.query";
import { TimelineQuery } from "./dto/timeline.query";
import { TeacherListQuery } from "./dto/teacher-list.query";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { UpdateStaffDto } from "./dto/update-staff.dto";
import { UpdateTeacherDto } from "./dto/update-teacher.dto";
import { UpsertAttendanceDto } from "./dto/upsert-attendance.dto";
import { UpsertGroupDto } from "./dto/upsert-group.dto";
import { UpsertLeadDto } from "./dto/upsert-lead.dto";
import { UpsertLeadStatusDto } from "./dto/upsert-lead-status.dto";
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";
import { UpsertRoomDto } from "./dto/upsert-room.dto";
import { UpsertTaskDto } from "./dto/upsert-task.dto";
import { CrmPolicy } from "./crm.policy";
import { HolliHopMetadataService } from "./hollihop-metadata.service";
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

interface StudentRow {
  id: string;
  lead_id: string | null;
  status: string;
  custom_data: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  teacher_user_ids: string[] | null;
  created_at: Date | string;
}

interface StudentSearchRow extends StudentRow {
  branch_id: string | null;
  branch_name: string | null;
  groups_count: string | number;
  open_tasks_count: string | number;
  lessons_count: string | number;
  payments_total: string | number | null;
  linked_user_id: string | null;
  linked_user_email: string | null;
  is_app_account: boolean | null;
}

interface TeacherRow {
  id: string;
  status: string;
  specialization: string | null;
  custom_data?: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  app_role?: string | null;
  is_app_account?: boolean | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  branches?: Array<{ id: string; name: string }> | null;
  students_count?: string | number | null;
  lessons_count?: string | number | null;
  rating?: string | number | null;
  created_at?: Date | string;
}

interface StaffRow {
  id: string;
  role: string;
  position: string | null;
  status: string;
  custom_data: Record<string, unknown> | null;
  profile_id: string | null;
  profile_user_id: string | null;
  app_role: string | null;
  is_app_account: boolean | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  branches: Array<{ id: string; name: string }> | null;
  created_at: Date | string;
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

interface LessonRow {
  id: string;
  student_id: string | null;
  group_id: string | null;
  lead_id: string | null;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  scheduled_at: Date | string;
  duration_minutes: number;
  status: string;
  is_trial: boolean;
  notes: string | null;
  student_user_id: string | null;
  teacher_user_id: string | null;
  student_name: string | null;
  teacher_name: string | null;
  branch_name: string | null;
  room_name: string | null;
  group_name: string | null;
  group_price_per_lesson: string | null;
}

interface ScheduleLessonRow extends LessonRow {
  conflict_types: string[] | null;
}

interface LessonAccessRow {
  id: string;
  student_id: string | null;
  group_id: string | null;
  teacher_user_id: string | null;
}

interface AttendanceStudentRow {
  student_id: string;
  first_name: string | null;
  last_name: string | null;
}

interface AttendanceParticipationRow {
  student_id: string;
  status: string;
  pass_reason: string | null;
}

interface TaskRow {
  id: string;
  entity_type: string;
  entity_id: string;
  assigned_to: string | null;
  assigned_first_name?: string | null;
  assigned_last_name?: string | null;
  creator_first_name?: string | null;
  creator_last_name?: string | null;
  entity_first_name?: string | null;
  entity_last_name?: string | null;
  entity_name?: string | null;
  branch_id?: string | null;
  branch_name?: string | null;
  title: string;
  description: string | null;
  status: string;
  due_at: Date | string | null;
  created_by: string | null;
  created_at: Date | string;
}

interface TimelineRow {
  id: string;
  type: string;
  title: string;
  body: string | null;
  status: string | null;
  amount: string | number | null;
  actor_user_id: string | null;
  actor_first_name: string | null;
  actor_last_name: string | null;
  occurred_at: Date | string;
}

interface CommentRow {
  id: string;
  entity_type: string;
  entity_id: string;
  author_id: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
  body: string;
  created_at: Date | string;
}

interface PaymentRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  student_first_name: string | null;
  student_last_name: string | null;
  amount: string;
  currency: string;
  payment_date: Date | string;
  method: string | null;
  external_id: string | null;
  notes: string | null;
  created_by: string | null;
  created_at: Date | string;
}

interface ExpectedPaymentRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  student_first_name: string | null;
  student_last_name: string | null;
  amount: string;
  due_date: Date | string | null;
  status: string;
  description: string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

interface StudentBalanceRow {
  student_id: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  total_paid: string | number;
  total_cost: string | number;
  balance: string | number;
  updated_at: Date | string;
}

interface SubscriptionRow {
  id: string;
  student_id: string;
  student_user_id: string | null;
  lessons_total: number;
  lessons_used: number;
  starts_at: Date | string | null;
  expires_at: Date | string | null;
  status: string;
  created_at: Date | string;
  updated_at: Date | string;
}

interface LeadRow {
  id: string;
  status_id: string | null;
  status_name: string | null;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  email: string | null;
  source: string | null;
  notes: string | null;
  assigned_to: string | null;
  custom_data: Record<string, unknown> | null;
  created_by: string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

interface LeadBoardRow extends LeadRow {
  status_color: string | null;
  status_sort_order: number | null;
  assigned_first_name: string | null;
  assigned_last_name: string | null;
  branch_id: string | null;
  branch_name: string | null;
  linked_student_id: string | null;
  open_tasks_count: string | number;
  comments_count: string | number;
  trial_lessons_count: string | number;
}

interface LeadBoardCountRow {
  status_id: string | null;
  count: string | number;
}

interface DuplicateCandidateRow {
  id: string;
  entity_type_a: string;
  entity_id_a: string;
  entity_type_b: string;
  entity_id_b: string;
  match_type: string;
  match_value: string;
  confidence: string | number;
  source: string;
  status: string;
  decided_at: Date | string | null;
  decided_by: string | null;
  decision_notes: string | null;
  created_at: Date | string;
  updated_at: Date | string;
  entity_a_name: string | null;
  entity_b_name: string | null;
  entity_a_phone: string | null;
  entity_b_phone: string | null;
  entity_a_email: string | null;
  entity_b_email: string | null;
}

interface BranchRow {
  id: string;
  name: string;
  address: string | null;
  utc_offset_minutes: number | string;
  created_at: Date | string;
}

interface RoomRow {
  id: string;
  branch_id: string | null;
  branch_name: string | null;
  name: string;
  capacity: number | null;
  created_at: Date | string;
}

interface RoomAvailabilityRow {
  room_id: string;
  branch_id: string | null;
  branch_name: string | null;
  room_name: string;
  capacity: number | null;
  lessons: Array<Record<string, unknown>> | null;
  is_available: boolean | null;
  conflict_types: string[] | null;
}

interface GroupRow {
  id: string;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  name: string;
  price_per_lesson: string | null;
  teacher_name: string | null;
  branch_name: string | null;
  room_name: string | null;
  created_at: Date | string;
}

interface LeadStatusRow {
  id: string;
  name: string;
  color: string | null;
  sort_order: number;
  created_at: Date | string;
}

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

@Injectable()
export class CrmService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly hollihop: HolliHopMetadataService,
    private readonly notifications: NotificationsService,
  ) {}

  async getMySummary(actor: ActorContext) {
    const students = await this.listClientStudents(actor.userId);
    const lessons = await this.listLessons(actor, { limit: 20 });
    const tasks = await this.listTasks(actor, { limit: 20 });
    const payments = await this.listPayments(actor, { limit: 20 });

    return {
      students: students.map((row) => this.toStudentDto(row)),
      upcomingLessons: lessons.items,
      tasks: tasks.items,
      recentPayments: payments.items,
    };
  }

  async getOverview(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
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
      revenueMonth: this.toNumericStat(row?.revenue_month),
    };
  }

  async getManagerDashboard(actor: ActorContext, query: ManagerDashboardQuery) {
    this.policy.assertCanWriteCrm(actor);
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
              and ($3::uuid is null or ${this.branchIdExpr('s')} = $3::text)
          ) as revenue,
          (
            select coalesce(sum(ep.amount), 0)
            from app.expected_payments ep
            join app.students s on s.id = ep.student_id and s.deleted_at is null
            where ep.status in ('pending', 'open')
              and (ep.due_date is null or ep.due_date < $2::date)
              and ($3::uuid is null or ${this.branchIdExpr('s')} = $3::text)
          ) as expected_payments,
          (
            select count(*)
            from app.student_balances sb
            join app.students s on s.id = sb.student_id and s.deleted_at is null
            where sb.balance < 0
              and ($3::uuid is null or ${this.branchIdExpr('s')} = $3::text)
          ) as debt_students,
          (
            select count(*)
            from app.students s
            where s.deleted_at is null
              and s.status = 'active'
              and ($3::uuid is null or ${this.branchIdExpr('s')} = $3::text)
          ) as active_students,
          (
            select count(*)
            from app.leads l
            where l.deleted_at is null
              and l.created_at >= $1::timestamptz
              and l.created_at < $2::timestamptz
              and ($3::uuid is null or ${this.branchIdExpr('l')} = $3::text)
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
        revenue: this.toNumericStat(row?.revenue),
        expectedPayments: this.toNumericStat(row?.expected_payments),
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
    this.policy.assertCanWriteCrm(actor);
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

  async listStudents(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanListStudents(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where s.deleted_at is null
          and (
            $1::text in ('manager', 'admin', 'system_admin')
            or ($1::text = 'teacher' and tp.user_id = $2)
          )
          and (
            $3::text is null
            or lower(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || coalesce(u.email, '')) like lower('%' || $3 || '%')
          )
        group by s.id, p.id, u.id
        order by s.created_at desc, s.id desc
        limit $4
      `,
      [actor.role, actor.userId, q || null, limit],
    );

    return { items: result.rows.map((row) => this.toStudentDto(row)) };
  }

  async searchStudents(actor: ActorContext, query: StudentSearchQuery) {
    this.policy.assertCanListStudents(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const filter = this.buildStudentSearchFilter(actor, query);
    const result = await this.database.query<StudentSearchRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone,
          s.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids,
          ${this.branchIdExpr('s')} as branch_id,
          b.name as branch_name,
          (
            select count(*)
            from app.group_students active_groups
            where active_groups.student_id = s.id
              and active_groups.left_at is null
          ) as groups_count,
          (
            select count(*)
            from app.tasks open_task
            where open_task.entity_type = 'student'
              and open_task.entity_id = s.id
              and open_task.deleted_at is null
              and open_task.status in ('open', 'in_progress')
          ) as open_tasks_count,
          (
            select count(*)
            from app.lessons lesson
            where lesson.student_id = s.id
              and lesson.deleted_at is null
          ) as lessons_count,
          (
            select coalesce(sum(payment.amount), 0)
            from app.payments payment
            where payment.student_id = s.id
              and payment.deleted_at is null
          ) as payments_total,
          coalesce(link_user.id, case when u.is_app_account = true then u.id else null end) as linked_user_id,
          coalesce(link_user.email, case when u.is_app_account = true then u.email else null end) as linked_user_email,
          coalesce(link_user.is_app_account, u.is_app_account, false) as is_app_account
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b
          on b.id::text = ${this.branchIdExpr('s')}
         and b.deleted_at is null
        left join app.user_crm_links link
          on link.entity_type = 'student'
         and link.entity_id = s.id
         and link.deleted_at is null
        left join app.users link_user
          on link_user.id = link.user_id
         and link_user.deleted_at is null
        where ${filter.where}
        group by s.id, p.id, u.id, b.id, link_user.id
        order by s.created_at desc, s.id desc
        limit $${filter.params.length + 1}
      `,
      [...filter.params, limit],
    );
    return {
      items: result.rows.map((row) => this.toStudentSearchDto(row)),
      totalCount: result.rows.length,
    };
  }

  async createStudent(actor: ActorContext, dto: CreateStudentDto) {
    this.policy.assertCanWriteCrm(actor);
    const firstName = this.requiredTrim(
      dto.firstName,
      "Имя ученика обязательно.",
    );
    const lastName = this.trimOptional(dto.lastName);
    const phone = this.trimOptional(dto.phone);
    const email = this.trimOptional(dto.email)?.toLowerCase() ?? null;
    const status = this.trimOptional(dto.status) ?? "active";
    const fullName = [firstName, lastName].filter(Boolean).join(" ");
    const leadId = dto.leadId ?? null;
    const customDataPatch = this.sanitizeJsonObject(dto.customDataPatch);
    const branchId = this.extractBranchId(dto.customDataPatch);

    if (leadId) {
      const lead = await this.database.query<{ id: string }>(
        "select id from app.leads where id = $1 and deleted_at is null limit 1",
        [leadId],
      );
      if (!lead.rows[0]) throw new NotFoundException("Лид не найден.");

      const existingStudent = await this.database.query<{ id: string }>(
        "select id from app.students where lead_id = $1 and deleted_at is null limit 1",
        [leadId],
      );
      if (existingStudent.rows[0]) {
        throw new ConflictException("Этот лид уже конвертирован в ученика.");
      }
    }

    try {
      const result = await this.database.query<StudentRow>(
        `
          with identity as (
            select coalesce($3::text, 'student-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid') as email
          ),
          inserted_user as (
            insert into app.users (email, full_name, phone, role, profile_completed, is_app_account)
            select identity.email, $4, $5, 'client'::app.user_role, false, false
            from identity
            returning id, email
          ),
          inserted_profile as (
            insert into app.profiles (user_id, first_name, last_name, phone)
            select id, $1, $2, $5
            from inserted_user
            returning id, user_id, first_name, last_name, phone
          ),
          inserted_student as (
            insert into app.students (profile_id, status, lead_id, custom_data, branch_id)
            select id, $6, $7, $8::jsonb, $9::uuid
            from inserted_profile
            returning id, status, profile_id, lead_id, custom_data, created_at
          )
          select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
            s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone, s.created_at,
            '{}'::uuid[] as teacher_user_ids
          from inserted_student s
          join inserted_profile p on p.id = s.profile_id
          join inserted_user u on u.id = p.user_id
          limit 1
        `,
        [
          firstName,
          lastName,
          email,
          fullName,
          phone,
          status,
          leadId,
          JSON.stringify(customDataPatch),
          branchId,
        ],
      );
      const student = result.rows[0];
      await this.audit.record({
        actor,
        action: "crm.student_created",
        entityType: "student",
        entityId: student.id,
        metadata: { leadId },
      });
      return this.toStudentDto(student);
    } catch (error) {
      this.rethrowCreatePersonError(error);
    }
  }

  async getStudent(actor: ActorContext, studentId: string) {
    const student = await this.findStudent(studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });
    return this.toStudentDto(student);
  }

  async getStudentCard(actor: ActorContext, studentId: string) {
    const student = await this.findStudent(studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });

    const [
      groups,
      lessons,
      payments,
      tasks,
      comments,
      expectedPayments,
      balances,
      links,
    ] = await Promise.all([
      this.listStudentGroups(actor, studentId, { limit: 100 }),
      this.listLessons(actor, { studentId, limit: 100 }),
      this.listPayments(actor, { studentId, limit: 100 }),
      this.listTasks(actor, { studentId, limit: 100 }),
      this.listComments(actor, {
        entityType: "student",
        entityId: studentId,
        limit: 100,
      }),
      this.listExpectedPayments(actor, { studentId, limit: 100 }),
      this.listStudentBalances(actor, { studentId, limit: 1 }),
      this.listUserCrmLinks("student", studentId),
    ]);

    const timeline = [
      ...comments.items.map((comment) => ({
        id: comment.id,
        type: "comment",
        title: "Комментарий",
        body: comment.body,
        status: null,
        occurredAt: comment.createdAt,
      })),
      ...tasks.items.map((task) => ({
        id: task.id,
        type: "task",
        title: task.title,
        body: task.description,
        status: task.status,
        occurredAt: task.createdAt,
      })),
      ...lessons.items.map((lesson) => ({
        id: lesson.id,
        type: lesson.isTrial ? "trial" : "lesson",
        title: lesson.isTrial ? "Пробное занятие" : "Занятие",
        body: lesson.teacherName || lesson.roomName || null,
        status: lesson.status,
        occurredAt: lesson.scheduledAt,
      })),
      ...payments.items.map((payment) => ({
        id: payment.id,
        type: "payment",
        title: "Платеж",
        body: `${payment.amount} ${payment.currency}`,
        status: null,
        occurredAt: payment.paymentDate,
      })),
    ].sort(
      (a, b) =>
        new Date(String(b.occurredAt)).getTime() -
        new Date(String(a.occurredAt)).getTime(),
    );

    return {
      student: this.toStudentDto(student),
      groups: groups.items,
      lessons: lessons.items,
      payments: payments.items,
      tasks: tasks.items,
      comments: comments.items,
      expectedPayments: expectedPayments.items,
      balance: balances.items[0] ?? null,
      links,
      timeline,
    };
  }

  async listDuplicateCandidates(
    actor: ActorContext,
    query: DuplicateCandidatesQuery,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<DuplicateCandidateRow>(
      `
        select dc.id, dc.entity_type_a, dc.entity_id_a, dc.entity_type_b, dc.entity_id_b,
          dc.match_type, dc.match_value, dc.confidence, dc.source, dc.status,
          dc.decided_at, dc.decided_by, dc.decision_notes, dc.created_at, dc.updated_at,
          coalesce(
            nullif(concat_ws(' ', spa.first_name, spa.last_name), ''),
            nullif(concat_ws(' ', la.first_name, la.last_name), '')
          ) as entity_a_name,
          coalesce(
            nullif(concat_ws(' ', spb.first_name, spb.last_name), ''),
            nullif(concat_ws(' ', lb.first_name, lb.last_name), '')
          ) as entity_b_name,
          coalesce(spa.phone, la.phone) as entity_a_phone,
          coalesce(spb.phone, lb.phone) as entity_b_phone,
          coalesce(ua.email, la.email) as entity_a_email,
          coalesce(ub.email, lb.email) as entity_b_email
        from app.duplicate_candidates dc
        left join app.students sa on dc.entity_type_a = 'student' and sa.id = dc.entity_id_a and sa.deleted_at is null
        left join app.profiles spa on spa.id = sa.profile_id and spa.deleted_at is null
        left join app.users ua on ua.id = spa.user_id and ua.deleted_at is null
        left join app.leads la on dc.entity_type_a = 'lead' and la.id = dc.entity_id_a and la.deleted_at is null
        left join app.students sb on dc.entity_type_b = 'student' and sb.id = dc.entity_id_b and sb.deleted_at is null
        left join app.profiles spb on spb.id = sb.profile_id and spb.deleted_at is null
        left join app.users ub on ub.id = spb.user_id and ub.deleted_at is null
        left join app.leads lb on dc.entity_type_b = 'lead' and lb.id = dc.entity_id_b and lb.deleted_at is null
        where dc.deleted_at is null
          and ($1::text is null or dc.status = $1)
          and (
            $2::uuid is null
            or (dc.entity_type_a = 'lead' and dc.entity_id_a = $2)
            or (dc.entity_type_b = 'lead' and dc.entity_id_b = $2)
          )
        order by dc.created_at desc, dc.id desc
        limit $3
      `,
      [query.status ?? "pending", query.leadId ?? null, limit],
    );
    return {
      items: result.rows.map((row) => this.toDuplicateCandidateDto(row)),
    };
  }

  async decideDuplicateCandidate(
    actor: ActorContext,
    candidateId: string,
    dto: DuplicateDecisionDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const candidateResult = await this.database.query<DuplicateCandidateRow>(
      `
        select dc.id, dc.entity_type_a, dc.entity_id_a, dc.entity_type_b, dc.entity_id_b,
          dc.match_type, dc.match_value, dc.confidence, dc.source, dc.status,
          dc.decided_at, dc.decided_by, dc.decision_notes, dc.created_at, dc.updated_at,
          null::text as entity_a_name, null::text as entity_b_name,
          null::text as entity_a_phone, null::text as entity_b_phone,
          null::text as entity_a_email, null::text as entity_b_email
        from app.duplicate_candidates dc
        where dc.id = $1 and dc.deleted_at is null
        limit 1
      `,
      [candidateId],
    );
    const candidate = candidateResult.rows[0];
    if (!candidate) throw new NotFoundException("Кандидат дубля не найден.");

    if (dto.status === "attached") {
      await this.attachDuplicateCandidate(candidate);
    }

    const updated = await this.database.query<DuplicateCandidateRow>(
      `
        update app.duplicate_candidates
        set status = $2,
          decided_at = now(),
          decided_by = $3,
          decision_notes = $4,
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, entity_type_a, entity_id_a, entity_type_b, entity_id_b,
          match_type, match_value, confidence, source, status, decided_at,
          decided_by, decision_notes, created_at, updated_at,
          null::text as entity_a_name, null::text as entity_b_name,
          null::text as entity_a_phone, null::text as entity_b_phone,
          null::text as entity_a_email, null::text as entity_b_email
      `,
      [candidateId, dto.status, actor.userId, dto.notes?.trim() || null],
    );
    const row = updated.rows[0];
    await this.audit.record({
      actor,
      action: "crm.duplicate_candidate_decided",
      entityType: "student",
      entityId: candidateId,
      metadata: {
        status: dto.status,
        entityTypeA: candidate.entity_type_a,
        entityTypeB: candidate.entity_type_b,
      },
    });
    return this.toDuplicateCandidateDto(row);
  }

  async listStudentGroups(
    actor: ActorContext,
    studentId: string,
    query: CrmListQuery,
  ) {
    const student = await this.findStudent(studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });

    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<GroupRow>(
      `
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.created_at
        from app.group_students gs
        join app.groups g on g.id = gs.group_id and g.deleted_at is null
        left join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = g.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = g.room_id and r.deleted_at is null
        where gs.student_id = $1
          and gs.left_at is null
        order by g.name asc, g.id asc
        limit $2
      `,
      [studentId, limit],
    );

    return { items: result.rows.map((row) => this.toGroupDto(row)) };
  }

  async updateStudent(
    actor: ActorContext,
    studentId: string,
    dto: UpdateStudentDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const customDataPatch = this.sanitizeJsonObject(dto.customDataPatch);
    const branchId = this.extractBranchId(dto.customDataPatch);
    const beforeStudent = (
      await this.database.query<{ status: string | null; branch_id: string | null }>(
        `select status, branch_id from app.students where id = $1 and deleted_at is null`,
        [studentId],
      )
    ).rows[0] ?? null;
    const result = await this.database.query<StudentRow>(
      `
        with target as (
          select s.id, s.profile_id, p.user_id
          from app.students s
          left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          where s.id = $1 and s.deleted_at is null
          limit 1
        ),
        updated_profile as (
          update app.profiles p
          set first_name = coalesce($2, p.first_name),
            last_name = coalesce($3, p.last_name),
            phone = coalesce($4, p.phone),
            updated_at = now()
          from target
          where p.id = target.profile_id
          returning p.id, p.user_id, p.first_name, p.last_name, p.phone
        ),
        updated_user as (
          update app.users u
          set email = coalesce($5, u.email),
            updated_at = now()
          from target
          where u.id = target.user_id
          returning u.id, u.email
        ),
        updated_student as (
          update app.students s
          set status = coalesce($6, s.status),
            custom_data = coalesce(s.custom_data, '{}'::jsonb) || $7::jsonb,
            branch_id = coalesce($8::uuid, s.branch_id),
            updated_at = now()
          from target
          where s.id = target.id
          returning s.id, s.status, s.profile_id, s.lead_id, s.custom_data, s.created_at
        )
        select us.id, us.status, us.profile_id,
          coalesce(updated_profile_dependency.user_id, p.user_id) as profile_user_id,
          us.lead_id, us.custom_data,
          coalesce(updated_profile_dependency.first_name, p.first_name) as first_name,
          coalesce(updated_profile_dependency.last_name, p.last_name) as last_name,
          coalesce(updated_user_dependency.email, u.email) as email,
          coalesce(updated_profile_dependency.phone, p.phone) as phone,
          us.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
        from updated_student us
        join app.students s on s.id = us.id
        left join updated_profile updated_profile_dependency on true
        left join updated_user updated_user_dependency on true
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        group by us.id, us.status, us.profile_id, us.lead_id, us.custom_data, us.created_at, p.id, u.id,
          updated_profile_dependency.user_id,
          updated_profile_dependency.first_name,
          updated_profile_dependency.last_name,
          updated_profile_dependency.phone,
          updated_user_dependency.email
        limit 1
      `,
      [
        studentId,
        this.trimOptional(dto.firstName),
        this.trimOptional(dto.lastName),
        this.trimOptional(dto.phone),
        this.trimOptional(dto.email)?.toLowerCase() ?? null,
        this.trimOptional(dto.status),
        JSON.stringify(customDataPatch),
        branchId,
      ],
    );
    const student = result.rows[0];
    if (!student) throw new NotFoundException("Ученик не найден.");
    await this.audit.record({
      actor,
      action: "crm.student_updated",
      entityType: "student",
      entityId: student.id,
    });
    if (beforeStudent && beforeStudent.status !== student.status) {
      await this.database.query(
        `insert into app.student_status_history (student_id, status, branch_id)
         values ($1, $2, $3)`,
        [studentId, student.status, branchId ?? beforeStudent.branch_id],
      );
    }
    return this.toStudentDto(student);
  }

  async inviteStudent(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    const student = await this.findStudent(studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");

    const email = this.trimOptional(student.email ?? undefined)?.toLowerCase();
    if (!email || !this.isDeliverableEmail(email)) {
      throw new BadRequestException("У ученика нет email для приглашения.");
    }
    if (!student.profile_user_id) {
      throw new BadRequestException("У ученика нет профиля для приглашения.");
    }

    await this.notifications.sendEmail({
      userId: student.profile_user_id,
      template: "student_invite",
      title: "Приглашение в личный кабинет Magic Music",
      body:
        "Здравствуйте! Школа Magic Music подготовила для вас личный кабинет. " +
        `Зарегистрируйтесь в приложении Magic Music CRM с этой почтой: ${email}. ` +
        "После регистрации аккаунт будет привязан к вашей карточке ученика.",
    });

    await this.audit.record({
      actor,
      action: "crm.student_invite_sent",
      entityType: "student",
      entityId: student.id,
      metadata: { emailHash: this.hashEmail(email) },
    });

    return { studentId: student.id, email, status: "queued" };
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

  async listTeachers(actor: ActorContext, query: TeacherListQuery) {
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<TeacherRow>(
      `
        select distinct t.id, t.status, t.specialization, t.custom_data,
          t.profile_id, p.user_id as profile_user_id, u.role::text as app_role,
          coalesce(u.is_app_account, false) as is_app_account,
          p.first_name, p.last_name, u.email, p.phone,
          (
            select coalesce(
              jsonb_agg(
                distinct jsonb_build_object('id', branch_rows.id, 'name', branch_rows.name)
              ) filter (where branch_rows.id is not null),
              '[]'::jsonb
            )
            from (
              select b.id, b.name
              from app.groups group_branch
              join app.branches b on b.id = group_branch.branch_id and b.deleted_at is null
              where group_branch.teacher_id = t.id and group_branch.deleted_at is null
              union
              select b.id, b.name
              from app.lessons lesson_branch
              join app.branches b on b.id = lesson_branch.branch_id and b.deleted_at is null
              where lesson_branch.teacher_id = t.id and lesson_branch.deleted_at is null
            ) branch_rows
          ) as branches,
          (
            select count(*)
            from (
              select l.student_id
              from app.lessons l
              where l.teacher_id = t.id
                and l.student_id is not null
                and l.deleted_at is null
              union
              select gs.student_id
              from app.groups g
              join app.group_students gs on gs.group_id = g.id and gs.left_at is null
              where g.teacher_id = t.id
                and gs.student_id is not null
                and g.deleted_at is null
            ) teacher_students
          ) as students_count,
          (
            select count(*)
            from app.lessons lesson_count
            where lesson_count.teacher_id = t.id
              and lesson_count.deleted_at is null
          ) as lessons_count,
          case
            when t.custom_data->>'rating' ~ '^-?[0-9]+(\\.[0-9]+)?$'
              then (t.custom_data->>'rating')::numeric
            else null
          end as rating,
          t.created_at
        from app.teachers t
        left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.teacher_id = t.id and l.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.groups g on g.teacher_id = t.id and g.deleted_at is null
        left join app.group_students gs on gs.group_id = g.id and gs.left_at is null
        left join app.students group_student on group_student.id = gs.student_id and group_student.deleted_at is null
        left join app.profiles group_student_profile on group_student_profile.id = group_student.profile_id and group_student_profile.deleted_at is null
        where t.deleted_at is null
          and (
            $1::text in ('manager', 'admin', 'system_admin')
            or ($1::text = 'teacher' and p.user_id = $2)
            or ($1::text = 'client' and (sp.user_id = $2 or group_student_profile.user_id = $2))
          )
          and (
            $3::text is null
            or lower(
              coalesce(p.first_name, '') || ' ' ||
              coalesce(p.last_name, '') || ' ' ||
              coalesce(u.email, '') || ' ' ||
              coalesce(p.phone, '') || ' ' ||
              coalesce(t.specialization, '') || ' ' ||
              coalesce(t.custom_data::text, '')
            ) like lower('%' || $3 || '%')
          )
          and ($4::text is null or t.status = $4)
          and (
            $5::uuid is null
            or exists (
              select 1
              from app.groups branch_group
              where branch_group.teacher_id = t.id
                and branch_group.branch_id = $5
                and branch_group.deleted_at is null
            )
            or exists (
              select 1
              from app.lessons branch_lesson
              where branch_lesson.teacher_id = t.id
                and branch_lesson.branch_id = $5
                and branch_lesson.deleted_at is null
            )
          )
          and (
            $6::text is null
            or lower(concat_ws(' ',
              t.specialization,
              t.custom_data->>'discipline',
              t.custom_data->>'disciplineName',
              t.custom_data->>'discipline_name',
              t.custom_data->>'disciplines'
            )) like lower('%' || $6 || '%')
          )
          and (
            $7::text is null
            or lower(concat_ws(' ',
              t.custom_data->>'level',
              t.custom_data->>'levelName',
              t.custom_data->>'level_name',
              t.custom_data->>'levels'
            )) like lower('%' || $7 || '%')
          )
          and (
            $8::text is null
            or lower(concat_ws(' ',
              t.custom_data->>'category',
              t.custom_data->>'categoryName',
              t.custom_data->>'category_name',
              t.custom_data->>'maturity',
              t.custom_data->>'maturities',
              t.custom_data->>'categories'
            )) like lower('%' || $8 || '%')
          )
          and ($9::text is null or u.role::text = $9)
          and (
            $10::text is null
            or ($10 = 'app' and coalesce(u.is_app_account, false) = true)
            or ($10 = 'technical' and coalesce(u.is_app_account, false) = false)
            or ($10 = 'linked' and exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'teacher'
                and link.entity_id = t.id
                and link.deleted_at is null
            ))
            or ($10 = 'unlinked' and not exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'teacher'
                and link.entity_id = t.id
                and link.deleted_at is null
            ))
          )
          and (
            $11::numeric is null
            or (
              case
                when t.custom_data->>'rating' ~ '^-?[0-9]+(\\.[0-9]+)?$'
                  then (t.custom_data->>'rating')::numeric
                else null
              end
            ) >= $11
          )
          and (
            $12::numeric is null
            or (
              case
                when t.custom_data->>'rating' ~ '^-?[0-9]+(\\.[0-9]+)?$'
                  then (t.custom_data->>'rating')::numeric
                else null
              end
            ) <= $12
          )
          and (
            $13::int is null
            or (
              case
                when p.dob is not null then extract(month from p.dob)::int
                when coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
                  then extract(month from coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date')::date)::int
                when coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date') ~ '^[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}$'
                  then extract(month from to_date(coalesce(t.custom_data->>'birthday', t.custom_data->>'birthDate', t.custom_data->>'birth_date'), 'DD.MM.YYYY'))::int
                else null
              end
            ) = $13
          )
        order by p.last_name nulls last, p.first_name nulls last, t.id
        limit $14
      `,
      [
        actor.role,
        actor.userId,
        q || null,
        query.status ?? null,
        query.branchId ?? null,
        query.discipline ?? null,
        query.level ?? null,
        query.category ?? null,
        query.appRole ?? null,
        query.authorization ?? null,
        query.ratingFrom ?? null,
        query.ratingTo ?? null,
        query.birthdayMonth ?? null,
        limit,
      ],
    );

    return { items: result.rows.map((row) => this.toTeacherDto(row)) };
  }

  async createTeacher(actor: ActorContext, dto: CreateTeacherDto) {
    this.policy.assertCanWriteCrm(actor);
    const firstName = this.requiredTrim(
      dto.firstName,
      "Имя преподавателя обязательно.",
    );
    const lastName = this.trimOptional(dto.lastName);
    const phone = this.trimOptional(dto.phone);
    const email = this.trimOptional(dto.email)?.toLowerCase() ?? null;
    const specialization = this.trimOptional(dto.specialization);
    const status = this.trimOptional(dto.status) ?? "active";
    const fullName = [firstName, lastName].filter(Boolean).join(" ");

    try {
      const result = await this.database.query<TeacherRow>(
        `
          with identity as (
            select coalesce($3::text, 'teacher-' || gen_random_uuid()::text || '@local.magicmusiccrm.invalid') as email
          ),
          inserted_user as (
            insert into app.users (email, full_name, phone, role, profile_completed, is_app_account)
            select identity.email, $4, $5, 'teacher'::app.user_role, false, false
            from identity
            returning id, email
          ),
          inserted_profile as (
            insert into app.profiles (user_id, first_name, last_name, phone)
            select id, $1, $2, $5
            from inserted_user
            returning id, user_id, first_name, last_name, phone
          ),
          inserted_teacher as (
            insert into app.teachers (profile_id, status, specialization)
            select id, $6, $7
            from inserted_profile
            returning id, status, specialization, profile_id
          )
          select t.id, t.status, t.specialization, t.profile_id,
            p.user_id as profile_user_id, p.first_name, p.last_name, u.email, p.phone
          from inserted_teacher t
          join inserted_profile p on p.id = t.profile_id
          join inserted_user u on u.id = p.user_id
          limit 1
        `,
        [firstName, lastName, email, fullName, phone, status, specialization],
      );
      const teacher = result.rows[0];
      await this.audit.record({
        actor,
        action: "crm.teacher_created",
        entityType: "teacher",
        entityId: teacher.id,
      });
      return this.toTeacherDto(teacher);
    } catch (error) {
      this.rethrowCreatePersonError(error);
    }
  }

  async updateTeacher(
    actor: ActorContext,
    teacherId: string,
    dto: UpdateTeacherDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<TeacherRow>(
      `
        with target as (
          select t.id, t.profile_id, p.user_id
          from app.teachers t
          left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
          where t.id = $1 and t.deleted_at is null
          limit 1
        ),
        updated_profile as (
          update app.profiles p
          set first_name = coalesce($2, p.first_name),
            last_name = coalesce($3, p.last_name),
            phone = coalesce($4, p.phone),
            updated_at = now()
          from target
          where p.id = target.profile_id
          returning p.id, p.user_id, p.first_name, p.last_name, p.phone
        ),
        updated_user as (
          update app.users u
          set email = coalesce($5, u.email),
            updated_at = now()
          from target
          where u.id = target.user_id
          returning u.id, u.email
        ),
        updated_teacher as (
          update app.teachers t
          set status = coalesce($6, t.status),
            specialization = coalesce($7, t.specialization),
            updated_at = now()
          from target
          where t.id = target.id
          returning t.id, t.status, t.specialization, t.profile_id
        )
        select ut.id, ut.status, ut.specialization, ut.profile_id,
          coalesce(updated_profile_dependency.user_id, p.user_id) as profile_user_id,
          coalesce(updated_profile_dependency.first_name, p.first_name) as first_name,
          coalesce(updated_profile_dependency.last_name, p.last_name) as last_name,
          coalesce(updated_user_dependency.email, u.email) as email,
          coalesce(updated_profile_dependency.phone, p.phone) as phone
        from updated_teacher ut
        left join updated_profile updated_profile_dependency on true
        left join updated_user updated_user_dependency on true
        left join app.profiles p on p.id = ut.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        limit 1
      `,
      [
        teacherId,
        this.trimOptional(dto.firstName),
        this.trimOptional(dto.lastName),
        this.trimOptional(dto.phone),
        this.trimOptional(dto.email)?.toLowerCase() ?? null,
        this.trimOptional(dto.status),
        this.trimOptional(dto.specialization),
      ],
    );
    const teacher = result.rows[0];
    if (!teacher) throw new NotFoundException("Преподаватель не найден.");
    await this.audit.record({
      actor,
      action: "crm.teacher_updated",
      entityType: "teacher",
      entityId: teacher.id,
    });
    return this.toTeacherDto(teacher);
  }

  async listStaff(actor: ActorContext, query: StaffListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<StaffRow>(
      `
        select sm.id, sm.role, sm.position, sm.status, sm.custom_data,
          sm.profile_id, p.user_id as profile_user_id, u.role as app_role,
          u.is_app_account, p.first_name, p.last_name, u.email, p.phone,
          coalesce(
            jsonb_agg(
              distinct jsonb_build_object('id', b.id, 'name', b.name)
            ) filter (where b.id is not null),
            '[]'::jsonb
          ) as branches,
          sm.created_at
        from app.staff_members sm
        left join app.profiles p on p.id = sm.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.staff_branch_assignments sba
          on sba.staff_member_id = sm.id and sba.deleted_at is null
        left join app.branches b on b.id = sba.branch_id and b.deleted_at is null
        where sm.deleted_at is null
          and ($1::uuid is null or exists (
            select 1
            from app.staff_branch_assignments branch_filter
            where branch_filter.staff_member_id = sm.id
              and branch_filter.branch_id = $1
              and branch_filter.deleted_at is null
          ))
          and (
            $2::text is null
            or lower(
              coalesce(p.first_name, '') || ' ' ||
              coalesce(p.last_name, '') || ' ' ||
              coalesce(u.email, '') || ' ' ||
              coalesce(p.phone, '') || ' ' ||
              coalesce(sm.role, '') || ' ' ||
              coalesce(sm.position, '')
            ) like lower('%' || $2 || '%')
          )
          and ($3::text is null or sm.role = $3)
          and ($4::text is null or sm.status = $4)
          and ($5::text is null or u.role::text = $5)
          and (
            $6::text is null
            or ($6 = 'app' and coalesce(u.is_app_account, false) = true)
            or ($6 = 'technical' and coalesce(u.is_app_account, false) = false)
            or ($6 = 'linked' and exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'staff'
                and link.entity_id = sm.id
                and link.deleted_at is null
            ))
            or ($6 = 'unlinked' and not exists (
              select 1
              from app.user_crm_links link
              where link.entity_type = 'staff'
                and link.entity_id = sm.id
                and link.deleted_at is null
            ))
          )
          and (
            $7::int is null
            or (
              case
                when p.dob is not null then extract(month from p.dob)::int
                when coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
                  then extract(month from coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date')::date)::int
                when coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date') ~ '^[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}$'
                  then extract(month from to_date(coalesce(sm.custom_data->>'birthday', sm.custom_data->>'birthDate', sm.custom_data->>'birth_date'), 'DD.MM.YYYY'))::int
                else null
              end
            ) = $7
          )
        group by sm.id, p.id, u.id
        order by sm.created_at desc, sm.id desc
        limit $8
      `,
      [
        query.branchId ?? null,
        q || null,
        query.role ?? null,
        query.status ?? null,
        query.appRole ?? null,
        query.authorization ?? null,
        query.birthdayMonth ?? null,
        limit,
      ],
    );

    return { items: result.rows.map((row) => this.toStaffDto(row)) };
  }

  async createStaff(actor: ActorContext, dto: CreateStaffDto) {
    if (!isAdminRole(actor.role)) {
      throw new ForbiddenException(
        "Только администратор может создавать сотрудников.",
      );
    }
    const firstName = this.requiredTrim(
      dto.firstName,
      "Имя сотрудника обязательно.",
    );
    const lastName = this.requiredTrim(
      dto.lastName,
      "Фамилия сотрудника обязательна.",
    );
    const email = this.requiredTrim(
      dto.email,
      "Email сотрудника обязателен.",
    ).toLowerCase();
    const phone = this.trimOptional(dto.phone);
    const fullName = [firstName, lastName].join(" ");

    try {
      const result = await this.database.query(
        `
          with inserted_user as (
            insert into app.users (email, full_name, phone, role, profile_completed, is_app_account)
            values ($1, $2, $3, $4::app.user_role, true, true)
            returning id, email, role, created_at, updated_at
          ),
          inserted_profile as (
            insert into app.profiles (user_id, first_name, last_name, phone)
            select id, $5, $6, $3
            from inserted_user
            returning id, user_id, first_name, last_name, phone, avatar_file_id, email_otp_2fa_enabled, created_at, updated_at
          ),
          inserted_staff as (
            insert into app.staff_members (profile_id, role, position, status)
            select
              id,
              $4,
              case
                when $4 = 'system_admin' then 'Администратор системы'
                when $4 = 'admin' then 'Администратор'
                when $4 = 'manager' then 'Управляющий'
                else 'Сотрудник'
              end,
              'working'
            from inserted_profile
            returning id, profile_id, role, position, status
          )
          select p.id, p.user_id as "userId", u.email, u.role,
            s.id as "staffId", s.position, s.status as "staffStatus",
            p.first_name as "firstName", p.last_name as "lastName", p.phone,
            p.avatar_file_id as "avatarFileId",
            p.email_otp_2fa_enabled as "emailOtp2faEnabled",
            p.created_at as "createdAt", p.updated_at as "updatedAt"
          from inserted_profile p
          join inserted_user u on u.id = p.user_id
          left join inserted_staff s on s.profile_id = p.id
          limit 1
        `,
        [email, fullName, phone, dto.role, firstName, lastName],
      );
      const staff = result.rows[0];
      await this.audit.record({
        actor,
        action: "crm.staff_created",
        entityType: "profile",
        entityId: staff.id,
      });
      return staff;
    } catch (error) {
      this.rethrowCreatePersonError(error);
    }
  }

  async updateStaff(actor: ActorContext, staffId: string, dto: UpdateStaffDto) {
    if (!isAdminRole(actor.role)) {
      throw new ForbiddenException(
        "Только администратор может редактировать сотрудников.",
      );
    }
    const customDataPatch = this.sanitizeJsonObject(dto.customDataPatch);

    try {
      const result = await this.database.query<StaffRow>(
        `
          with target as (
            select sm.id, sm.profile_id, p.user_id
            from app.staff_members sm
            left join app.profiles p on p.id = sm.profile_id and p.deleted_at is null
            where sm.id = $1 and sm.deleted_at is null
            limit 1
          ),
          updated_profile as (
            update app.profiles p
            set first_name = coalesce($2, p.first_name),
              last_name = coalesce($3, p.last_name),
              phone = coalesce($4, p.phone),
              updated_at = now()
            from target
            where p.id = target.profile_id
            returning p.id, p.user_id, p.first_name, p.last_name, p.phone
          ),
          updated_user as (
            update app.users u
            set email = coalesce($5, u.email),
              updated_at = now()
            from target
            where u.id = target.user_id
            returning u.id, u.email, u.role, u.is_app_account
          ),
          updated_staff as (
            update app.staff_members sm
            set role = coalesce($6, sm.role),
              position = coalesce($7, sm.position),
              status = coalesce($8, sm.status),
              custom_data = coalesce(sm.custom_data, '{}'::jsonb) || $9::jsonb,
              updated_at = now()
            from target
            where sm.id = target.id
            returning sm.id, sm.role, sm.position, sm.status, sm.custom_data,
              sm.profile_id, sm.created_at
          )
          select us.id, us.role, us.position, us.status, us.custom_data,
            us.profile_id,
            coalesce(up.user_id, p.user_id) as profile_user_id,
            coalesce(uu.role, u.role) as app_role,
            coalesce(uu.is_app_account, u.is_app_account, false) as is_app_account,
            coalesce(up.first_name, p.first_name) as first_name,
            coalesce(up.last_name, p.last_name) as last_name,
            coalesce(uu.email, u.email) as email,
            coalesce(up.phone, p.phone) as phone,
            coalesce(
              jsonb_agg(
                distinct jsonb_build_object('id', b.id, 'name', b.name)
              ) filter (where b.id is not null),
              '[]'::jsonb
            ) as branches,
            us.created_at
          from updated_staff us
          left join updated_profile up on true
          left join updated_user uu on true
          left join app.profiles p on p.id = us.profile_id and p.deleted_at is null
          left join app.users u on u.id = coalesce(up.user_id, p.user_id)
            and u.deleted_at is null
          left join app.staff_branch_assignments sba
            on sba.staff_member_id = us.id and sba.deleted_at is null
          left join app.branches b on b.id = sba.branch_id and b.deleted_at is null
          group by us.id, us.role, us.position, us.status, us.custom_data,
            us.profile_id, us.created_at, p.id, u.id,
            up.user_id, up.first_name, up.last_name, up.phone,
            uu.email, uu.role, uu.is_app_account
          limit 1
        `,
        [
          staffId,
          this.trimOptional(dto.firstName),
          this.trimOptional(dto.lastName),
          this.trimOptional(dto.phone),
          this.trimOptional(dto.email)?.toLowerCase() ?? null,
          this.trimOptional(dto.role),
          this.trimOptional(dto.position),
          this.trimOptional(dto.status),
          JSON.stringify(customDataPatch),
        ],
      );
      const staff = result.rows[0];
      if (!staff) throw new NotFoundException("Сотрудник не найден.");
      await this.audit.record({
        actor,
        action: "crm.staff_updated",
        entityType: "staff",
        entityId: staff.id,
      });
      return this.toStaffDto(staff);
    } catch (error) {
      this.rethrowCreatePersonError(error);
    }
  }

  async listBranches(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<BranchRow>(
      `
        select id, name, address, utc_offset_minutes, created_at
        from app.branches
        where deleted_at is null
          and (
            $1::text is null
            or lower(coalesce(name, '') || ' ' || coalesce(address, '')) like lower('%' || $1 || '%')
          )
        order by name asc, id asc
        limit $2
      `,
      [q || null, limit],
    );

    return { items: result.rows.map((row) => this.toBranchDto(row)) };
  }

  async listRooms(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<RoomRow>(
      `
        select r.id, r.branch_id, b.name as branch_name, r.name, r.capacity, r.created_at
        from app.rooms r
        left join app.branches b on b.id = r.branch_id and b.deleted_at is null
        where r.deleted_at is null
          and ($1::uuid is null or r.branch_id = $1)
          and (
            $2::text is null
            or lower(coalesce(r.name, '') || ' ' || coalesce(b.name, '')) like lower('%' || $2 || '%')
          )
        order by b.name nulls last, r.name asc, r.id asc
        limit $3
      `,
      [query.branchId ?? null, q || null, limit],
    );

    return { items: result.rows.map((row) => this.toRoomDto(row)) };
  }

  async listRoomAvailability(
    actor: ActorContext,
    query: RoomAvailabilityQuery,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 200);
    const bounds = this.roomAvailabilityBounds(query);
    const result = await this.database.query<RoomAvailabilityRow>(
      `
        with room_rows as (
          select r.id as room_id, r.branch_id, b.name as branch_name,
            r.name as room_name, r.capacity
          from app.rooms r
          left join app.branches b on b.id = r.branch_id and b.deleted_at is null
          where r.deleted_at is null
            and ($1::uuid is null or r.branch_id = $1)
            and ($2::uuid is null or r.id = $2)
          order by b.name nulls last, r.name asc, r.id asc
          limit $8
        ),
        lesson_rows as (
          select l.id, l.room_id, l.teacher_id, l.branch_id, l.scheduled_at,
            l.duration_minutes, l.status, l.is_trial,
            trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
            trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
            g.name as group_name
          from app.lessons l
          left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
          left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
          left join app.students s on s.id = l.student_id and s.deleted_at is null
          left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          where l.deleted_at is null
            and l.room_id is not null
            and l.scheduled_at >= $3::timestamptz
            and l.scheduled_at < $4::timestamptz
        )
        select rr.room_id, rr.branch_id, rr.branch_name, rr.room_name,
          rr.capacity,
          coalesce(
            jsonb_agg(
              jsonb_build_object(
                'id', lr.id,
                'teacherId', lr.teacher_id,
                'teacherName', nullif(lr.teacher_name, ''),
                'studentName', nullif(lr.student_name, ''),
                'groupName', lr.group_name,
                'scheduledAt', lr.scheduled_at,
                'durationMinutes', lr.duration_minutes,
                'status', lr.status,
                'isTrial', lr.is_trial
              )
              order by lr.scheduled_at asc, lr.id asc
            ) filter (where lr.id is not null),
            '[]'::jsonb
          ) as lessons,
          not exists (
            select 1
            from app.lessons overlap_lesson
            where overlap_lesson.deleted_at is null
              and overlap_lesson.status <> 'cancelled'
              and overlap_lesson.room_id = rr.room_id
              and overlap_lesson.scheduled_at < $6::timestamptz
              and overlap_lesson.scheduled_at + overlap_lesson.duration_minutes * interval '1 minute' > $5::timestamptz
          ) as is_available,
          array_remove(array[
            -- room_overlap = TWO lessons actually overlapping each other in the
            -- room (different groups), not merely the room being occupied during
            -- the queried window (which a whole-day window would always be).
            case when exists (
              select 1
              from app.lessons a
              join app.lessons b
                on b.room_id = a.room_id
                and b.id <> a.id
                and b.deleted_at is null
                and b.status <> 'cancelled'
                and (a.group_id is null or b.group_id is null
                     or a.group_id <> b.group_id)
                and b.scheduled_at < a.scheduled_at + a.duration_minutes * interval '1 minute'
                and b.scheduled_at + b.duration_minutes * interval '1 minute' > a.scheduled_at
              where a.room_id = rr.room_id
                and a.deleted_at is null
                and a.status <> 'cancelled'
                and a.scheduled_at < $6::timestamptz
                and a.scheduled_at + a.duration_minutes * interval '1 minute' > $5::timestamptz
            ) then 'room_overlap' end,
            case when $7::uuid is not null and exists (
              select 1
              from app.lessons teacher_lesson
              where teacher_lesson.deleted_at is null
                and teacher_lesson.status <> 'cancelled'
                and teacher_lesson.teacher_id = $7
                and teacher_lesson.scheduled_at < $6::timestamptz
                and teacher_lesson.scheduled_at + teacher_lesson.duration_minutes * interval '1 minute' > $5::timestamptz
            ) then 'teacher_overlap' end
          ], null) as conflict_types
        from room_rows rr
        left join lesson_rows lr on lr.room_id = rr.room_id
        group by rr.room_id, rr.branch_id, rr.branch_name, rr.room_name, rr.capacity
        order by rr.branch_name nulls last, rr.room_name asc, rr.room_id asc
      `,
      [
        query.branchId ?? null,
        query.roomId ?? null,
        bounds.dayFrom,
        bounds.dayTo,
        bounds.slotFrom,
        bounds.slotTo,
        query.teacherId ?? null,
        limit,
      ],
    );

    return {
      dateFrom: bounds.dayFrom,
      dateTo: bounds.dayTo,
      slotFrom: bounds.slotFrom,
      slotTo: bounds.slotTo,
      items: result.rows.map((row) => this.toRoomAvailabilityDto(row)),
    };
  }

  async createRoom(actor: ActorContext, dto: UpsertRoomDto) {
    this.policy.assertCanWriteCrm(actor);
    const name = dto.name?.trim();
    if (!name) {
      throw new BadRequestException("Название аудитории обязательно.");
    }

    const result = await this.database.query<RoomRow>(
      `
        with inserted as (
          insert into app.rooms (branch_id, name, capacity)
          values ($1, $2, $3)
          returning id, branch_id, name, capacity, created_at
        )
        select i.id, i.branch_id, b.name as branch_name, i.name, i.capacity, i.created_at
        from inserted i
        left join app.branches b on b.id = i.branch_id and b.deleted_at is null
      `,
      [dto.branchId ?? null, name, dto.capacity ?? null],
    );
    const room = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.room_created",
      entityType: "room",
      entityId: room.id,
    });
    return this.toRoomDto(room);
  }

  async updateRoom(actor: ActorContext, roomId: string, dto: UpsertRoomDto) {
    this.policy.assertCanWriteCrm(actor);
    const name = dto.name?.trim();
    if (dto.name !== undefined && !name) {
      throw new BadRequestException("Название аудитории обязательно.");
    }

    const result = await this.database.query<RoomRow>(
      `
        with updated as (
          update app.rooms
          set branch_id = coalesce($2, branch_id),
            name = coalesce($3, name),
            capacity = coalesce($4, capacity),
            updated_at = now()
          where id = $1 and deleted_at is null
          returning id, branch_id, name, capacity, created_at
        )
        select u.id, u.branch_id, b.name as branch_name, u.name, u.capacity, u.created_at
        from updated u
        left join app.branches b on b.id = u.branch_id and b.deleted_at is null
      `,
      [roomId, dto.branchId ?? null, name ?? null, dto.capacity ?? null],
    );
    const room = result.rows[0];
    if (!room) throw new NotFoundException("Аудитория не найдена.");
    await this.audit.record({
      actor,
      action: "crm.room_updated",
      entityType: "room",
      entityId: room.id,
    });
    return this.toRoomDto(room);
  }

  async deleteRoom(actor: ActorContext, roomId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.rooms
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [roomId],
    );
    const room = result.rows[0];
    if (!room) throw new NotFoundException("Аудитория не найдена.");
    await this.audit.record({
      actor,
      action: "crm.room_deleted",
      entityType: "room",
      entityId: room.id,
    });
    return { success: true };
  }

  async listGroups(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const q = query.q?.trim();
    const result = await this.database.query<GroupRow>(
      `
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.created_at
        from app.groups g
        left join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = g.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = g.room_id and r.deleted_at is null
        where g.deleted_at is null
          and ($1::uuid is null or g.branch_id = $1)
          and (
            $2::text is null
            or lower(coalesce(g.name, '') || ' ' || coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) like lower('%' || $2 || '%')
          )
        order by g.name asc, g.id asc
        limit $3
      `,
      [query.branchId ?? null, q || null, limit],
    );

    return { items: result.rows.map((row) => this.toGroupDto(row)) };
  }

  async createGroup(actor: ActorContext, dto: UpsertGroupDto) {
    this.policy.assertCanWriteCrm(actor);
    const name = this.requiredTrim(dto.name, "Название группы обязательно.");
    const result = await this.database.query<GroupRow>(
      `
        with inserted_group as (
          insert into app.groups (
            teacher_id,
            branch_id,
            room_id,
            name,
            price_per_lesson
          )
          values ($1, $2, $3, $4, $5)
          returning id, teacher_id, branch_id, room_id, name, price_per_lesson, created_at
        )
        select g.id, g.teacher_id, g.branch_id, g.room_id, g.name,
          g.price_per_lesson,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.created_at
        from inserted_group g
        left join app.teachers t on t.id = g.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = g.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = g.room_id and r.deleted_at is null
        limit 1
      `,
      [
        dto.teacherId ?? null,
        dto.branchId ?? null,
        dto.roomId ?? null,
        name,
        dto.pricePerLesson ?? null,
      ],
    );
    const group = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.group_created",
      entityType: "group",
      entityId: group.id,
    });
    return this.toGroupDto(group);
  }

  async listGroupStudents(
    actor: ActorContext,
    groupId: string,
    query: CrmListQuery,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
        from app.group_students gs
        join app.groups g on g.id = gs.group_id and g.deleted_at is null
        join app.students s on s.id = gs.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where gs.group_id = $1
          and gs.left_at is null
        group by s.id, p.id, u.id
        order by p.last_name nulls last, p.first_name nulls last, s.id
        limit $2
      `,
      [groupId, limit],
    );
    return { items: result.rows.map((row) => this.toStudentDto(row)) };
  }

  async addGroupStudent(
    actor: ActorContext,
    groupId: string,
    studentId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      student_id: string;
    }>(
      `
        with target_group as (
          select id from app.groups where id = $1 and deleted_at is null
        ),
        target_student as (
          select id from app.students where id = $2 and deleted_at is null
        )
        insert into app.group_students (group_id, student_id, left_at)
        select target_group.id, target_student.id, null
        from target_group, target_student
        on conflict (group_id, student_id)
        do update set left_at = null
        returning id, student_id
      `,
      [groupId, studentId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Группа или ученик не найдены.");
    await this.audit.record({
      actor,
      action: "crm.group_student_added",
      entityType: "group",
      entityId: groupId,
      metadata: { studentId: row.student_id },
    });
    return { success: true };
  }

  async removeGroupStudent(
    actor: ActorContext,
    groupId: string,
    studentId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.group_students
        set left_at = now()
        where group_id = $1
          and student_id = $2
          and left_at is null
        returning id
      `,
      [groupId, studentId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Ученик не найден в группе.");
    await this.audit.record({
      actor,
      action: "crm.group_student_removed",
      entityType: "group",
      entityId: groupId,
      metadata: { studentId },
    });
    return { success: true };
  }

  async countPhoneReviewQueue(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count from app.phone_review_queue where resolved_at is null`,
    );
    return { count: Number(result.rows[0]?.count ?? 0) };
  }

  async listPhoneReviewQueue(actor: ActorContext, limit = 50) {
    this.policy.assertCanReadOperationalData(actor);
    const capped = Math.min(Math.max(limit, 1), 200);
    const result = await this.database.query<{
      id: string;
      entity_type: string;
      entity_id: string;
      raw_phone: string | null;
      reason: string;
      created_at: string;
    }>(
      `select id, entity_type, entity_id, raw_phone, reason, created_at
         from app.phone_review_queue
        where resolved_at is null
        order by created_at desc
        limit $1`,
      [capped],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        rawPhone: row.raw_phone,
        reason: row.reason,
        createdAt: row.created_at,
      })),
    };
  }

  async listLeadStatuses(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 100, 100);
    const result = await this.database.query<LeadStatusRow>(
      `
        select id, name, color, sort_order, created_at
        from app.lead_statuses
        order by sort_order asc, name asc, id asc
        limit $1
      `,
      [limit],
    );

    return { items: result.rows.map((row) => this.toLeadStatusDto(row)) };
  }

  async listLossReasons(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
      color: string | null;
    }>(
      `select id, name, kind, sort_order, color
         from app.lead_loss_reasons
        where is_active and deleted_at is null
        order by sort_order asc, name asc`,
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        name: row.name,
        kind: row.kind,
        sortOrder: row.sort_order,
        color: row.color,
      })),
    };
  }

  async listLeadSources(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      canonical_name: string;
      display_name: string;
    }>(
      `select id, canonical_name, display_name
         from app.lead_sources
        where is_active and deleted_at is null
        order by display_name asc`,
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        canonicalName: row.canonical_name,
        displayName: row.display_name,
      })),
    };
  }

  async listDisciplines(actor: ActorContext) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ id: string; name: string }>(
      `select id, name
         from app.disciplines
        where is_active and deleted_at is null
        order by name asc`,
    );
    return { items: result.rows.map((row) => ({ id: row.id, name: row.name })) };
  }

  async listBranchDisciplines(actor: ActorContext, branchId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      name: string;
      sort_order: number;
    }>(
      `select bd.id, bd.discipline_id, d.name, bd.sort_order
         from app.branch_disciplines bd
         join app.disciplines d on d.id = bd.discipline_id and d.deleted_at is null and d.is_active
        where bd.branch_id = $1 and bd.deleted_at is null
        order by bd.sort_order asc, d.name asc`,
      [branchId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        disciplineId: row.discipline_id,
        name: row.name,
        sortOrder: row.sort_order,
      })),
    };
  }

  async listHolliHopDisciplines(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listDisciplines();
  }

  async listHolliHopLevels(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listLevels();
  }

  async listHolliHopCategories(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listCategories();
  }

  async listHolliHopLeadStatuses(actor: ActorContext) {
    this.policy.assertCanWriteCrm(actor);
    return this.hollihop.listLeadStatuses();
  }

  async createLeadStatus(actor: ActorContext, dto: UpsertLeadStatusDto) {
    this.policy.assertCanWriteCrm(actor);
    const label = dto.label.trim();
    if (!label) throw new BadRequestException("Название статуса обязательно.");
    const result = await this.database.query<LeadStatusRow>(
      `
        insert into app.lead_statuses (name, color, sort_order)
        values ($1, $2, coalesce($3, 0))
        returning id, name, color, sort_order, created_at
      `,
      [label, dto.color?.trim() || null, dto.sortOrder ?? null],
    );
    const status = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.lead_status_created",
      entityType: "lead",
      entityId: status.id,
      metadata: { key: dto.key?.trim() || null },
    });
    return this.toLeadStatusDto(status);
  }

  async deleteLeadStatus(actor: ActorContext, statusId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        delete from app.lead_statuses
        where id = $1
        returning id
      `,
      [statusId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Статус лида не найден.");
    await this.audit.record({
      actor,
      action: "crm.lead_status_deleted",
      entityType: "lead",
      entityId: row.id,
    });
    return { success: true };
  }

  async createDiscipline(actor: ActorContext, dto: { name: string }) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string; name: string }>(
      `insert into app.disciplines (name) values ($1) returning id, name`,
      [dto.name],
    );
    return { id: result.rows[0].id, name: result.rows[0].name };
  }

  async createLossReason(
    actor: ActorContext,
    dto: { name: string; kind?: "lost" | "paused"; sortOrder?: number },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      name: string;
      kind: string;
      sort_order: number;
    }>(
      `insert into app.lead_loss_reasons (name, kind, sort_order)
       values ($1, $2, $3)
       returning id, name, kind, sort_order`,
      [dto.name, dto.kind ?? "lost", dto.sortOrder ?? 0],
    );
    const row = result.rows[0];
    return { id: row.id, name: row.name, kind: row.kind, sortOrder: row.sort_order };
  }

  async assignBranchDiscipline(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineId: string; sortOrder?: number },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      discipline_id: string;
      sort_order: number;
    }>(
      `insert into app.branch_disciplines (branch_id, discipline_id, sort_order)
       values (
         $1, $2,
         coalesce($3, (select coalesce(max(sort_order) + 1, 0)
                         from app.branch_disciplines
                        where branch_id = $1 and deleted_at is null))
       )
       on conflict (branch_id, discipline_id)
       do update set sort_order = coalesce($3, app.branch_disciplines.sort_order), deleted_at = null
       returning id, discipline_id, sort_order`,
      [branchId, dto.disciplineId, dto.sortOrder ?? null],
    );
    const row = result.rows[0];
    return { id: row.id, disciplineId: row.discipline_id, sortOrder: row.sort_order };
  }

  async reorderBranchDisciplines(
    actor: ActorContext,
    branchId: string,
    dto: { disciplineIds: string[] },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query(
      `update app.branch_disciplines bd
          set sort_order = t.ord - 1
         from unnest($2::uuid[]) with ordinality as t(discipline_id, ord)
        where bd.branch_id = $1
          and bd.discipline_id = t.discipline_id
          and bd.deleted_at is null`,
      [branchId, dto.disciplineIds],
    );
    return { updated: result.rowCount ?? 0 };
  }

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
                -- One teacher running one group class spans many participant
                -- rows at the same time — not a teacher double-booking.
                and (scoped.group_id is null or other_teacher.group_id is null
                     or other_teacher.group_id <> scoped.group_id)
                and other_teacher.scheduled_at < scoped.scheduled_at + scoped.duration_minutes * interval '1 minute'
                and other_teacher.scheduled_at + other_teacher.duration_minutes * interval '1 minute' > scoped.scheduled_at
            ) then 'teacher_overlap' end
          ], null) as conflict_types
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
      ...this.toLessonDto(row),
      conflictTypes: row.conflict_types ?? [],
    }));
    const groups = this.groupScheduleItems(items, groupBy);
    const conflicts = items.flatMap((item) => {
      const conflictTypes = Array.isArray(item.conflictTypes)
        ? item.conflictTypes
        : [];
      return conflictTypes.map((type) => ({
        type,
        lessonId: item.id,
        scheduledAt: item.scheduledAt,
        roomId: item.roomId,
        teacherId: item.teacherId,
      }));
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
    const limit = Math.min(query.limit ?? 100, 200);
    const result = await this.database.query<LessonRow>(
      `
        select l.id, l.student_id, l.group_id, l.lead_id, l.teacher_id, l.branch_id, l.room_id, l.scheduled_at,
          l.duration_minutes, l.status, l.is_trial, l.notes,
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
            $1::text in ('manager', 'admin', 'system_admin')
            or ($1::text = 'teacher' and tp.user_id = $2)
            or ($1::text = 'client' and sp.user_id = $2)
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

    return { items: result.rows.map((row) => this.toLessonDto(row)) };
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
          status, is_trial, notes
        )
        values ($1, $2, $3, $4, $5, $6, $7, coalesce($8, 60), coalesce($9, 'scheduled'), coalesce($10, false), $11)
        returning id, student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, null::uuid as student_user_id, null::uuid as teacher_user_id,
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
      ],
    );
    const lesson = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.lesson_created",
      entityType: "lesson",
      entityId: lesson.id,
    });
    return this.toLessonDto(lesson);
  }

  async updateLesson(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertLessonDto,
  ) {
    await this.assertCanUpdateLesson(actor, lessonId, dto);
    const result = await this.database.query<LessonRow>(
      `
        update app.lessons
        set student_id = coalesce($2, student_id),
          group_id = coalesce($3, group_id),
          lead_id = coalesce($4, lead_id),
          teacher_id = coalesce($5, teacher_id),
          branch_id = coalesce($6, branch_id),
          room_id = coalesce($7, room_id),
          scheduled_at = coalesce($8::timestamptz, scheduled_at),
          duration_minutes = coalesce($9, duration_minutes),
          status = coalesce($10, status),
          is_trial = coalesce($11, is_trial),
          notes = coalesce($12, notes),
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, student_id, group_id, lead_id, teacher_id, branch_id, room_id, scheduled_at, duration_minutes,
          status, is_trial, notes, null::uuid as student_user_id, null::uuid as teacher_user_id,
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
    await this.audit.record({
      actor,
      action: "crm.lesson_updated",
      entityType: "lesson",
      entityId: lesson.id,
    });
    return this.toLessonDto(lesson);
  }

  async deleteLesson(actor: ActorContext, lessonId: string) {
    // Only managers/admins may delete a lesson outright; teachers can update
    // status/notes via updateLesson but not remove a lesson from the schedule.
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.lessons
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
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
    return { success: true };
  }

  async getLessonAttendance(actor: ActorContext, lessonId: string) {
    const lesson = await this.findLessonForAttendance(actor, lessonId);
    const students = await this.listAttendanceStudents(lesson);
    const participations =
      await this.database.query<AttendanceParticipationRow>(
        `
        select student_id, status, pass_reason
        from app.lesson_participation
        where lesson_id = $1
      `,
        [lessonId],
      );
    const byStudentId = new Map(
      participations.rows.map((row) => [row.student_id, row]),
    );

    return {
      lessonId,
      students: students.map((row) => {
        const participation = byStudentId.get(row.student_id);
        return {
          studentId: row.student_id,
          studentName:
            `${row.first_name ?? ""} ${row.last_name ?? ""}`.trim() ||
            "Без имени",
          status: this.toAttendanceStatus(participation?.status),
          passReason: participation?.pass_reason ?? "",
        };
      }),
    };
  }

  async upsertLessonAttendance(
    actor: ActorContext,
    lessonId: string,
    dto: UpsertAttendanceDto,
  ) {
    const lesson = await this.findLessonForAttendance(actor, lessonId);
    const students = await this.listAttendanceStudents(lesson);
    const allowedStudentIds = new Set(students.map((row) => row.student_id));
    const items = dto.items ?? [];
    for (const item of items) {
      if (!allowedStudentIds.has(item.studentId)) {
        throw new BadRequestException("Ученик не относится к этому уроку.");
      }
    }

    for (const item of items) {
      await this.database.query(
        `
          insert into app.lesson_participation (
            lesson_id, student_id, status, pass_reason
          )
          values ($1, $2, $3, $4)
          on conflict (lesson_id, student_id)
          do update set status = excluded.status,
            pass_reason = excluded.pass_reason
        `,
        [
          lessonId,
          item.studentId,
          item.status,
          item.passReason?.trim() || null,
        ],
      );
    }

    await this.database.query(
      `
        update app.lessons
        set status = 'completed', updated_at = now()
        where id = $1 and deleted_at is null
      `,
      [lessonId],
    );
    await this.audit.record({
      actor,
      action: "crm.lesson_attendance_updated",
      entityType: "lesson",
      entityId: lessonId,
    });
    return this.getLessonAttendance(actor, lessonId);
  }

  async listTasks(actor: ActorContext, query: TaskBoardQuery) {
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<TaskRow>(
      `
        select task.id, task.entity_type, task.entity_id, task.assigned_to,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          creator_profile.first_name as creator_first_name,
          creator_profile.last_name as creator_last_name,
          coalesce(student_profile.first_name, teacher_profile.first_name) as entity_first_name,
          coalesce(student_profile.last_name, teacher_profile.last_name) as entity_last_name,
          coalesce(
            nullif(concat_ws(' ', lead.first_name, lead.last_name), ''),
            grp.name
          ) as entity_name,
          coalesce(
            nullif(${this.branchIdExpr('student')}, ''),
            nullif(${this.branchIdExpr('lead')}, ''),
            grp.branch_id::text,
            lesson.branch_id::text
          ) as branch_id,
          branch.name as branch_name,
          task.title, task.description, task.status, task.due_at,
          task.created_by, task.created_at
        from app.tasks task
        left join app.users assigned_user on assigned_user.id = task.assigned_to and assigned_user.deleted_at is null
        left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
        left join app.users creator_user on creator_user.id = task.created_by and creator_user.deleted_at is null
        left join app.profiles creator_profile on creator_profile.user_id = creator_user.id and creator_profile.deleted_at is null
        left join app.students student on task.entity_type = 'student' and student.id = task.entity_id and student.deleted_at is null
        left join app.profiles student_profile on student_profile.id = student.profile_id and student_profile.deleted_at is null
        left join app.teachers teacher on task.entity_type = 'teacher' and teacher.id = task.entity_id and teacher.deleted_at is null
        left join app.profiles teacher_profile on teacher_profile.id = teacher.profile_id and teacher_profile.deleted_at is null
        left join app.leads lead on task.entity_type = 'lead' and lead.id = task.entity_id and lead.deleted_at is null
        left join app.groups grp on task.entity_type = 'group' and grp.id = task.entity_id and grp.deleted_at is null
        left join app.lessons lesson on task.entity_type = 'lesson' and lesson.id = task.entity_id and lesson.deleted_at is null
        left join app.branches branch on branch.id::text = coalesce(
          nullif(${this.branchIdExpr('student')}, ''),
          nullif(${this.branchIdExpr('lead')}, ''),
          grp.branch_id::text,
          lesson.branch_id::text
        ) and branch.deleted_at is null
        where task.deleted_at is null
          and (
            $1::text in ('manager', 'admin', 'system_admin')
            or task.assigned_to = $2
            or exists (
              select 1
              from app.students s
              join app.profiles p on p.id = s.profile_id
              where task.entity_type = 'student'
                and task.entity_id = s.id
                and p.user_id = $2
                and $1::text = 'client'
            )
          )
          and ($4::uuid is null or (task.entity_type = 'student' and task.entity_id = $4))
          and ($5::text is null or task.status = $5)
          and (
            $6::text is null
            or lower(
              coalesce(task.title, '') || ' ' ||
              coalesce(task.description, '') || ' ' ||
              coalesce(student_profile.first_name, '') || ' ' ||
              coalesce(student_profile.last_name, '') || ' ' ||
              coalesce(teacher_profile.first_name, '') || ' ' ||
              coalesce(teacher_profile.last_name, '') || ' ' ||
              coalesce(lead.first_name, '') || ' ' ||
              coalesce(lead.last_name, '') || ' ' ||
              coalesce(grp.name, '')
            ) like lower('%' || $6 || '%')
          )
          and ($7::text is null or task.entity_type::text = $7)
          and ($8::uuid is null or task.entity_id = $8)
          and ($9::uuid is null or task.assigned_to = $9)
          and ($10::uuid is null or task.created_by = $10)
          and (
            $11::uuid is null
            or coalesce(
              nullif(${this.branchIdExpr('student')}, ''),
              nullif(${this.branchIdExpr('lead')}, ''),
              grp.branch_id::text,
              lesson.branch_id::text
            ) = $11::text
          )
          and (
            $12::text is null
            or lower(coalesce(task.title, '') || ' ' || coalesce(task.description, '')) like lower('%' || $12 || '%')
          )
          and (
            $13::text is null
            or lower(coalesce(task.title, '') || ' ' || coalesce(task.description, '')) like lower('%' || $13 || '%')
          )
          and (
            $14::text is null
            or lower(coalesce(task.title, '') || ' ' || coalesce(task.description, '')) like lower('%' || $14 || '%')
          )
          and ($15::timestamptz is null or task.due_at >= $15)
          and ($16::timestamptz is null or task.due_at < $16)
        order by task.due_at nulls last, task.created_at desc
        limit $3
      `,
      [
        actor.role,
        actor.userId,
        limit,
        query.studentId ?? null,
        query.status ?? null,
        query.q ?? null,
        query.entityType ?? null,
        query.entityId ?? null,
        query.assignedTo ?? null,
        query.createdBy ?? null,
        query.branchId ?? null,
        query.priority ?? null,
        query.taskType ?? null,
        query.communicationMethod ?? null,
        query.from ?? null,
        query.to ?? null,
      ],
    );
    return { items: result.rows.map((row) => this.toTaskDto(row)) };
  }

  async listTimeline(actor: ActorContext, query: TimelineQuery) {
    if (!query.entityType || !query.entityId) {
      throw new BadRequestException("Тип и объект timeline обязательны.");
    }
    await this.assertCanReadEntityComments(
      actor,
      query.entityType,
      query.entityId,
    );
    const limit = Math.min(query.limit ?? 80, 200);
    const includeAudit = query.includeAudit === true;
    const result = await this.database.query<TimelineRow>(
      `
        with timeline as (
          select c.id::text as id, 'comment'::text as type,
            'Комментарий'::text as title, c.body as body,
            null::text as status, null::numeric as amount,
            c.author_id as actor_user_id,
            cp.first_name as actor_first_name,
            cp.last_name as actor_last_name,
            c.created_at as occurred_at
          from app.entity_comments c
          left join app.users cu on cu.id = c.author_id and cu.deleted_at is null
          left join app.profiles cp on cp.user_id = cu.id and cp.deleted_at is null
          where c.deleted_at is null
            and c.entity_type::text = $1
            and c.entity_id = $2::uuid

          union all

          select task.id::text as id, 'task'::text as type,
            task.title, task.description as body, task.status,
            null::numeric as amount, task.created_by as actor_user_id,
            tp.first_name as actor_first_name,
            tp.last_name as actor_last_name,
            coalesce(task.due_at, task.created_at) as occurred_at
          from app.tasks task
          left join app.users tu on tu.id = task.created_by and tu.deleted_at is null
          left join app.profiles tp on tp.user_id = tu.id and tp.deleted_at is null
          where task.deleted_at is null
            and task.entity_type::text = $1
            and task.entity_id = $2::uuid

          union all

          select lesson.id::text as id,
            case when lesson.is_trial then 'trial' else 'lesson' end as type,
            case when lesson.is_trial then 'Пробное занятие' else 'Занятие' end as title,
            nullif(trim(coalesce(tp2.first_name, '') || ' ' || coalesce(tp2.last_name, '')), '') as body,
            lesson.status, null::numeric as amount,
            null::uuid as actor_user_id,
            null::text as actor_first_name,
            null::text as actor_last_name,
            lesson.scheduled_at as occurred_at
          from app.lessons lesson
          left join app.teachers teacher on teacher.id = lesson.teacher_id and teacher.deleted_at is null
          left join app.profiles tp2 on tp2.id = teacher.profile_id and tp2.deleted_at is null
          where lesson.deleted_at is null
            and (
              ($1 = 'student' and lesson.student_id = $2::uuid)
              or ($1 = 'lead' and lesson.lead_id = $2::uuid)
              or ($1 = 'teacher' and lesson.teacher_id = $2::uuid)
              or ($1 = 'group' and lesson.group_id = $2::uuid)
              or ($1 = 'lesson' and lesson.id = $2::uuid)
            )

          union all

          select pay.id::text as id, 'payment'::text as type,
            'Платеж'::text as title, pay.notes as body,
            pay.method as status, pay.amount,
            pay.created_by as actor_user_id,
            pp.first_name as actor_first_name,
            pp.last_name as actor_last_name,
            pay.payment_date as occurred_at
          from app.payments pay
          left join app.users pu on pu.id = pay.created_by and pu.deleted_at is null
          left join app.profiles pp on pp.user_id = pu.id and pp.deleted_at is null
          where pay.deleted_at is null
            and $1 = 'student'
            and pay.student_id = $2::uuid

          union all

          select audit.id::text as id, 'audit'::text as type,
            audit.action as title, audit.metadata::text as body,
            audit.entity_type as status, null::numeric as amount,
            audit.actor_user_id,
            ap.first_name as actor_first_name,
            ap.last_name as actor_last_name,
            audit.created_at as occurred_at
          from app.audit_events audit
          left join app.users au on au.id = audit.actor_user_id and au.deleted_at is null
          left join app.profiles ap on ap.user_id = au.id and ap.deleted_at is null
          where $5::boolean = true
            and audit.entity_type = $1
            and audit.entity_id = $2::text
        )
        select *
        from timeline
        where ($3::timestamptz is null or occurred_at >= $3)
          and ($4::timestamptz is null or occurred_at < $4)
        order by occurred_at desc, id desc
        limit $6
      `,
      [
        query.entityType,
        query.entityId,
        query.from ?? null,
        query.to ?? null,
        includeAudit,
        limit,
      ],
    );
    return { items: result.rows.map((row) => this.toTimelineDto(row)) };
  }

  async listComments(actor: ActorContext, query: CommentQuery) {
    if (!query.entityType || !query.entityId) {
      throw new BadRequestException("Тип и объект комментариев обязательны.");
    }
    await this.assertCanReadEntityComments(
      actor,
      query.entityType,
      query.entityId,
    );
    const limit = Math.min(query.limit ?? 50, 100);
    const progressOnly =
      query.progressOnly === true ||
      actor.role === "client" ||
      actor.role === "teacher";
    const result = await this.database.query<CommentRow>(
      `
        select c.id, c.entity_type, c.entity_id, c.author_id,
          p.first_name as author_first_name, p.last_name as author_last_name,
          c.body, c.created_at
        from app.entity_comments c
        left join app.users u on u.id = c.author_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where c.deleted_at is null
          and c.entity_type = $1::app.crm_entity_type
          and c.entity_id = $2
          and ($3::boolean = false or c.body like '[PROGRESS]%')
        order by c.created_at desc, c.id desc
        limit $4
      `,
      [query.entityType, query.entityId, progressOnly, limit],
    );
    return { items: result.rows.map((row) => this.toCommentDto(row)) };
  }

  async createComment(actor: ActorContext, dto: CreateCommentDto) {
    const body = dto.body.trim();
    if (!body)
      throw new BadRequestException("Комментарий не может быть пустым.");
    await this.assertCanCreateEntityComment(actor, dto);
    const storedBody =
      dto.progress === true && !body.startsWith("[PROGRESS]")
        ? `[PROGRESS] ${body}`
        : body;
    const result = await this.database.query<CommentRow>(
      `
        insert into app.entity_comments (
          entity_type, entity_id, author_id, body
        )
        values ($1::app.crm_entity_type, $2, $3, $4)
        returning id, entity_type, entity_id, author_id,
          null::text as author_first_name, null::text as author_last_name,
          body, created_at
      `,
      [dto.entityType, dto.entityId, actor.userId, storedBody],
    );
    const comment = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.comment_created",
      entityType: dto.entityType,
      entityId: dto.entityId,
      metadata: { commentId: comment.id },
    });
    return this.toCommentDto(comment);
  }

  async createTask(actor: ActorContext, dto: UpsertTaskDto) {
    this.policy.assertCanWriteCrm(actor);
    if (!dto.entityType || !dto.entityId || !dto.title) {
      throw new BadRequestException(
        "Тип, объект и название задачи обязательны.",
      );
    }
    const result = await this.database.query<TaskRow>(
      `
        insert into app.tasks (
          entity_type, entity_id, assigned_to, title, description,
          status, due_at, created_by
        )
        values ($1::app.crm_entity_type, $2, $3, $4, $5, coalesce($6, 'open'), $7, $8)
        returning id, entity_type, entity_id, assigned_to, title, description,
          status, due_at, created_by, created_at
      `,
      [
        dto.entityType,
        dto.entityId,
        dto.assignedTo ?? null,
        dto.title.trim(),
        dto.description?.trim() || null,
        dto.status ?? null,
        dto.dueAt ?? null,
        actor.userId,
      ],
    );
    const task = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.task_created",
      entityType: "task",
      entityId: task.id,
    });
    return this.toTaskDto(task);
  }

  async updateTask(actor: ActorContext, taskId: string, dto: UpsertTaskDto) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<TaskRow>(
      `
        update app.tasks
        set entity_type = coalesce($2::app.crm_entity_type, entity_type),
          entity_id = coalesce($3, entity_id),
          assigned_to = coalesce($4, assigned_to),
          title = coalesce($5, title),
          description = coalesce($6, description),
          status = coalesce($7, status),
          due_at = coalesce($8::timestamptz, due_at),
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, entity_type, entity_id, assigned_to, title, description,
          status, due_at, created_by, created_at
      `,
      [
        taskId,
        dto.entityType,
        dto.entityId,
        dto.assignedTo ?? null,
        dto.title?.trim() || null,
        dto.description?.trim() || null,
        dto.status ?? null,
        dto.dueAt ?? null,
      ],
    );
    const task = result.rows[0];
    if (!task) throw new NotFoundException("Задача не найдена.");
    await this.audit.record({
      actor,
      action: "crm.task_updated",
      entityType: "task",
      entityId: task.id,
    });
    return this.toTaskDto(task);
  }

  async listPayments(actor: ActorContext, query: PaymentQuery) {
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<PaymentRow>(
      `
        select pay.id, pay.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name, pay.amount,
          pay.currency, pay.payment_date, pay.method, pay.external_id,
          pay.notes, pay.created_by, pay.created_at
        from app.payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and ($3::uuid is null or pay.student_id = $3)
          and ($4::timestamptz is null or pay.payment_date >= $4)
          and ($5::timestamptz is null or pay.payment_date < $5)
          and (
            $1::text in ('manager', 'admin', 'system_admin')
            or ($1::text = 'client' and p.user_id = $2)
          )
        order by pay.payment_date desc, pay.id desc
        limit $6
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.from ?? null,
        query.to ?? null,
        limit,
      ],
    );
    // Period totals over the FULL filtered set (not just the page), so the UI
    // can show a correct "Итого" instead of summing a truncated page.
    const totals = await this.database.query<{
      total_amount: string;
      total_count: string;
    }>(
      `
        select coalesce(sum(pay.amount), 0)::text as total_amount,
          count(*)::text as total_count
        from app.payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and ($3::uuid is null or pay.student_id = $3)
          and ($4::timestamptz is null or pay.payment_date >= $4)
          and ($5::timestamptz is null or pay.payment_date < $5)
          and (
            $1::text in ('manager', 'admin', 'system_admin')
            or ($1::text = 'client' and p.user_id = $2)
          )
      `,
      [
        actor.role,
        actor.userId,
        query.studentId ?? null,
        query.from ?? null,
        query.to ?? null,
      ],
    );
    return {
      items: result.rows.map((row) => this.toPaymentDto(row)),
      totalAmount: Number(totals.rows[0]?.total_amount ?? "0"),
      totalCount: Number(totals.rows[0]?.total_count ?? "0"),
    };
  }

  async listExpectedPayments(actor: ActorContext, query: CrmListQuery) {
    if (!query.studentId) {
      throw new BadRequestException("studentId обязателен.");
    }
    const student = await this.findStudent(query.studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });

    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<ExpectedPaymentRow>(
      `
        select ep.id, ep.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name,
          ep.amount, ep.due_date, ep.status, ep.description,
          ep.created_at, ep.updated_at
        from app.expected_payments ep
        join app.students s on s.id = ep.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where ep.student_id = $1
        order by ep.due_date desc nulls last, ep.created_at desc, ep.id desc
        limit $2
      `,
      [query.studentId, limit],
    );

    return { items: result.rows.map((row) => this.toExpectedPaymentDto(row)) };
  }

  async listStudentBalances(actor: ActorContext, query: StudentBalanceQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<StudentBalanceRow>(
      `
        with lesson_costs as (
          select
            coalesce(l.student_id, lp.student_id) as student_id,
            sum(
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
            ) as total_cost,
            max(l.updated_at) as updated_at
          from app.lessons l
          left join app.lesson_participation lp on lp.lesson_id = l.id
          join app.students s on s.id = coalesce(l.student_id, lp.student_id)
          left join app.groups g on g.id = l.group_id and g.deleted_at is null
          where l.deleted_at is null
            and l.status in ('completed', 'done')
            and coalesce(l.student_id, lp.student_id) is not null
          group by coalesce(l.student_id, lp.student_id)
        ),
        payment_totals as (
          select
            p.student_id,
            sum(p.amount) as total_paid,
            max(coalesce(p.created_at, p.payment_date)) as updated_at
          from app.payments p
          where p.deleted_at is null
          group by p.student_id
        ),
        balances as (
          select
            s.id as student_id,
            profile.first_name,
            profile.last_name,
            profile.phone,
            coalesce(pay.total_paid, 0) as total_paid,
            coalesce(cost.total_cost, 0) as total_cost,
            coalesce(pay.total_paid, 0) - coalesce(cost.total_cost, 0) as balance,
            greatest(
              coalesce(pay.updated_at, 'epoch'::timestamptz),
              coalesce(cost.updated_at, 'epoch'::timestamptz),
              s.updated_at
            ) as updated_at
          from app.students s
          left join app.profiles profile on profile.id = s.profile_id and profile.deleted_at is null
          left join payment_totals pay on pay.student_id = s.id
          left join lesson_costs cost on cost.student_id = s.id
          where s.deleted_at is null
            and ($1::uuid is null or s.id = $1)
        )
        select *
        from balances
        where ($2::boolean = false or balance < 0)
        order by balance asc, updated_at desc
        limit $3
      `,
      [query.studentId ?? null, query.debtOnly === true, limit],
    );
    return { items: result.rows.map((row) => this.toStudentBalanceDto(row)) };
  }

  async listSubscriptions(actor: ActorContext, query: CrmListQuery) {
    const limit = Math.min(query.limit ?? 20, 100);
    const result = await this.database.query<SubscriptionRow>(
      `
        select sub.id, sub.student_id, p.user_id as student_user_id,
          sub.lessons_total, sub.lessons_used, sub.starts_at, sub.expires_at,
          sub.status, sub.created_at, sub.updated_at
        from app.subscriptions sub
        join app.students s on s.id = sub.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where ($3::uuid is null or sub.student_id = $3)
          and (
            $1::text in ('manager', 'admin', 'system_admin')
            or ($1::text = 'client' and p.user_id = $2)
          )
        order by sub.expires_at desc nulls last, sub.created_at desc, sub.id desc
        limit $4
      `,
      [actor.role, actor.userId, query.studentId ?? null, limit],
    );
    return { items: result.rows.map((row) => this.toSubscriptionDto(row)) };
  }

  async createPayment(actor: ActorContext, dto: CreatePaymentDto) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<PaymentRow>(
      `
        insert into app.payments (
          student_id, amount, currency, payment_date, method,
          external_id, notes, created_by
        )
        values ($1, $2, coalesce($3, 'RUB'), $4, $5, $6, $7, $8)
        returning id, student_id, null::uuid as student_user_id, amount,
          null::text as student_first_name, null::text as student_last_name,
          currency, payment_date, method, external_id, notes, created_by, created_at
      `,
      [
        dto.studentId,
        dto.amount,
        dto.currency ?? null,
        dto.paymentDate,
        dto.method?.trim() || null,
        dto.externalId?.trim() || null,
        dto.notes?.trim() || null,
        actor.userId,
      ],
    );
    const payment = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.payment_created",
      entityType: "student",
      entityId: payment.student_id,
      metadata: { paymentId: payment.id },
    });
    return this.toPaymentDto(payment);
  }

  async listLeadBoard(actor: ActorContext, query: LeadBoardQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 25, 50);
    const filter = this.buildLeadBoardFilter(query);
    const countFilter = this.buildLeadBoardFilter({
      ...query,
      cursor: undefined,
    });
    const statusResult = await this.database.query<LeadStatusRow>(
      `
        select id, name, color, sort_order, created_at
        from app.lead_statuses
        order by sort_order asc, name asc, id asc
      `,
    );
    const countResult = await this.database.query<LeadBoardCountRow>(
      `
        select l.status_id, count(*) as count
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where ${countFilter.where}
        group by l.status_id
      `,
      countFilter.params,
    );

    const leadResult = await this.database.query<LeadBoardRow>(
      `
        with filtered as (
          select l.id, l.status_id, ls.name as status_name, ls.color as status_color,
            ls.sort_order as status_sort_order, l.first_name, l.last_name, l.phone,
            l.email, l.source, l.notes, l.assigned_to, l.custom_data,
            assigned_profile.first_name as assigned_first_name,
            assigned_profile.last_name as assigned_last_name,
            ${this.branchIdExpr('l')} as branch_id,
            b.name as branch_name,
            linked_student.id as linked_student_id,
            (
              select count(*)
              from app.tasks task
              where task.deleted_at is null
                and task.entity_type = 'lead'
                and task.entity_id = l.id
                and task.status in ('open', 'in_progress')
            ) as open_tasks_count,
            (
              select count(*)
              from app.entity_comments comment
              where comment.deleted_at is null
                and comment.entity_type = 'lead'
                and comment.entity_id = l.id
            ) as comments_count,
            (
              select count(*)
              from app.lessons lesson
              where lesson.deleted_at is null
                and lesson.lead_id = l.id
                and lesson.is_trial = true
            ) as trial_lessons_count,
            l.created_by, l.created_at, l.updated_at,
            row_number() over (
              partition by coalesce(l.status_id::text, 'unassigned')
              order by l.created_at desc, l.id desc
            ) as rn
          from app.leads l
          left join app.lead_statuses ls on ls.id = l.status_id
          left join app.users assigned_user on assigned_user.id = l.assigned_to and assigned_user.deleted_at is null
          left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
          left join app.branches b
            on b.id::text = ${this.branchIdExpr('l')}
           and b.deleted_at is null
          left join app.students linked_student
            on linked_student.lead_id = l.id
           and linked_student.deleted_at is null
          where ${filter.where}
        )
        select *
        from filtered
        where rn <= $${filter.params.length + 1}
        order by status_sort_order nulls last, status_name nulls last, created_at desc, id desc
      `,
      [...filter.params, limit],
    );

    const counts = new Map(
      countResult.rows.map((row) => [
        row.status_id ?? "unassigned",
        this.toNumericStat(row.count),
      ]),
    );
    const columns = statusResult.rows.map((status) => ({
      ...this.toLeadStatusDto(status),
      totalCount: counts.get(status.id) ?? 0,
      items: [] as ReturnType<typeof this.toLeadBoardItemDto>[],
    }));

    const byStatus = new Map(columns.map((column) => [column.id, column]));
    for (const row of leadResult.rows) {
      const statusKey = row.status_id ?? "unassigned";
      if (!byStatus.has(statusKey)) {
        const column = {
          id: statusKey,
          name: row.status_name ?? "Без статуса",
          color: row.status_color ?? null,
          sortOrder: row.status_sort_order ?? 9999,
          createdAt: row.created_at,
          totalCount: counts.get(statusKey) ?? 0,
          items: [] as ReturnType<typeof this.toLeadBoardItemDto>[],
        };
        byStatus.set(statusKey, column);
        columns.push(column);
      }
      byStatus.get(statusKey)?.items.push(this.toLeadBoardItemDto(row));
    }

    columns.sort((a, b) => {
      const order = (a.sortOrder ?? 9999) - (b.sortOrder ?? 9999);
      if (order !== 0) return order;
      return String(a.name).localeCompare(String(b.name), "ru");
    });

    const loadedRows = leadResult.rows;
    const oldest = loadedRows[loadedRows.length - 1];
    return {
      columns,
      totalCount: Array.from(counts.values()).reduce(
        (sum, count) => sum + count,
        0,
      ),
      nextCursor: oldest ? this.encodeLeadCursor(oldest) : null,
    };
  }

  async getLeadCard(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const leadResult = await this.database.query<LeadBoardRow>(
      `
        select l.id, l.status_id, ls.name as status_name, ls.color as status_color,
          ls.sort_order as status_sort_order, l.first_name, l.last_name, l.phone,
          l.email, l.source, l.notes, l.assigned_to, l.custom_data,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          ${this.branchIdExpr('l')} as branch_id,
          b.name as branch_name,
          linked_student.id as linked_student_id,
          (
            select count(*)
            from app.tasks task
            where task.deleted_at is null
              and task.entity_type = 'lead'
              and task.entity_id = l.id
              and task.status in ('open', 'in_progress')
          ) as open_tasks_count,
          (
            select count(*)
            from app.entity_comments comment
            where comment.deleted_at is null
              and comment.entity_type = 'lead'
              and comment.entity_id = l.id
          ) as comments_count,
          (
            select count(*)
            from app.lessons lesson
            where lesson.deleted_at is null
              and lesson.lead_id = l.id
              and lesson.is_trial = true
          ) as trial_lessons_count,
          l.created_by, l.created_at, l.updated_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        left join app.users assigned_user on assigned_user.id = l.assigned_to and assigned_user.deleted_at is null
        left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
        left join app.branches b
          on b.id::text = ${this.branchIdExpr('l')}
         and b.deleted_at is null
        left join app.students linked_student
          on linked_student.lead_id = l.id
         and linked_student.deleted_at is null
        where l.id = $1 and l.deleted_at is null
        limit 1
      `,
      [leadId],
    );
    const lead = leadResult.rows[0];
    if (!lead) throw new NotFoundException("Лид не найден.");

    const [students, otherLeads, comments, tasks, trials] = await Promise.all([
      this.listStudentsLinkedToLead(leadId),
      this.listRelatedLeads(lead),
      this.listLeadComments(leadId),
      this.listLeadTasks(leadId),
      this.listLeadTrialLessons(leadId),
    ]);

    const timeline = [
      ...comments.map((comment) => ({
        id: comment.id,
        type: "comment",
        title: "Комментарий",
        body: comment.body,
        status: null,
        occurredAt: comment.createdAt,
      })),
      ...tasks.map((task) => ({
        id: task.id,
        type: "task",
        title: task.title,
        body: task.description,
        status: task.status,
        occurredAt: task.createdAt,
      })),
      ...trials.map((lesson) => ({
        id: lesson.id,
        type: "trial",
        title: "Пробное занятие",
        body: lesson.teacherName || lesson.roomName || null,
        status: lesson.status,
        occurredAt: lesson.scheduledAt,
      })),
    ].sort(
      (a, b) =>
        new Date(String(b.occurredAt)).getTime() -
        new Date(String(a.occurredAt)).getTime(),
    );

    return {
      lead: this.toLeadBoardItemDto(lead),
      linkedStudents: students,
      otherLeads,
      comments,
      tasks,
      trials,
      timeline,
    };
  }

  async listLeadStatusHistory(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      old_status: string | null;
      new_status: string | null;
      old_owner_id: string | null;
      new_owner_id: string | null;
      changed_by: string | null;
      changed_at: string;
      reason_id: string | null;
      comment: string | null;
    }>(
      `select h.id,
              os.name as old_status,
              ns.name as new_status,
              h.old_owner_id, h.new_owner_id, h.changed_by, h.changed_at,
              h.reason_id, h.comment
         from app.lead_status_history h
         left join app.lead_statuses os on os.id = h.old_status_id
         left join app.lead_statuses ns on ns.id = h.new_status_id
        where h.lead_id = $1
        order by h.changed_at desc`,
      [leadId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        oldStatus: row.old_status,
        newStatus: row.new_status,
        oldOwnerId: row.old_owner_id,
        newOwnerId: row.new_owner_id,
        changedBy: row.changed_by,
        changedAt: row.changed_at,
        reasonId: row.reason_id,
        comment: row.comment,
      })),
    };
  }

  async listLeads(actor: ActorContext, query: CrmListQuery) {
    this.policy.assertCanWriteCrm(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const q = query.q?.trim();
    const result = await this.database.query<LeadRow>(
      `
        select l.id, l.status_id, ls.name as status_name, l.first_name,
          l.last_name, l.phone, l.email, l.source, l.notes, l.assigned_to, l.custom_data,
          l.created_by, l.created_at, l.updated_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where l.deleted_at is null
          and (
            $1::text is null
            or lower(coalesce(l.first_name, '') || ' ' || coalesce(l.last_name, '') || ' ' || coalesce(l.email, '') || ' ' || coalesce(l.phone, '')) like lower('%' || $1 || '%')
          )
        order by l.created_at desc, l.id desc
        limit $2
      `,
      [q || null, limit],
    );
    return { items: result.rows.map((row) => this.toLeadDto(row)) };
  }

  // Resolve the messenger user behind a lead so staff can jump straight into a
  // chat with them. Prefers an explicit user_crm_link, then falls back to a
  // client user whose profile phone matches the lead's phone.
  async resolveLeadChatUser(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const lead = await this.database.query<{
      id: string;
      name: string;
      phone: string | null;
    }>(
      `
        select id,
          coalesce(
            nullif(btrim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''),
            'Лид'
          ) as name,
          phone
        from app.leads
        where id = $1 and deleted_at is null
        limit 1
      `,
      [leadId],
    );
    if (!lead.rows[0]) throw new NotFoundException("Лид не найден.");

    const link = await this.database.query<{ user_id: string }>(
      `
        select user_id
        from app.user_crm_links
        where entity_type = 'lead' and entity_id = $1 and deleted_at is null
        order by confirmed_at desc nulls last, created_at desc
        limit 1
      `,
      [leadId],
    );
    if (link.rows[0]) {
      return { userId: link.rows[0].user_id, name: lead.rows[0].name };
    }

    const phone = this.normalizeContactPhone(lead.rows[0].phone);
    if (phone) {
      const byPhone = await this.database.query<{ user_id: string }>(
        `
          select p.user_id
          from app.profiles p
          join app.users u on u.id = p.user_id and u.deleted_at is null
          where p.deleted_at is null
            and ${normalizedPhoneExpr('p.phone')} = $1
            and u.role = 'client'
          order by u.created_at desc
          limit 1
        `,
        [phone],
      );
      if (byPhone.rows[0]) {
        return { userId: byPhone.rows[0].user_id, name: lead.rows[0].name };
      }
    }
    return { userId: null, name: lead.rows[0].name };
  }

  // Reverse lookup: given a messenger user (a chat partner), find the CRM
  // lead/student they map to so staff can open the right card from a chat.
  async resolveContactForUser(actor: ActorContext, userId: string) {
    this.policy.assertCanWriteCrm(actor);
    const links = await this.database.query<{
      entity_type: string;
      entity_id: string;
    }>(
      `
        select entity_type, entity_id
        from app.user_crm_links
        where user_id = $1 and deleted_at is null
      `,
      [userId],
    );
    let studentId: string | null = null;
    let leadId: string | null = null;
    for (const row of links.rows) {
      if (row.entity_type === "student") studentId ??= row.entity_id;
      if (row.entity_type === "lead") leadId ??= row.entity_id;
    }
    // Students created in-app own their user directly (their profile.user_id),
    // which may not have an explicit crm-link row.
    if (!studentId) {
      const owned = await this.database.query<{ id: string }>(
        `
          select s.id
          from app.students s
          join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          where p.user_id = $1 and s.deleted_at is null
          order by s.created_at desc
          limit 1
        `,
        [userId],
      );
      studentId = owned.rows[0]?.id ?? null;
    }
    return { studentId, leadId };
  }

  private normalizeContactPhone(phone: string | null | undefined): string | null {
    return normalizePhoneRu(phone).canonical;
  }

  // Save a chat partner (an existing messenger user) into the CRM as a lead or
  // student, linking the CRM entity back to that user. Idempotent: if the user
  // is already linked to / backed by such an entity, returns it instead of
  // creating a duplicate.
  async saveContactFromChat(
    actor: ActorContext,
    dto: { userId: string; as: "lead" | "student" },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const profileResult = await this.database.query<{
      profile_id: string;
      user_id: string;
      first_name: string | null;
      last_name: string | null;
      phone: string | null;
    }>(
      `
        select p.id as profile_id, p.user_id, p.first_name, p.last_name, p.phone
        from app.profiles p
        join app.users u on u.id = p.user_id and u.deleted_at is null
        where p.user_id = $1 and p.deleted_at is null
        limit 1
      `,
      [dto.userId],
    );
    const profile = profileResult.rows[0];
    if (!profile) throw new NotFoundException("Пользователь чата не найден.");

    const firstName = (profile.first_name ?? "").trim() || "Без имени";
    const lastName = (profile.last_name ?? "").trim() || null;
    const phone = (profile.phone ?? "").trim() || null;
    const matchedPhone = this.normalizeContactPhone(phone);

    if (dto.as === "lead") {
      const existing = await this.database.query<{ entity_id: string }>(
        `
          select entity_id from app.user_crm_links
          where user_id = $1 and entity_type = 'lead' and deleted_at is null
          limit 1
        `,
        [profile.user_id],
      );
      if (existing.rows[0]) {
        return { leadId: existing.rows[0].entity_id, created: false };
      }
      const leadId = await this.database.transaction(async (client) => {
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.leads (first_name, last_name, phone, source, created_by)
            values ($1, $2, $3, 'Чат', $4)
            returning id
          `,
          [firstName, lastName, phone, actor.userId],
        );
        const id = inserted.rows[0].id;
        await client.query(
          `
            insert into app.user_crm_links
              (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
            values ($1, 'lead', $2, $3, 'manual_phone', $4, now())
            on conflict do nothing
          `,
          [profile.user_id, id, matchedPhone, actor.userId],
        );
        return id;
      });
      await this.audit.record({
        actor,
        action: "crm.lead_created",
        entityType: "lead",
        entityId: leadId,
        metadata: { fromChat: true, userId: profile.user_id },
      });
      return { leadId, created: true };
    }

    // as === "student": reuse the partner's existing profile (do not mint a new
    // user); dedup by profile so a client isn't doubled.
    const existingStudent = await this.database.query<{ id: string }>(
      `
        select id from app.students
        where profile_id = $1 and deleted_at is null
        limit 1
      `,
      [profile.profile_id],
    );
    if (existingStudent.rows[0]) {
      return { studentId: existingStudent.rows[0].id, created: false };
    }
    const studentId = await this.database.transaction(async (client) => {
      const inserted = await client.query<{ id: string }>(
        `
          insert into app.students (profile_id, status)
          values ($1, 'active')
          returning id
        `,
        [profile.profile_id],
      );
      const id = inserted.rows[0].id;
      await client.query(
        `
          insert into app.user_crm_links
            (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
          values ($1, 'student', $2, $3, 'manual_phone', $4, now())
          on conflict do nothing
        `,
        [profile.user_id, id, matchedPhone, actor.userId],
      );
      return id;
    });
    await this.audit.record({
      actor,
      action: "crm.student_created",
      entityType: "student",
      entityId: studentId,
      metadata: { fromChat: true, userId: profile.user_id },
    });
    return { studentId, created: true };
  }

  async createLead(actor: ActorContext, dto: UpsertLeadDto) {
    this.policy.assertCanWriteCrm(actor);
    const branchId = this.extractBranchId(dto.customDataPatch);
    const result = await this.database.query<LeadRow>(
      `
        insert into app.leads (
          status_id, first_name, last_name, phone, email,
          source, notes, assigned_to, custom_data, created_by, branch_id
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        returning id, status_id, null::text as status_name, first_name,
          last_name, phone, email, source, notes, assigned_to,
          custom_data, created_by, created_at, updated_at
      `,
      [
        dto.statusId ?? null,
        dto.firstName?.trim() || null,
        dto.lastName?.trim() || null,
        dto.phone?.trim() || null,
        dto.email?.trim().toLowerCase() || null,
        dto.source?.trim() || null,
        dto.notes?.trim() || null,
        dto.assignedTo ?? null,
        this.sanitizeJsonObject(dto.customDataPatch),
        actor.userId,
        branchId,
      ],
    );
    const lead = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: lead.id,
    });
    return this.toLeadDto(lead);
  }

  async updateLead(actor: ActorContext, leadId: string, dto: UpsertLeadDto) {
    this.policy.assertCanWriteCrm(actor);
    const branchId = this.extractBranchId(dto.customDataPatch);
    const beforeRes = await this.database.query<{
      status_id: string | null;
      assigned_to: string | null;
      branch_id: string | null;
    }>(
      `select status_id, assigned_to, branch_id from app.leads where id = $1 and deleted_at is null`,
      [leadId],
    );
    const before = beforeRes.rows[0] ?? null;
    const result = await this.database.query<LeadRow>(
      `
        update app.leads
        set status_id = case when $11::boolean then null
                             else coalesce($2, status_id) end,
          first_name = coalesce($3, first_name),
          last_name = coalesce($4, last_name),
          phone = coalesce($5, phone),
          email = coalesce($6, email),
          source = coalesce($7, source),
          notes = coalesce($8, notes),
          assigned_to = coalesce($9, assigned_to),
          custom_data = custom_data || $10::jsonb,
          branch_id = coalesce($12::uuid, branch_id),
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, status_id, null::text as status_name, first_name,
          last_name, phone, email, source, notes, assigned_to,
          custom_data, created_by, created_at, updated_at
      `,
      [
        leadId,
        dto.statusId ?? null,
        dto.firstName?.trim() || null,
        dto.lastName?.trim() || null,
        dto.phone?.trim() || null,
        dto.email?.trim().toLowerCase() || null,
        dto.source?.trim() || null,
        dto.notes?.trim() || null,
        dto.assignedTo ?? null,
        this.sanitizeJsonObject(dto.customDataPatch),
        dto.clearStatus ?? false,
        branchId,
      ],
    );
    const lead = result.rows[0];
    if (!lead) throw new NotFoundException("Лид не найден.");
    await this.audit.record({
      actor,
      action: "crm.lead_updated",
      entityType: "lead",
      entityId: lead.id,
    });
    if (
      before &&
      (before.status_id !== lead.status_id || before.assigned_to !== lead.assigned_to)
    ) {
      await this.database.query(
        `insert into app.lead_status_history
           (lead_id, old_status_id, new_status_id, old_owner_id, new_owner_id,
            changed_by, reason_id, comment, branch_id, source_snapshot)
         values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
        [
          leadId,
          before.status_id,
          lead.status_id,
          before.assigned_to,
          lead.assigned_to,
          actor.userId,
          dto.reasonId ?? null,
          dto.statusComment ?? null,
          branchId ?? before.branch_id,
          lead.source,
        ],
      );
    }
    return this.toLeadDto(lead);
  }

  async deleteLead(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.leads
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [leadId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Лид не найден.");
    await this.audit.record({
      actor,
      action: "crm.lead_deleted",
      entityType: "lead",
      entityId: row.id,
    });
    return { success: true };
  }

  // Transition-safe branch read: prefer the real branch_id column, fall back to
  // the legacy custom_data keys. Returns text to preserve the existing
  // text-based comparison semantics (no jsonb::uuid casts).
  private branchIdExpr(alias: string): string {
    return `coalesce(${alias}.branch_id::text, ${alias}.custom_data->>'branchId', ${alias}.custom_data->>'branch_id')`;
  }

  private static readonly UUID_RE =
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

  // Pull a valid branch UUID out of a customDataPatch (branchId or branch_id),
  // for dual-writing the real column alongside the legacy json.
  private extractBranchId(
    patch: Record<string, unknown> | undefined | null,
  ): string | null {
    const raw = patch?.["branchId"] ?? patch?.["branch_id"];
    return typeof raw === "string" && CrmService.UUID_RE.test(raw) ? raw : null;
  }

  private buildStudentSearchFilter(
    actor: ActorContext,
    query: StudentSearchQuery,
  ) {
    const params: unknown[] = [];
    const filters = ["s.deleted_at is null"];
    const add = (value: unknown) => {
      params.push(value);
      return `$${params.length}`;
    };
    const role = add(actor.role);
    const userId = add(actor.userId);
    filters.push(`
      (
        ${role}::text in ('manager', 'admin', 'system_admin')
        or (${role}::text = 'teacher' and tp.user_id = ${userId})
      )
    `);

    const q = query.q?.trim();
    if (q) {
      const p = add(q);
      filters.push(
        `lower(concat_ws(' ', p.first_name, p.last_name, u.email, p.phone, s.custom_data::text)) like lower('%' || ${p}::text || '%')`,
      );
    }
    if (query.status?.trim()) {
      filters.push(`s.status = ${add(query.status.trim())}::text`);
    }
    if (query.branchId) {
      const p = add(query.branchId);
      filters.push(
        `${this.branchIdExpr('s')} = ${p}::text`,
      );
    }
    if (query.groupId) {
      filters.push(`
        exists (
          select 1
          from app.group_students group_filter
          where group_filter.student_id = s.id
            and group_filter.group_id = ${add(query.groupId)}::uuid
            and group_filter.left_at is null
        )
      `);
    }
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(s.custom_data->>'discipline', s.custom_data->>'disciplineName', s.custom_data->>'discipline_name')",
      query.discipline,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(s.custom_data->>'level', s.custom_data->>'levelName', s.custom_data->>'level_name')",
      query.level,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(s.custom_data->>'category', s.custom_data->>'categoryName', s.custom_data->>'category_name', s.custom_data->>'maturity')",
      query.category,
    );
    if (query.from) {
      filters.push(`s.created_at >= ${add(query.from)}::timestamptz`);
    }
    if (query.to) {
      filters.push(`s.created_at < ${add(query.to)}::timestamptz`);
    }
    if (query.linkedUser !== undefined) {
      const condition =
        "(exists (select 1 from app.user_crm_links link_filter where link_filter.entity_type = 'student' and link_filter.entity_id = s.id and link_filter.deleted_at is null) or u.is_app_account = true)";
      filters.push(query.linkedUser ? condition : `not ${condition}`);
    }
    if (query.noEmail === true) {
      filters.push(`coalesce(nullif(btrim(u.email), ''), '') = ''`);
    }
    if (query.noOpenTasks === true) {
      filters.push(`
        not exists (
          select 1
          from app.tasks task_filter
          where task_filter.entity_type = 'student'
            and task_filter.entity_id = s.id
            and task_filter.deleted_at is null
            and task_filter.status in ('open', 'in_progress')
        )
      `);
    }
    return { where: filters.join("\n          and "), params };
  }

  private async listUserCrmLinks(entityType: string, entityId: string) {
    const result = await this.database.query<{
      id: string;
      user_id: string;
      email: string | null;
      phone: string | null;
      link_source: string;
      confirmed_at: Date | string | null;
      created_at: Date | string;
    }>(
      `
        select link.id, link.user_id, u.email, u.phone, link.link_source,
          link.confirmed_at, link.created_at
        from app.user_crm_links link
        join app.users u on u.id = link.user_id and u.deleted_at is null
        where link.deleted_at is null
          and link.entity_type = $1::app.crm_entity_type
          and link.entity_id = $2
        order by link.created_at desc, link.id desc
      `,
      [entityType, entityId],
    );
    return result.rows.map((row) => ({
      id: row.id,
      userId: row.user_id,
      email: row.email,
      phone: row.phone,
      linkSource: row.link_source,
      confirmedAt: row.confirmed_at,
      createdAt: row.created_at,
    }));
  }

  private async attachDuplicateCandidate(candidate: DuplicateCandidateRow) {
    const leadId =
      candidate.entity_type_a === "lead"
        ? candidate.entity_id_a
        : candidate.entity_type_b === "lead"
          ? candidate.entity_id_b
          : null;
    const studentId =
      candidate.entity_type_a === "student"
        ? candidate.entity_id_a
        : candidate.entity_type_b === "student"
          ? candidate.entity_id_b
          : null;
    if (!leadId || !studentId) {
      throw new BadRequestException("Прикрепить можно только пару лид-ученик.");
    }
    const result = await this.database.query<{ id: string }>(
      `
        update app.students
        set lead_id = $2, updated_at = now()
        where id = $1
          and deleted_at is null
          and (lead_id is null or lead_id = $2)
        returning id
      `,
      [studentId, leadId],
    );
    if (!result.rows[0]) {
      throw new ConflictException("Ученик уже связан с другим лидом.");
    }
  }

  private buildLeadBoardFilter(query: LeadBoardQuery) {
    const params: unknown[] = [];
    const filters = ["l.deleted_at is null"];
    const add = (value: unknown) => {
      params.push(value);
      return `$${params.length}`;
    };
    const q = query.q?.trim();
    if (q) {
      const p = add(q);
      filters.push(
        `lower(concat_ws(' ', l.first_name, l.last_name, l.email, l.phone, l.source, l.notes, l.custom_data::text)) like lower('%' || ${p}::text || '%')`,
      );
    }
    if (query.statusId) {
      filters.push(`l.status_id = ${add(query.statusId)}::uuid`);
    }
    if (query.assignedTo) {
      filters.push(`l.assigned_to = ${add(query.assignedTo)}::uuid`);
    }
    if (query.branchId) {
      const p = add(query.branchId);
      filters.push(
        `${this.branchIdExpr('l')} = ${p}::text`,
      );
    }
    this.addLeadTextFilter(filters, add, "l.source", query.source);
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'discipline', l.custom_data->>'disciplineName', l.custom_data->>'discipline_name')",
      query.discipline,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'level', l.custom_data->>'levelName', l.custom_data->>'level_name')",
      query.level,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'category', l.custom_data->>'categoryName', l.custom_data->>'category_name', l.custom_data->>'maturity')",
      query.category,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'requestType', l.custom_data->>'request_type', l.custom_data->>'type')",
      query.requestType,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'goal', l.custom_data->>'learningGoal', l.custom_data->>'learning_goal')",
      query.goal,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'gender', l.custom_data->>'sex')",
      query.gender,
    );
    this.addLeadTextFilter(
      filters,
      add,
      "coalesce(l.custom_data->>'preferredSchedule', l.custom_data->>'preferred_schedule')",
      query.preferredSchedule,
      true,
    );
    if (query.from) {
      filters.push(`l.created_at >= ${add(query.from)}::timestamptz`);
    }
    if (query.to) {
      filters.push(`l.created_at < ${add(query.to)}::timestamptz`);
    }
    if (query.openTasks === true) {
      filters.push(`
        exists (
          select 1
          from app.tasks open_task
          where open_task.deleted_at is null
            and open_task.entity_type = 'lead'
            and open_task.entity_id = l.id
            and open_task.status in ('open', 'in_progress')
        )
      `);
    }
    const cursor = this.decodeLeadCursor(query.cursor);
    if (cursor) {
      const createdAt = add(cursor.createdAt);
      const id = add(cursor.id);
      filters.push(
        `(l.created_at, l.id) < (${createdAt}::timestamptz, ${id}::uuid)`,
      );
    }

    const quick = query.quick ?? "all";
    if (quick !== "all") {
      const groupExpr =
        "lower(coalesce(l.custom_data->>'statusGroup', l.custom_data->>'status_group', ''))";
      const statusExpr = "lower(coalesce(ls.name, ''))";
      const processed = `${groupExpr} = 'processed' or ${statusExpr} like '%обработ%' or ${statusExpr} like '%закрыт%' or ${statusExpr} like '%отказ%' or ${statusExpr} like '%processed%'`;
      const deferred = `${groupExpr} = 'deferred' or ${statusExpr} like '%отлож%' or ${statusExpr} like '%перезвон%' or ${statusExpr} like '%defer%'`;
      if (quick === "processed") {
        filters.push(`(${processed})`);
      } else if (quick === "deferred") {
        filters.push(`(${deferred})`);
      } else {
        filters.push(`not (${processed}) and not (${deferred})`);
      }
    }

    return { where: filters.join("\n          and "), params };
  }

  private addLeadTextFilter(
    filters: string[],
    add: (value: unknown) => string,
    expression: string,
    value: string | undefined,
    fuzzy = false,
  ) {
    const trimmed = value?.trim();
    if (!trimmed) return;
    const p = add(trimmed);
    filters.push(
      fuzzy
        ? `lower(${expression}) like lower('%' || ${p}::text || '%')`
        : `lower(${expression}) = lower(${p}::text)`,
    );
  }

  private encodeLeadCursor(row: { created_at: Date | string; id: string }) {
    const createdAt =
      row.created_at instanceof Date
        ? row.created_at.toISOString()
        : String(row.created_at);
    return `${createdAt}|${row.id}`;
  }

  private decodeLeadCursor(cursor: string | undefined) {
    if (!cursor) return null;
    const [createdAt, id] = cursor.split("|");
    if (!createdAt || !id || Number.isNaN(Date.parse(createdAt))) return null;
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
        id,
      )
    ) {
      return null;
    }
    return { createdAt, id };
  }

  private async listStudentsLinkedToLead(leadId: string) {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone,
          s.created_at, '{}'::uuid[] as teacher_user_ids
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where s.deleted_at is null and s.lead_id = $1
        order by s.created_at desc, s.id desc
        limit 20
      `,
      [leadId],
    );
    return result.rows.map((row) => this.toStudentDto(row));
  }

  private async listRelatedLeads(lead: LeadRow) {
    if (!lead.phone && !lead.email) return [];
    const result = await this.database.query<LeadRow>(
      `
        select l.id, l.status_id, ls.name as status_name, l.first_name,
          l.last_name, l.phone, l.email, l.source, l.notes, l.assigned_to,
          l.custom_data, l.created_by, l.created_at, l.updated_at
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where l.deleted_at is null
          and l.id <> $1
          and (
            ($2::text is not null and l.phone = $2)
            or ($3::text is not null and lower(l.email) = lower($3))
          )
        order by l.created_at desc, l.id desc
        limit 10
      `,
      [lead.id, lead.phone, lead.email],
    );
    return result.rows.map((row) => this.toLeadDto(row));
  }

  private async listLeadComments(leadId: string) {
    const result = await this.database.query<CommentRow>(
      `
        select c.id, c.entity_type, c.entity_id, c.author_id,
          p.first_name as author_first_name, p.last_name as author_last_name,
          c.body, c.created_at
        from app.entity_comments c
        left join app.users u on u.id = c.author_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where c.deleted_at is null
          and c.entity_type = 'lead'
          and c.entity_id = $1
        order by c.created_at desc, c.id desc
        limit 50
      `,
      [leadId],
    );
    return result.rows.map((row) => this.toCommentDto(row));
  }

  private async listLeadTasks(leadId: string) {
    const result = await this.database.query<TaskRow>(
      `
        select task.id, task.entity_type, task.entity_id, task.assigned_to,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          null::text as entity_first_name,
          null::text as entity_last_name,
          null::text as entity_name,
          task.title, task.description, task.status, task.due_at,
          task.created_by, task.created_at
        from app.tasks task
        left join app.users assigned_user on assigned_user.id = task.assigned_to and assigned_user.deleted_at is null
        left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
        where task.deleted_at is null
          and task.entity_type = 'lead'
          and task.entity_id = $1
        order by task.due_at nulls last, task.created_at desc, task.id desc
        limit 50
      `,
      [leadId],
    );
    return result.rows.map((row) => this.toTaskDto(row));
  }

  private async listLeadTrialLessons(leadId: string) {
    const result = await this.database.query<LessonRow>(
      `
        select l.id, l.student_id, l.group_id, l.lead_id, l.teacher_id, l.branch_id, l.room_id, l.scheduled_at,
          l.duration_minutes, l.status, l.is_trial, l.notes,
          null::uuid as student_user_id, tp.user_id as teacher_user_id,
          null::text as student_name,
          trim(coalesce(tp.first_name, '') || ' ' || coalesce(tp.last_name, '')) as teacher_name,
          b.name as branch_name,
          r.name as room_name,
          g.name as group_name,
          g.price_per_lesson as group_price_per_lesson
        from app.lessons l
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b on b.id = l.branch_id and b.deleted_at is null
        left join app.rooms r on r.id = l.room_id and r.deleted_at is null
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        where l.deleted_at is null
          and l.lead_id = $1
          and l.is_trial = true
        order by l.scheduled_at desc, l.id desc
        limit 20
      `,
      [leadId],
    );
    return result.rows.map((row) => this.toLessonDto(row));
  }

  private async listClientStudents(userId: string): Promise<StudentRow[]> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          '{}'::uuid[] as teacher_user_ids
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where s.deleted_at is null and p.user_id = $1
        order by s.created_at desc
      `,
      [userId],
    );
    return result.rows;
  }

  private async findStudent(
    studentId: string,
  ): Promise<StudentRow | undefined> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where s.id = $1 and s.deleted_at is null
        group by s.id, p.id, u.id
        limit 1
      `,
      [studentId],
    );
    return result.rows[0];
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

  private async findLessonForAttendance(
    actor: ActorContext,
    lessonId: string,
  ): Promise<LessonAccessRow> {
    const result = await this.database.query<LessonAccessRow>(
      `
        select l.id, l.student_id, l.group_id, tp.user_id as teacher_user_id
        from app.lessons l
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        where l.id = $1 and l.deleted_at is null
        limit 1
      `,
      [lessonId],
    );
    const lesson = result.rows[0];
    if (!lesson) throw new NotFoundException("Урок не найден.");
    if (isManagerOrAdminRole(actor.role)) return lesson;
    if (actor.role === "teacher" && lesson.teacher_user_id === actor.userId) {
      return lesson;
    }
    throw new NotFoundException("Урок не найден.");
  }

  private async listAttendanceStudents(
    lesson: LessonAccessRow,
  ): Promise<AttendanceStudentRow[]> {
    const result = await this.database.query<AttendanceStudentRow>(
      `
        select s.id as student_id, p.first_name, p.last_name
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where s.deleted_at is null
          and (
            ($1::uuid is not null and s.id = $1)
            or exists (
              select 1
              from app.group_students gs
              where gs.student_id = s.id
                and gs.left_at is null
                and gs.group_id = $2
            )
          )
        order by p.last_name nulls last, p.first_name nulls last, s.id
      `,
      [lesson.student_id, lesson.group_id],
    );
    return result.rows;
  }

  private toAttendanceStatus(status: string | undefined): "present" | "absent" {
    if (status === "absent" || status === "missed" || status === "no_show") {
      return "absent";
    }
    return "present";
  }

  private async assertCanReadEntityComments(
    actor: ActorContext,
    entityType: string,
    entityId: string,
  ) {
    if (entityType === "student") {
      const student = await this.findStudent(entityId);
      if (!student) throw new NotFoundException("Ученик не найден.");
      this.policy.assertCanReadStudent(actor, {
        profileUserId: student.profile_user_id,
        teacherUserIds: student.teacher_user_ids ?? [],
      });
      return;
    }

    this.policy.assertCanWriteCrm(actor);
  }

  private async assertCanCreateEntityComment(
    actor: ActorContext,
    dto: CreateCommentDto,
  ) {
    if (isManagerOrAdminRole(actor.role)) {
      this.policy.assertCanWriteCrm(actor);
      await this.assertEntityExistsForComment(dto.entityType, dto.entityId);
      return;
    }

    if (
      actor.role === "teacher" &&
      dto.entityType === "student" &&
      dto.progress === true
    ) {
      await this.assertCanReadEntityComments(
        actor,
        dto.entityType,
        dto.entityId,
      );
      return;
    }

    throw new ForbiddenException("Недостаточно прав для комментария.");
  }

  private async assertEntityExistsForComment(
    entityType: string,
    entityId: string,
  ) {
    if (entityType === "student") {
      const student = await this.findStudent(entityId);
      if (!student) throw new NotFoundException("Ученик не найден.");
      return;
    }

    const tableByType: Record<string, string> = {
      teacher: "teachers",
      group: "groups",
      lesson: "lessons",
      lead: "leads",
      profile: "profiles",
    };
    const table = tableByType[entityType];
    if (!table)
      throw new BadRequestException("Неподдерживаемый тип комментария.");
    const result = await this.database.query<{ exists: boolean }>(
      `select exists(select 1 from app.${table} where id = $1 and deleted_at is null) as exists`,
      [entityId],
    );
    if (!result.rows[0]?.exists) {
      throw new NotFoundException("Объект комментария не найден.");
    }
  }

  private sanitizeJsonObject(value: unknown): Record<string, unknown> {
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).filter(
        ([, entryValue]) => entryValue !== undefined,
      ),
    );
  }

  private requiredTrim(value: string | undefined, message: string): string {
    const trimmed = value?.trim();
    if (!trimmed) throw new BadRequestException(message);
    return trimmed;
  }

  private rethrowCreatePersonError(error: unknown): never {
    if (
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      (error as { code?: string }).code === "23505"
    ) {
      throw new BadRequestException(
        "Пользователь с таким email уже существует.",
      );
    }
    throw error;
  }

  private trimOptional(value: string | undefined): string | null {
    if (value === undefined) return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private isDeliverableEmail(value: string): boolean {
    const email = value.trim().toLowerCase();
    return (
      email.length > 0 &&
      !email.endsWith("@local.magicmusiccrm.invalid") &&
      !email.endsWith("@migration.invalid")
    );
  }

  private hashEmail(value: string): string {
    return createHash("sha256").update(value.toLowerCase()).digest("hex");
  }

  private toStudentDto(row: StudentRow) {
    return {
      id: row.id,
      leadId: row.lead_id,
      status: row.status,
      customData: row.custom_data ?? {},
      profileId: row.profile_id,
      profileUserId: row.profile_user_id,
      firstName: row.first_name,
      lastName: row.last_name,
      email: row.email,
      phone: row.phone,
      teacherUserIds: row.teacher_user_ids ?? [],
      createdAt: row.created_at,
    };
  }

  private toStudentSearchDto(row: StudentSearchRow) {
    return {
      ...this.toStudentDto(row),
      branchId: row.branch_id,
      branchName: row.branch_name,
      groupsCount: this.toNumericStat(row.groups_count),
      openTasksCount: this.toNumericStat(row.open_tasks_count),
      lessonsCount: this.toNumericStat(row.lessons_count),
      paymentsTotal: this.toNumericStat(row.payments_total),
      linkedUserId: row.linked_user_id,
      linkedUserEmail: row.linked_user_email,
      isAppAccount: row.is_app_account ?? false,
    };
  }

  private toTeacherDto(row: TeacherRow) {
    const teacher: Record<string, unknown> = {
      id: row.id,
      status: row.status,
      specialization: row.specialization,
      profileId: row.profile_id,
      profileUserId: row.profile_user_id,
      firstName: row.first_name,
      lastName: row.last_name,
      email: row.email,
      phone: row.phone,
    };
    if (row.custom_data !== undefined) {
      teacher.customData = row.custom_data ?? {};
    }
    if (row.app_role !== undefined) {
      teacher.appRole = row.app_role;
    }
    if (row.is_app_account !== undefined) {
      teacher.isAppAccount = row.is_app_account ?? false;
    }
    if (row.branches !== undefined) {
      teacher.branches = row.branches ?? [];
    }
    if (row.students_count !== undefined) {
      teacher.studentsCount = this.toNumericStat(row.students_count);
    }
    if (row.lessons_count !== undefined) {
      teacher.lessonsCount = this.toNumericStat(row.lessons_count);
    }
    if (row.rating !== undefined) {
      teacher.rating =
        row.rating === null || row.rating === undefined
          ? null
          : this.toNumericStat(row.rating);
    }
    if (row.created_at !== undefined) {
      teacher.createdAt = row.created_at;
    }
    return teacher;
  }

  private toStaffDto(row: StaffRow) {
    return {
      id: row.id,
      role: row.role,
      position: row.position,
      status: row.status,
      customData: row.custom_data ?? {},
      profileId: row.profile_id,
      profileUserId: row.profile_user_id,
      appRole: row.app_role,
      isAppAccount: row.is_app_account ?? false,
      firstName: row.first_name,
      lastName: row.last_name,
      email: row.email,
      phone: row.phone,
      branches: row.branches ?? [],
      createdAt: row.created_at,
    };
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

  private roomAvailabilityBounds(query: RoomAvailabilityQuery) {
    const reference = query.date
      ? new Date(query.date)
      : query.from
        ? new Date(query.from)
        : new Date();
    const dayStart = this.utcDayStart(reference);
    const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
    const slotFrom = query.from ? new Date(query.from) : dayStart;
    const slotTo = query.to
      ? new Date(query.to)
      : query.from
        ? new Date(
            slotFrom.getTime() + (query.durationMinutes ?? 60) * 60 * 1000,
          )
        : dayEnd;

    return {
      dayFrom: dayStart.toISOString(),
      dayTo: dayEnd.toISOString(),
      slotFrom: slotFrom.toISOString(),
      slotTo: slotTo.toISOString(),
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

  private toRoomAvailabilityDto(row: RoomAvailabilityRow) {
    return {
      roomId: row.room_id,
      branchId: row.branch_id,
      branchName: row.branch_name,
      roomName: row.room_name,
      capacity: row.capacity,
      lessons: row.lessons ?? [],
      isAvailable: row.is_available ?? false,
      conflictTypes: row.conflict_types ?? [],
    };
  }

  private toLessonDto(row: LessonRow) {
    return {
      id: row.id,
      studentId: row.student_id,
      groupId: row.group_id,
      leadId: row.lead_id,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      scheduledAt: row.scheduled_at,
      durationMinutes: row.duration_minutes,
      status: row.status,
      isTrial: row.is_trial,
      notes: row.notes,
      studentName: row.student_name || null,
      teacherName: row.teacher_name || null,
      branchName: row.branch_name || null,
      roomName: row.room_name || null,
      groupName: row.group_name || null,
      groupPricePerLesson:
        row.group_price_per_lesson === null
          ? null
          : Number(row.group_price_per_lesson),
    };
  }

  private toTaskDto(row: TaskRow) {
    const assignedName =
      `${row.assigned_first_name ?? ""} ${row.assigned_last_name ?? ""}`.trim();
    const creatorName =
      `${row.creator_first_name ?? ""} ${row.creator_last_name ?? ""}`.trim();
    const personName =
      `${row.entity_first_name ?? ""} ${row.entity_last_name ?? ""}`.trim();
    const task: Record<string, unknown> = {
      id: row.id,
      entityType: row.entity_type,
      entityId: row.entity_id,
      assignedTo: row.assigned_to,
      assignedName: assignedName || null,
      entityName: personName || row.entity_name?.trim() || null,
      title: row.title,
      description: row.description,
      status: row.status,
      dueAt: row.due_at,
      createdBy: row.created_by,
      createdAt: row.created_at,
    };
    if (
      row.creator_first_name !== undefined ||
      row.creator_last_name !== undefined
    ) {
      task.creatorName = creatorName || null;
    }
    if (row.branch_id !== undefined) {
      task.branchId = row.branch_id;
    }
    if (row.branch_name !== undefined) {
      task.branchName = row.branch_name;
    }
    return task;
  }

  private toTimelineDto(row: TimelineRow) {
    const actorName =
      `${row.actor_first_name ?? ""} ${row.actor_last_name ?? ""}`.trim();
    return {
      id: row.id,
      type: row.type,
      title: row.title,
      body: row.body,
      status: row.status,
      amount: row.amount === null ? null : Number(row.amount),
      actorUserId: row.actor_user_id,
      actorName: actorName || null,
      occurredAt: row.occurred_at,
    };
  }

  private toCommentDto(row: CommentRow) {
    const authorName =
      `${row.author_first_name ?? ""} ${row.author_last_name ?? ""}`.trim();
    return {
      id: row.id,
      entityType: row.entity_type,
      entityId: row.entity_id,
      authorId: row.author_id,
      authorName: authorName || null,
      body: row.body,
      createdAt: row.created_at,
    };
  }

  private toPaymentDto(row: PaymentRow) {
    return {
      id: row.id,
      studentId: row.student_id,
      studentName:
        `${row.student_first_name ?? ""} ${row.student_last_name ?? ""}`.trim() ||
        null,
      amount: Number(row.amount),
      currency: row.currency,
      paymentDate: row.payment_date,
      method: row.method,
      externalId: row.external_id,
      notes: row.notes,
      createdBy: row.created_by,
      createdAt: row.created_at,
    };
  }

  private toExpectedPaymentDto(row: ExpectedPaymentRow) {
    return {
      id: row.id,
      studentId: row.student_id,
      studentName:
        `${row.student_first_name ?? ""} ${row.student_last_name ?? ""}`.trim() ||
        null,
      amount: Number(row.amount),
      dueDate: row.due_date,
      status: row.status,
      description: row.description,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private toStudentBalanceDto(row: StudentBalanceRow) {
    return {
      studentId: row.student_id,
      balance: Number(row.balance),
      totalPaid: Number(row.total_paid),
      totalCost: Number(row.total_cost),
      updatedAt: row.updated_at,
      student: {
        firstName: row.first_name,
        lastName: row.last_name,
        phone: row.phone,
      },
    };
  }

  private toSubscriptionDto(row: SubscriptionRow) {
    return {
      id: row.id,
      studentId: row.student_id,
      lessonsTotal: row.lessons_total,
      lessonsUsed: row.lessons_used,
      startsAt: row.starts_at,
      expiresAt: row.expires_at,
      status: row.status,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private toLeadDto(row: LeadRow) {
    return {
      id: row.id,
      statusId: row.status_id,
      statusName: row.status_name,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      email: row.email,
      source: row.source,
      notes: row.notes,
      assignedTo: row.assigned_to,
      customData: row.custom_data ?? {},
      createdBy: row.created_by,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  private toLeadBoardItemDto(row: LeadBoardRow) {
    const assignedName =
      `${row.assigned_first_name ?? ""} ${row.assigned_last_name ?? ""}`.trim();
    return {
      ...this.toLeadDto(row),
      statusColor: row.status_color,
      statusSortOrder: row.status_sort_order,
      assignedName: assignedName || null,
      branchId: row.branch_id,
      branchName: row.branch_name,
      linkedStudentId: row.linked_student_id,
      openTasksCount: this.toNumericStat(row.open_tasks_count),
      commentsCount: this.toNumericStat(row.comments_count),
      trialLessonsCount: this.toNumericStat(row.trial_lessons_count),
    };
  }

  private toDuplicateCandidateDto(row: DuplicateCandidateRow) {
    return {
      id: row.id,
      entityTypeA: row.entity_type_a,
      entityIdA: row.entity_id_a,
      entityTypeB: row.entity_type_b,
      entityIdB: row.entity_id_b,
      matchType: row.match_type,
      matchValue: row.match_value,
      confidence: Number(row.confidence),
      source: row.source,
      status: row.status,
      decidedAt: row.decided_at,
      decidedBy: row.decided_by,
      decisionNotes: row.decision_notes,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      entityA: {
        name: row.entity_a_name,
        phone: row.entity_a_phone,
        email: row.entity_a_email,
      },
      entityB: {
        name: row.entity_b_name,
        phone: row.entity_b_phone,
        email: row.entity_b_email,
      },
    };
  }

  private toBranchDto(row: BranchRow) {
    return {
      id: row.id,
      name: row.name,
      address: row.address,
      utcOffsetMinutes: Number(row.utc_offset_minutes ?? 180),
      createdAt: row.created_at,
    };
  }

  async updateBranch(
    actor: ActorContext,
    branchId: string,
    dto: UpdateBranchDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<BranchRow>(
      `
        update app.branches
        set name = coalesce($2, name),
          address = coalesce($3, address),
          utc_offset_minutes = coalesce($4, utc_offset_minutes),
          updated_at = now()
        where id = $1 and deleted_at is null
        returning id, name, address, utc_offset_minutes, created_at
      `,
      [
        branchId,
        dto.name?.trim() || null,
        dto.address?.trim() ?? null,
        dto.utcOffsetMinutes ?? null,
      ],
    );
    const branch = result.rows[0];
    if (!branch) throw new NotFoundException("Филиал не найден.");
    await this.audit.record({
      actor,
      action: "crm.branch_updated",
      entityType: "branch",
      entityId: branch.id,
      metadata: { utcOffsetMinutes: dto.utcOffsetMinutes },
    });
    return this.toBranchDto(branch);
  }

  private toRoomDto(row: RoomRow) {
    return {
      id: row.id,
      branchId: row.branch_id,
      branchName: row.branch_name,
      name: row.name,
      capacity: row.capacity,
      createdAt: row.created_at,
    };
  }

  private toGroupDto(row: GroupRow) {
    return {
      id: row.id,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      name: row.name,
      pricePerLesson:
        row.price_per_lesson === null ? null : Number(row.price_per_lesson),
      teacherName: row.teacher_name || null,
      branchName: row.branch_name,
      roomName: row.room_name,
      createdAt: row.created_at,
    };
  }

  private toLeadStatusDto(row: LeadStatusRow) {
    return {
      id: row.id,
      name: row.name,
      color: row.color,
      sortOrder: row.sort_order,
      createdAt: row.created_at,
    };
  }

  private toNumericStat(value: string | number | null | undefined): number {
    if (value === null || value === undefined) return 0;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
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

  async createFamily(actor: ActorContext, dto: { name?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string; name: string | null; branch_id: string | null }>(
      `insert into app.families (name, branch_id) values ($1, $2) returning id, name, branch_id`,
      [dto.name ?? null, dto.branchId ?? null],
    );
    const row = result.rows[0];
    return { id: row.id, name: row.name, branchId: row.branch_id };
  }

  async addFamilyMember(
    actor: ActorContext,
    familyId: string,
    dto: { entityType: string; entityId: string; role: string; isPrimaryContact?: boolean },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      family_id: string;
      entity_type: string;
      entity_id: string;
      role: string;
    }>(
      `insert into app.family_members (family_id, entity_type, entity_id, role, is_primary_contact)
       values ($1, $2, $3, $4, $5)
       on conflict (family_id, entity_type, entity_id)
       do update set role = excluded.role, is_primary_contact = excluded.is_primary_contact, deleted_at = null
       returning id, family_id, entity_type, entity_id, role`,
      [familyId, dto.entityType, dto.entityId, dto.role, dto.isPrimaryContact ?? false],
    );
    const row = result.rows[0];
    return { id: row.id, familyId: row.family_id, entityType: row.entity_type, entityId: row.entity_id, role: row.role };
  }

  async getFamilyForEntity(actor: ActorContext, entityType: string, entityId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const famRes = await this.database.query<{
      family_id: string;
      name: string | null;
      branch_id: string | null;
      primary_payer_member_id: string | null;
    }>(
      `select f.id as family_id, f.name, f.branch_id, f.primary_payer_member_id
         from app.family_members m
         join app.families f on f.id = m.family_id and f.deleted_at is null
        where m.entity_type = $1 and m.entity_id = $2 and m.deleted_at is null
        limit 1`,
      [entityType, entityId],
    );
    const fam = famRes.rows[0];
    if (!fam) return { family: null, members: [] };
    const memRes = await this.database.query<{
      id: string;
      entity_type: string;
      entity_id: string;
      role: string;
      is_primary_contact: boolean;
      member_name: string | null;
    }>(
      `select m.id, m.entity_type, m.entity_id, m.role, m.is_primary_contact,
              coalesce(
                nullif(btrim(concat_ws(' ', l.first_name, l.last_name)), ''),
                nullif(btrim(concat_ws(' ', sp.first_name, sp.last_name)), ''),
                nullif(btrim(concat_ws(' ', pr.first_name, pr.last_name)), '')
              ) as member_name
         from app.family_members m
         left join app.leads l    on m.entity_type = 'lead'    and l.id = m.entity_id and l.deleted_at is null
         left join app.students st on m.entity_type = 'student' and st.id = m.entity_id and st.deleted_at is null
         left join app.profiles sp on sp.id = st.profile_id and sp.deleted_at is null
         left join app.profiles pr on m.entity_type = 'profile' and pr.id = m.entity_id and pr.deleted_at is null
        where m.family_id = $1 and m.deleted_at is null
        order by m.role, member_name`,
      [fam.family_id],
    );
    return {
      family: {
        id: fam.family_id,
        name: fam.name,
        branchId: fam.branch_id,
        primaryPayerMemberId: fam.primary_payer_member_id,
      },
      members: memRes.rows.map((row) => ({
        id: row.id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        role: row.role,
        isPrimaryContact: row.is_primary_contact,
        name: row.member_name,
      })),
    };
  }

  async removeFamilyMember(actor: ActorContext, memberId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query(
      `update app.family_members set deleted_at = now() where id = $1 and deleted_at is null`,
      [memberId],
    );
    if (!result.rowCount) {
      throw new NotFoundException("Участник семьи не найден.");
    }
    return { success: true as const };
  }

  async setPrimaryPayer(actor: ActorContext, familyId: string, memberId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query(
      `update app.families
          set primary_payer_member_id = $2, updated_at = now()
        where id = $1 and deleted_at is null
          and exists (
            select 1 from app.family_members m
            where m.id = $2 and m.family_id = $1 and m.deleted_at is null
          )`,
      [familyId, memberId],
    );
    if (!result.rowCount) {
      throw new NotFoundException("Семья или участник не найдены.");
    }
    return { success: true as const };
  }

  async listMergeCandidates(actor: ActorContext, limit = 50) {
    this.policy.assertCanReadOperationalData(actor);
    const safeLimit = Number.isFinite(limit) ? limit : 50;
    const capped = Math.min(Math.max(safeLimit, 1), 200);
    const result = await this.database.query<{
      loser_id: string;
      winner_id: string;
      phone: string | null;
      name: string;
    }>(
      `select l1.id as loser_id, l2.id as winner_id, l2.phone_normalized as phone,
              btrim(concat_ws(' ', l2.first_name, l2.last_name)) as name
         from app.leads l1
         join app.leads l2
           on l1.phone_normalized = l2.phone_normalized
          and lower(btrim(coalesce(l1.first_name, ''))) = lower(btrim(coalesce(l2.first_name, '')))
          and lower(btrim(coalesce(l1.last_name, '')))  = lower(btrim(coalesce(l2.last_name, '')))
          and l1.id < l2.id
        where l1.deleted_at is null and l2.deleted_at is null
          and l1.phone_normalized is not null
        order by l2.phone_normalized
        limit $1`,
      [capped],
    );
    return {
      items: result.rows.map((row) => ({
        loserId: row.loser_id,
        winnerId: row.winner_id,
        phone: row.phone,
        name: row.name,
      })),
    };
  }

  async mergeLeads(actor: ActorContext, loserId: string, winnerId: string) {
    this.policy.assertCanWriteCrm(actor);
    if (loserId === winnerId) {
      throw new BadRequestException("Нельзя объединить лид сам с собой.");
    }
    return this.database.transaction(async (client) => {
      const existing = await client.query<{ id: string }>(
        `select id from app.leads where id in ($1, $2) and deleted_at is null`,
        [loserId, winnerId],
      );
      if (existing.rows.length !== 2) {
        throw new NotFoundException("Один из лидов не найден.");
      }

      const repointed: Record<string, string[]> = {};
      const ids = (rows: { id: string }[]) => rows.map((r) => r.id);

      // Real-FK lead references.
      repointed["students.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.students set lead_id = $2, updated_at = now() where lead_id = $1 and deleted_at is null returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lessons.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lessons set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lead_status_history.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lead_status_history set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lead_comments.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lead_comments set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      // Polymorphic (no unique constraint).
      repointed["tasks.entity_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.tasks set entity_id = $2 where entity_type = 'lead' and entity_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["entity_comments.entity_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.entity_comments set entity_id = $2 where entity_type = 'lead' and entity_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["chats.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.chats set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      // Mark duplicate candidates merged (capture for undo).
      repointed["duplicate_candidates.status"] = ids(
        (await client.query<{ id: string }>(
          `update app.duplicate_candidates set status = 'merged', updated_at = now()
            where status = 'pending'
              and ((entity_type_a = 'lead' and entity_id_a = $1) or (entity_type_b = 'lead' and entity_id_b = $1))
            returning id`,
          [loserId],
        )).rows,
      );

      // Soft-delete the loser (CASCADE never fires — no hard delete).
      await client.query(
        `update app.leads set deleted_at = now(), updated_at = now() where id = $1`,
        [loserId],
      );

      const log = await client.query<{ id: string }>(
        `insert into app.merge_log (entity_type, loser_id, winner_id, repointed, merged_by)
         values ('lead', $1, $2, $3::jsonb, $4) returning id`,
        [loserId, winnerId, JSON.stringify(repointed), actor.userId],
      );
      return { mergeLogId: log.rows[0].id, winnerId };
    });
  }

  // Reverse-op for each known repointed key. Hard-coded — never derives a table
  // name from stored data.
  private static readonly UNDO_REPOINT: Record<string, string> = {
    "students.lead_id": "update app.students set lead_id = $1, updated_at = now() where id = any($2::uuid[])",
    "lessons.lead_id": "update app.lessons set lead_id = $1 where id = any($2::uuid[])",
    "lead_status_history.lead_id": "update app.lead_status_history set lead_id = $1 where id = any($2::uuid[])",
    "lead_comments.lead_id": "update app.lead_comments set lead_id = $1 where id = any($2::uuid[])",
    "tasks.entity_id": "update app.tasks set entity_id = $1 where id = any($2::uuid[])",
    "chats.lead_id": "update app.chats set lead_id = $1 where id = any($2::uuid[])",
    "entity_comments.entity_id": "update app.entity_comments set entity_id = $1 where id = any($2::uuid[])",
    "duplicate_candidates.status": "update app.duplicate_candidates set status = 'pending', updated_at = now() where id = any($2::uuid[])",
  };

  // Auto-create a lead when a non-staff user first writes to the admin chat.
  // Idempotent: skips if the user is already linked to a lead or student.
  async autoCreateLeadFromChat(
    actor: ActorContext,
    senderUserId: string,
  ): Promise<{ leadId: string | null; created: boolean }> {
    const linked = await this.database.query<{ entity_type: string; entity_id: string }>(
      `select entity_type, entity_id from app.user_crm_links
        where user_id = $1 and entity_type in ('lead', 'student') and deleted_at is null
        limit 1`,
      [senderUserId],
    );
    if (linked.rows[0]) {
      const existing = linked.rows[0];
      return { leadId: existing.entity_type !== "student" ? existing.entity_id : null, created: false };
    }

    const profileRes = await this.database.query<{
      first_name: string | null;
      last_name: string | null;
      phone: string | null;
    }>(
      `select p.first_name, p.last_name, p.phone
         from app.profiles p
         join app.users u on u.id = p.user_id and u.deleted_at is null
        where p.user_id = $1 and p.deleted_at is null
        limit 1`,
      [senderUserId],
    );
    const profile = profileRes.rows[0];
    if (!profile) return { leadId: null, created: false };

    const statusRes = await this.database.query<{ id: string }>(
      `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
    );
    const newStatusId = statusRes.rows[0]?.id ?? null;
    const matchedPhone = this.normalizeContactPhone(profile.phone);

    const leadId = await this.database.transaction(async (client) => {
      const inserted = await client.query<{ id: string }>(
        `insert into app.leads (first_name, last_name, phone, source, status_id, created_by)
         values ($1, $2, $3, 'Через приложение', $4, $5)
         returning id`,
        [profile.first_name, profile.last_name, profile.phone, newStatusId, actor.userId],
      );
      const id = inserted.rows[0].id;
      await client.query(
        `insert into app.user_crm_links
           (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
         values ($1, 'lead', $2, $3, 'auto_phone', $4, now())
         on conflict do nothing`,
        [senderUserId, id, matchedPhone, actor.userId],
      );
      return id;
    });

    await this.audit.record({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: leadId,
      metadata: { fromApp: true, userId: senderUserId },
    });
    return { leadId, created: true };
  }

  async countAppLeads(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count from app.leads where source = 'Через приложение' and deleted_at is null`,
    );
    return { count: Number(result.rows[0]?.count ?? 0) };
  }

  async undoMerge(actor: ActorContext, mergeLogId: string) {
    this.policy.assertCanWriteCrm(actor);
    return this.database.transaction(async (client) => {
      const logRes = await client.query<{
        loser_id: string;
        repointed: Record<string, string[]>;
      }>(
        `select loser_id, repointed from app.merge_log where id = $1 and undone_at is null`,
        [mergeLogId],
      );
      const log = logRes.rows[0];
      if (!log) {
        throw new NotFoundException("Слияние не найдено или уже отменено.");
      }
      for (const [key, sql] of Object.entries(CrmService.UNDO_REPOINT)) {
        const movedIds = log.repointed[key];
        if (!movedIds || movedIds.length === 0) continue;
        const isDupCandidate = key === "duplicate_candidates.status";
        await client.query(sql, isDupCandidate ? [null, movedIds] : [log.loser_id, movedIds]);
      }
      // The duplicate_candidates reverse SQL ignores $1; pass null there.
      await client.query(
        `update app.leads set deleted_at = null, updated_at = now() where id = $1`,
        [log.loser_id],
      );
      await client.query(
        `update app.merge_log set undone_at = now(), undone_by = $2 where id = $1`,
        [mergeLogId, actor.userId],
      );
      return { success: true as const };
    });
  }
}
