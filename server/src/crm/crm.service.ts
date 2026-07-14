import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { AuditService } from "../audit/audit.service";
import { LeadIntakePort } from "../common/lead-intake.port";
import { branchIdExpr, extractBranchId } from "./branch-scope";
import { audienceForLesson, audienceForStudent } from "./audience";
import { StudentRow, findStudent } from "./student-read";
import {
  ActorContext,
  canAssignRole,
  isAdminRole,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { ActivityLogQuery } from "./dto/activity-log.query";
import { CommentQuery } from "./dto/comment.query";
import { CreateCommentDto } from "./dto/create-comment.dto";
import { DuplicateCandidatesQuery } from "./dto/duplicate-candidates.query";
import { DuplicateDecisionDto } from "./dto/duplicate-decision.dto";
import {
  CreateScheduleSeriesDto,
  UpdateScheduleSeriesDto,
} from "./dto/schedule-series.dto";
import { CreateStaffDto } from "./dto/create-staff.dto";
import { CreateStudentDto } from "./dto/create-student.dto";
import { CreateTeacherDto } from "./dto/create-teacher.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { LessonQuery } from "./dto/lesson.query";
import { ManagerDashboardQuery } from "./dto/manager-dashboard.query";
import { ReportQuery } from "./dto/report.query";
import { ScheduleMatrixQuery } from "./dto/schedule-matrix.query";
import { StaffListQuery } from "./dto/staff-list.query";
import { StudentSearchQuery } from "./dto/student-search.query";
import { TimelineQuery } from "./dto/timeline.query";
import { TeacherListQuery } from "./dto/teacher-list.query";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { UpdateStaffDto } from "./dto/update-staff.dto";
import { UpdateTeacherDto } from "./dto/update-teacher.dto";
import { UpsertLeadDto } from "./dto/upsert-lead.dto";
import { UpsertLessonDto } from "./dto/upsert-lesson.dto";
import { CrmPolicy } from "./crm.policy";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { TasksService } from "./tasks.service";
import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

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
  disciplines: { id: string; name: string }[] | null;
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
  // KVA-238: оклад, актуальная ставка и явные связи (дисциплины/филиалы).
  salary?: string | number | null;
  current_rate?: string | number | null;
  disciplines?: Array<{ id: string; name: string }> | null;
  assigned_branches?: Array<{ id: string; name: string }> | null;
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
  teacher_rate?: string | number | null;
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

interface TaskRow {
  id: string;
  entity_type: string;
  entity_id: string;
  assigned_to: string | null;
  assigned_first_name?: string | null;
  assigned_last_name?: string | null;
  creator_first_name?: string | null;
  creator_last_name?: string | null;
  assigned_profile_id?: string | null;
  creator_profile_id?: string | null;
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
  kind: string;
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

interface GroupRow {
  id: string;
  teacher_id: string | null;
  branch_id: string | null;
  room_id: string | null;
  name: string;
  price_per_lesson: string | null;
  // KVA-238: переопределение ставки педагога (null = брать ставку педагога).
  teacher_rate?: string | number | null;
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
  requires_reason?: boolean;
  is_terminal?: boolean;
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
export class CrmService implements LeadIntakePort {
  private readonly logger = new Logger(CrmService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly subscriptions: SubscriptionsService,
    private readonly finance: FinanceService,
    private readonly tasks: TasksService,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeBus,
  ) {}

  async getMySummary(actor: ActorContext) {
    const ownStudents = await this.listClientStudents(actor.userId);
    // KVA-156: a parent/payer account also sees children linked via Families.
    const familyStudents = await this.listFamilyLinkedStudents(actor.userId);
    // Manual app-account links are the CRM source of truth for imported/existing
    // students whose profile owner is not the signed-in app user.
    const linkedStudents = await this.listManuallyLinkedStudents(actor.userId);
    // Union own + family/manual-linked students; dedup by student id (own wins).
    const byId = new Map<string, StudentRow>();
    for (const row of ownStudents) byId.set(row.id, row);
    for (const row of familyStudents) {
      if (!byId.has(row.id)) byId.set(row.id, row);
    }
    for (const row of linkedStudents) {
      if (!byId.has(row.id)) byId.set(row.id, row);
    }
    const students = Array.from(byId.values());
    const studentIds = students.map((student) => student.id);
    let lessons: LessonRow[] = [];
    let tasks: TaskRow[] = [];
    let payments: PaymentRow[] = [];
    if (studentIds.length) {
      [lessons, tasks, payments] = await Promise.all([
        this.listClientSummaryLessons(studentIds).catch(() => []),
        this.listClientSummaryTasks(studentIds).catch(() => []),
        this.listClientSummaryPayments(studentIds).catch(() => []),
      ]);
    }

    return {
      students: students.map((row) => this.toStudentDto(row)),
      upcomingLessons: lessons.map((row) => this.toLessonDto(row)),
      tasks: tasks.map((row) => this.toTaskDto(row)),
      recentPayments: payments.map((row) => this.toPaymentDto(row)),
    };
  }

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
              and ($3::uuid is null or ${branchIdExpr('s')} = $3::text)
          ) as revenue,
          (
            select coalesce(sum(ep.amount), 0)
            from app.expected_payments ep
            join app.students s on s.id = ep.student_id and s.deleted_at is null
            where ep.status in ('pending', 'open')
              and (ep.due_date is null or ep.due_date < $2::date)
              and ($3::uuid is null or ${branchIdExpr('s')} = $3::text)
          ) as expected_payments,
          (
            select count(*)
            from app.student_balances sb
            join app.students s on s.id = sb.student_id and s.deleted_at is null
            where sb.balance < 0
              and ($3::uuid is null or ${branchIdExpr('s')} = $3::text)
          ) as debt_students,
          (
            select count(*)
            from app.students s
            where s.deleted_at is null
              and s.status = 'active'
              and ($3::uuid is null or ${branchIdExpr('s')} = $3::text)
          ) as active_students,
          (
            select count(*)
            from app.leads l
            where l.deleted_at is null
              and l.created_at >= $1::timestamptz
              and l.created_at < $2::timestamptz
              and ($3::uuid is null or ${branchIdExpr('l')} = $3::text)
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
            $1::text in ('manager', 'director', 'admin', 'system_admin')
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
    // Board pulls a whole branch (up to ~1.5k students); cap matches DTO @Max(500).
    const limit = Math.min(query.limit ?? 50, 500);
    const filter = this.buildStudentSearchFilter(actor, query);
    const result = await this.database.query<StudentSearchRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone,
          s.created_at,
          coalesce(array_remove(array_agg(distinct tp.user_id), null), '{}'::uuid[]) as teacher_user_ids,
          ${branchIdExpr('s')} as branch_id,
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
          coalesce(link_user.is_app_account, u.is_app_account, false) as is_app_account,
          (
            select coalesce(
              json_agg(json_build_object('id', d.id, 'name', d.name) order by d.name),
              '[]'::json
            )
            from app.student_disciplines sd
            join app.disciplines d on d.id = sd.discipline_id
            where sd.student_id = s.id
          ) as disciplines
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        left join app.branches b
          on b.id::text = ${branchIdExpr('s')}
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
    const branchId = extractBranchId(dto.customDataPatch);

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
      this.realtime.emitCrmChanged({
        entity: "student",
        action: "created",
        id: student.id,
        branchId: branchId ?? null,
      });
      return this.toStudentDto(student);
    } catch (error) {
      this.rethrowCreatePersonError(error);
    }
  }

  async getStudent(actor: ActorContext, studentId: string) {
    const student = await findStudent(this.database, studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });
    return this.toStudentDto(student);
  }

  async getStudentCard(actor: ActorContext, studentId: string) {
    const student = await findStudent(this.database, studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });

    // Финансовые секции (баланс/оплаты/ожидаемые) видит только Управляющий +
    // Администратор. Для остальных (напр. преподавателя) карточка всё равно
    // открывается — финансы просто пустые. КАЖДАЯ секция изолирована (.catch),
    // чтобы отказ в доступе или сбой одной секции НИКОГДА не ронял всю карточку
    // (ранее Promise.all был «всё-или-ничего» → у admin/teacher падала вся
    // карточка из-за manager-only баланса).
    const canReadFinance = this.policy.canReadStudentFinance(actor);
    const emptyList = { items: [] as never[] };

    const [
      groups,
      lessons,
      payments,
      tasks,
      comments,
      expectedPayments,
      balances,
      subscriptions,
      links,
      chatWork,
    ] = await Promise.all([
      this.listStudentGroups(actor, studentId, { limit: 100 }),
      this.listLessons(actor, { studentId, limit: 100 }),
      canReadFinance
        ? this.finance.listPayments(actor, { studentId, limit: 100 }).catch(() => emptyList)
        : Promise.resolve(emptyList),
      this.tasks.listTasks(actor, { studentId, limit: 100 }),
      this.listComments(actor, {
        entityType: "student",
        entityId: studentId,
        limit: 100,
      }).catch(() => emptyList),
      canReadFinance
        ? this.finance.listExpectedPayments(actor, { studentId, limit: 100 }).catch(() => emptyList)
        : Promise.resolve(emptyList),
      canReadFinance
        ? this.finance.listStudentBalances(actor, { studentId, limit: 1 }).catch(() => emptyList)
        : Promise.resolve(emptyList),
      canReadFinance
        ? this.subscriptions.listSubscriptions(actor, { studentId, limit: 50 }).catch(() => emptyList)
        : Promise.resolve(emptyList),
      this.listUserCrmLinks("student", studentId),
      this.listChatWorkTimeline("student", studentId),
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
      ...chatWork,
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
      subscriptions: subscriptions.items,
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
    const student = await findStudent(this.database, studentId);
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
    const branchId = extractBranchId(dto.customDataPatch);
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
    this.realtime.emitCrmChanged({
      entity: "student",
      action: "updated",
      id: student.id,
      branchId: branchId ?? beforeStudent?.branch_id ?? null,
    });
    return this.toStudentDto(student);
  }

  async inviteStudent(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    const student = await findStudent(this.database, studentId);
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
        select t.id, t.status, t.specialization, t.custom_data,
          t.profile_id, p.user_id as profile_user_id, u.role::text as app_role,
          coalesce(u.is_app_account, false) as is_app_account,
          coalesce(p.first_name, t.custom_data->>'firstName') as first_name,
          coalesce(p.last_name, t.custom_data->>'lastName') as last_name,
          u.email, p.phone,
          agg.branches,
          agg.students_count,
          agg.lessons_count,
          -- KVA-238: оклад, актуальная ставка и явные связи для карточки.
          t.salary,
          (
            select tr.rate
            from app.teacher_rates tr
            where tr.teacher_id = t.id and tr.effective_from <= current_date
            order by tr.effective_from desc, tr.created_at desc
            limit 1
          ) as current_rate,
          (
            select coalesce(
              jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name),
              '[]'::jsonb
            )
            from app.teacher_disciplines td
            join app.disciplines d on d.id = td.discipline_id and d.deleted_at is null
            where td.teacher_id = t.id
          ) as disciplines,
          (
            select coalesce(
              jsonb_agg(jsonb_build_object('id', tb_branch.id, 'name', tb_branch.name) order by tb_branch.name),
              '[]'::jsonb
            )
            from app.teacher_branches tb
            join app.branches tb_branch on tb_branch.id = tb.branch_id and tb_branch.deleted_at is null
            where tb.teacher_id = t.id
          ) as assigned_branches,
          case
            when t.custom_data->>'rating' ~ '^-?[0-9]+(\\.[0-9]+)?$'
              then (t.custom_data->>'rating')::numeric
            else null
          end as rating,
          t.created_at
        from app.teachers t
        left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        left join lateral (
          select
            coalesce(
              (
                select jsonb_agg(distinct jsonb_build_object('id', br.id, 'name', br.name))
                  filter (where br.id is not null)
                from (
                  select b.id, b.name
                  from app.groups gb
                  join app.branches b on b.id = gb.branch_id and b.deleted_at is null
                  where gb.teacher_id = t.id and gb.deleted_at is null
                  union
                  select b.id, b.name
                  from app.lessons lb
                  join app.branches b on b.id = lb.branch_id and b.deleted_at is null
                  where lb.teacher_id = t.id and lb.deleted_at is null
                ) br
              ),
              '[]'::jsonb
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
            ) as lessons_count
        ) agg on true
        where t.deleted_at is null
          and (
            $1::text in ('manager', 'director', 'admin', 'system_admin')
            or ($1::text = 'teacher' and p.user_id = $2)
            or ($1::text = 'client' and (
              exists (
                select 1
                from app.lessons cl
                join app.students cs on cs.id = cl.student_id and cs.deleted_at is null
                join app.profiles csp on csp.id = cs.profile_id and csp.deleted_at is null
                where cl.teacher_id = t.id and cl.deleted_at is null and csp.user_id = $2
              )
              or exists (
                select 1
                from app.groups cg
                join app.group_students cgs on cgs.group_id = cg.id and cgs.left_at is null
                join app.students cgst on cgst.id = cgs.student_id and cgst.deleted_at is null
                join app.profiles cgsp on cgsp.id = cgst.profile_id and cgsp.deleted_at is null
                where cg.teacher_id = t.id and cg.deleted_at is null and cgsp.user_id = $2
              )
            ))
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
    // KVA-238: оклад — зарплатное поле, правится только ролями payroll.
    if (dto.salary !== undefined) this.policy.assertCanReadPayroll(actor);
    // KVA-238: custom-поля карточки (birthday, workStartDate, level, category,
    // isPartTime, isBlacklisted) патчатся merge'ем — по образцу updateStudent.
    const customDataPatch = this.sanitizeJsonObject(dto.customDataPatch);
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
            custom_data = coalesce(t.custom_data, '{}'::jsonb) || $8::jsonb,
            salary = coalesce($9::numeric, t.salary),
            updated_at = now()
          from target
          where t.id = target.id
          returning t.id, t.status, t.specialization, t.custom_data, t.salary,
            t.profile_id
        )
        select ut.id, ut.status, ut.specialization, ut.custom_data, ut.salary,
          ut.profile_id,
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
        JSON.stringify(customDataPatch),
        dto.salary ?? null,
      ],
    );
    const teacher = result.rows[0];
    if (!teacher) throw new NotFoundException("Преподаватель не найден.");
    // KVA-238: полная замена m2m-связей, если списки переданы. delete+insert
    // идемпотентен и проще диффа; объёмы — единицы строк на педагога.
    if (dto.disciplineIds) {
      await this.database.query(
        `delete from app.teacher_disciplines
         where teacher_id = $1 and not (discipline_id = any($2::uuid[]))`,
        [teacherId, dto.disciplineIds],
      );
      if (dto.disciplineIds.length) {
        await this.database.query(
          `insert into app.teacher_disciplines (teacher_id, discipline_id)
           select $1, unnest($2::uuid[])
           on conflict do nothing`,
          [teacherId, dto.disciplineIds],
        );
      }
    }
    if (dto.branchIds) {
      await this.database.query(
        `delete from app.teacher_branches
         where teacher_id = $1 and not (branch_id = any($2::uuid[]))`,
        [teacherId, dto.branchIds],
      );
      if (dto.branchIds.length) {
        await this.database.query(
          `insert into app.teacher_branches (teacher_id, branch_id)
           select $1, unnest($2::uuid[])
           on conflict do nothing`,
          [teacherId, dto.branchIds],
        );
      }
    }
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
    // Назначить роль сотруднику может только тот, кто стоит в иерархии выше этой
    // роли: Управляющий (manager) — admin и ниже; Администратор системы — любую.
    // Администратор (admin) ролями не управляет вовсе. См. canAssignRole.
    if (!canAssignRole(actor.role, dto.role)) {
      throw new ForbiddenException(
        "Недостаточно прав для назначения этой роли сотруднику.",
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
                when $4 = 'director' then 'Директор'
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
      ...this.toLessonDto(row),
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
    const limit = Math.min(query.limit ?? 100, 200);
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
            $1::text in ('manager', 'director', 'admin', 'system_admin')
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
    return this.toLessonDto(lesson);
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
      [seriesId, CrmService.SERIES_HORIZON_DAYS],
    );
    return result.rowCount ?? 0;
  }

  /** Продлить все живые серии (вкл. «до бесконечности») — вызывается воркером. */
  async extendAllSeriesHorizon(): Promise<{ series: number; created: number }> {
    const rows = await this.database.query<{ id: string }>(
      `
        select id from app.schedule_series
        where deleted_at is null
          and (valid_until is null or valid_until >= current_date)
      `,
    );
    let created = 0;
    for (const row of rows.rows) {
      created += await this.materializeSeries(row.id);
    }
    return { series: rows.rows.length, created };
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

    // Закрываем старую серию накануне effectiveFrom (если она уже шла).
    await this.database.query(
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
    await this.database.query(
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
    const inserted = await this.database.query<{ id: string }>(
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
    const newSeriesId = inserted.rows[0].id;
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
    const result = await this.database.query(
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
    await this.database.query(
      `
        update app.lessons
        set deleted_at = now(), updated_at = now()
        where series_id = $1 and series_date >= $2::date
          and status = 'scheduled' and original_scheduled_at is null
          and deleted_at is null
      `,
      [seriesId, stopFrom],
    );
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
    return this.toLessonDto(lesson);
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

    const whenLocal = this.formatLessonTimeMoscow(lesson.scheduled_at);
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
        const oldWhenLocal = this.formatLessonTimeMoscow(
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

  private formatLessonTimeMoscow(value: Date | string | null): string {
    if (value === null) return "";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    // Mirror the reminder format ("DD.MM HH24:MI", Europe/Moscow).
    const parts = new Intl.DateTimeFormat("ru-RU", {
      timeZone: "Europe/Moscow",
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(date);
    const get = (type: string) =>
      parts.find((part) => part.type === type)?.value ?? "";
    return `${get("day")}.${get("month")} ${get("hour")}:${get("minute")}`;
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
            and c.kind = any($7::text[])

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

          select work.id::text as id, 'chat_work'::text as type,
            case
              when work.action = 'unassigned' then 'Снято с работы'
              else 'Взято в работу'
            end as title,
            nullif(
              trim(coalesce(target_profile.first_name, '') || ' ' || coalesce(target_profile.last_name, '')),
              ''
            ) as body,
            work.action as status, null::numeric as amount,
            work.actor_user_id,
            actor_profile.first_name as actor_first_name,
            actor_profile.last_name as actor_last_name,
            work.created_at as occurred_at
          from app.chat_work_events work
          join app.chats chat on chat.id = work.chat_id and chat.deleted_at is null
          left join app.users actor_user on actor_user.id = work.actor_user_id and actor_user.deleted_at is null
          left join app.profiles actor_profile on actor_profile.user_id = actor_user.id and actor_profile.deleted_at is null
          left join app.users target_user on target_user.id = work.target_user_id and target_user.deleted_at is null
          left join app.profiles target_profile on target_profile.user_id = target_user.id and target_profile.deleted_at is null
          where chat.type = 'administration'
            and (
              ($1 = 'student' and (
                chat.student_id = $2::uuid
                or exists (
                  select 1
                  from app.user_crm_links link
                  where link.entity_type = 'student'
                    and link.entity_id = $2::uuid
                    and link.user_id = chat.owner_user_id
                    and link.deleted_at is null
                )
              ))
              or ($1 = 'lead' and (
                chat.lead_id = $2::uuid
                or exists (
                  select 1
                  from app.user_crm_links link
                  where link.entity_type = 'lead'
                    and link.entity_id = $2::uuid
                    and link.user_id = chat.owner_user_id
                    and link.deleted_at is null
                )
              ))
            )

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
        this.allowedCommentKinds(actor.role),
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
    let allowedKinds = this.allowedCommentKinds(actor.role);
    // Back-compat: progressOnly restricts to the client-visible progress stream.
    if (query.progressOnly === true) {
      allowedKinds = allowedKinds.filter((k) => k === "progress");
    }
    // Caller can request a single stream (e.g. the card's admin-comments vs
    // teacher-notes section); still bounded by what the role may see.
    if (query.kind) {
      allowedKinds = allowedKinds.filter((k) => k === query.kind);
    }
    if (allowedKinds.length === 0) return { items: [] };
    const result = await this.database.query<CommentRow>(
      `
        select c.id, c.entity_type, c.entity_id, c.author_id, c.kind,
          p.first_name as author_first_name, p.last_name as author_last_name,
          c.body, c.created_at
        from app.entity_comments c
        left join app.users u on u.id = c.author_id and u.deleted_at is null
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where c.deleted_at is null
          and c.entity_type = $1::app.crm_entity_type
          and c.entity_id = $2
          and c.kind = any($3::text[])
        order by c.created_at desc, c.id desc
        limit $4
      `,
      [query.entityType, query.entityId, allowedKinds, limit],
    );
    return { items: result.rows.map((row) => this.toCommentDto(row)) };
  }

  async createComment(actor: ActorContext, dto: CreateCommentDto) {
    const body = dto.body.trim();
    if (!body)
      throw new BadRequestException("Комментарий не может быть пустым.");
    const kind =
      dto.kind ?? (dto.progress === true ? "progress" : "admin_comment");
    await this.assertCanCreateEntityComment(actor, dto, kind);
    const result = await this.database.query<CommentRow>(
      `
        insert into app.entity_comments (
          entity_type, entity_id, author_id, body, kind
        )
        values ($1::app.crm_entity_type, $2, $3, $4, $5)
        returning id, entity_type, entity_id, author_id,
          null::text as author_first_name, null::text as author_last_name,
          body, kind, created_at
      `,
      [dto.entityType, dto.entityId, actor.userId, body, kind],
    );
    const comment = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.comment_created",
      entityType: dto.entityType,
      entityId: dto.entityId,
      metadata: { commentId: comment.id },
    });
    this.realtime.emitCrmChanged({
      entity: "comment",
      action: "created",
      id: comment.id,
    });
    return this.toCommentDto(comment);
  }

  // Toggle whether an existing comment is visible to the assigned teacher.
  // Default comments are `admin_comment` (staff-only); flipping to `teacher_note`
  // makes them visible to the teacher too, and back hides them again. Only staff
  // may change visibility; `progress` (client-facing) notes are out of scope.
  async setCommentVisibility(
    actor: ActorContext,
    commentId: string,
    visibleToTeacher: boolean,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const kind = visibleToTeacher ? "teacher_note" : "admin_comment";
    const result = await this.database.query<CommentRow>(
      `
        update app.entity_comments
        set kind = $2
        where id = $1
          and deleted_at is null
          and kind in ('admin_comment', 'teacher_note')
        returning id, entity_type, entity_id, author_id,
          null::text as author_first_name, null::text as author_last_name,
          body, kind, created_at
      `,
      [commentId, kind],
    );
    const comment = result.rows[0];
    if (!comment) throw new NotFoundException("Комментарий не найден.");
    await this.audit.record({
      actor,
      action: "crm.comment_visibility_changed",
      entityType: comment.entity_type,
      entityId: comment.entity_id,
      metadata: { commentId: comment.id, kind },
    });
    this.realtime.emitCrmChanged({
      entity: "comment",
      action: "updated",
      id: comment.id,
    });
    return this.toCommentDto(comment);
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
        select id, name, color, sort_order, created_at, requires_reason, is_terminal
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
            ${branchIdExpr('l')} as branch_id,
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
            on b.id::text = ${branchIdExpr('l')}
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
          requiresReason: false,
          isTerminal: false,
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
          ${branchIdExpr('l')} as branch_id,
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
          on b.id::text = ${branchIdExpr('l')}
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

    const [students, otherLeads, comments, tasks, trials, chatWork] = await Promise.all([
      this.listStudentsLinkedToLead(leadId),
      this.listRelatedLeads(lead),
      this.listLeadComments(leadId),
      this.listLeadTasks(leadId),
      this.listLeadTrialLessons(leadId),
      this.listChatWorkTimeline("lead", leadId),
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
      ...chatWork,
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

  // KVA-234: заявки лида из app.lead_applications (импорт HolliHop
  // GetStudyRequests, миграция 0050) — секция «Заявки» в карточке лида.
  async listLeadApplications(actor: ActorContext, leadId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{
      id: string;
      applied_at: string;
      channel: string | null;
      office: string | null;
      discipline: string | null;
      status: string | null;
      utm: Record<string, unknown> | null;
    }>(
      `select id, applied_at, channel, office, discipline, status, utm
         from app.lead_applications
        where lead_id = $1 and deleted_at is null
        order by applied_at desc`,
      [leadId],
    );
    return {
      items: result.rows.map((row) => ({
        id: row.id,
        appliedAt: row.applied_at,
        channel: row.channel,
        office: row.office,
        discipline: row.discipline,
        status: row.status,
        utm: row.utm,
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
      // KVA-175: stamp the funnel entry status «Новый» so a manually-saved
      // lead doesn't land in «Без статуса» (mirrors C6 autoCreateLeadFromChat).
      const statusRow = await this.database.query<{ id: string }>(
        `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
      );
      const defaultStatusId = statusRow.rows[0]?.id ?? null;
      const leadId = await this.database.transaction(async (client) => {
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.leads (first_name, last_name, phone, source, status_id, created_by)
            values ($1, $2, $3, 'Чат', $4, $5)
            returning id
          `,
          [firstName, lastName, phone, defaultStatusId, actor.userId],
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
    const branchId = extractBranchId(dto.customDataPatch);
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
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "created",
      id: lead.id,
      branchId: branchId ?? null,
    });
    this.notifyNewLeadSafe(
      lead.id,
      [lead.first_name, lead.last_name].filter(Boolean).join(" ").trim() || "Без имени",
      lead.source?.trim() || "CRM",
    );
    return this.toLeadDto(lead);
  }

  // Fire-and-forget staff notification about a new lead. A notification
  // failure (sync or async) must NEVER break lead creation — log and move on.
  private notifyNewLeadSafe(leadId: string, name: string, source: string): void {
    try {
      void this.notifications
        .notifyNewLead({ leadId, name, source })
        .catch((error: unknown) => {
          this.logger.warn(
            `New lead notification failed for ${leadId}: ${String(error)}`,
          );
        });
    } catch (error: unknown) {
      this.logger.warn(
        `New lead notification failed for ${leadId}: ${String(error)}`,
      );
    }
  }

  async updateLead(actor: ActorContext, leadId: string, dto: UpsertLeadDto) {
    this.policy.assertCanWriteCrm(actor);
    const branchId = extractBranchId(dto.customDataPatch);
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
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "updated",
      id: lead.id,
      branchId: branchId ?? before?.branch_id ?? null,
    });
    return this.toLeadDto(lead);
  }

  // Soft-delete a student (mirrors deleteLead). Enables a real undo of the
  // Лид→Ученик drag conversion: «Отменить» removes the just-created student.
  async deleteStudent(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.students
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [studentId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Ученик не найден.");
    await this.audit.record({
      actor,
      action: "crm.student_deleted",
      entityType: "student",
      entityId: row.id,
    });
    this.realtime.emitCrmChanged({
      entity: "student",
      action: "deleted",
      id: row.id,
    });
    return { success: true };
  }

  async returnStudentToLead(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    const current = await this.database.query<{
      id: string;
      lead_id: string | null;
      branch_id: string | null;
      custom_data: Record<string, unknown> | null;
      first_name: string | null;
      last_name: string | null;
      email: string | null;
      phone: string | null;
    }>(
      `
        select s.id, s.lead_id, s.branch_id, s.custom_data,
          p.first_name, p.last_name, u.email, p.phone
        from app.students s
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where s.id = $1 and s.deleted_at is null
        limit 1
      `,
      [studentId],
    );
    const student = current.rows[0];
    if (!student) throw new NotFoundException("Ученик не найден.");

    const returned = await this.database.transaction(async (client) => {
      let leadId = student.lead_id;
      let created = false;
      if (leadId) {
        const existingLead = await client.query<{ id: string }>(
          `select id from app.leads where id = $1 and deleted_at is null limit 1`,
          [leadId],
        );
        if (!existingLead.rows[0]) {
          leadId = null;
        }
      }

      if (!leadId) {
        const statusRow = await client.query<{ id: string }>(
          `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
        );
        const customData = {
          ...(student.custom_data ?? {}),
          sourceStudentId: student.id,
        };
        const inserted = await client.query<{ id: string }>(
          `
            insert into app.leads (
              status_id, first_name, last_name, phone, email,
              source, notes, assigned_to, custom_data, created_by, branch_id
            )
            values ($1, $2, $3, $4, $5, 'Возврат из ученика', null, null, $6::jsonb, $7, $8)
            returning id
          `,
          [
            statusRow.rows[0]?.id ?? null,
            student.first_name,
            student.last_name,
            student.phone,
            student.email,
            JSON.stringify(customData),
            actor.userId,
            student.branch_id,
          ],
        );
        leadId = inserted.rows[0].id;
        created = true;
      }

      await client.query(
        `
          update app.students
          set deleted_at = now(), updated_at = now()
          where id = $1 and deleted_at is null
        `,
        [student.id],
      );
      return { leadId, created };
    });

    await this.audit.record({
      actor,
      action: "crm.student_returned_to_lead",
      entityType: "student",
      entityId: student.id,
      metadata: {
        leadId: returned.leadId,
        createdLead: returned.created,
      },
    });
    this.realtime.emitCrmChanged({
      entity: "student",
      action: "deleted",
      id: student.id,
      branchId: student.branch_id ?? null,
    });
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: returned.created ? "created" : "updated",
      id: returned.leadId,
      branchId: student.branch_id ?? null,
    });
    return {
      success: true,
      studentId: student.id,
      leadId: returned.leadId,
      createdLead: returned.created,
    };
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
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "deleted",
      id: row.id,
    });
    return { success: true };
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
        ${role}::text in ('manager', 'director', 'admin', 'system_admin')
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
        `${branchIdExpr('s')} = ${p}::text`,
      );
    }
    // «Без филиала» board: students with no branch on the FK column nor any
    // legacy custom_data branch key. Mutually exclusive with branchId in practice.
    if (query.noBranch) {
      filters.push(`${branchIdExpr('s')} is null`);
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
        `${branchIdExpr('l')} = ${p}::text`,
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
    if (query.hideConverted === true) {
      filters.push(`
        not exists (
          select 1
          from app.students linked_conv
          left join app.profiles p_conv
            on p_conv.id = linked_conv.profile_id
           and p_conv.deleted_at is null
          where linked_conv.deleted_at is null
            and linked_conv.status = 'active'
            and (
              linked_conv.lead_id = l.id
              or (
                l.phone_normalized is not null
                and p_conv.phone_normalized = l.phone_normalized
                and lower(btrim(coalesce(p_conv.first_name, ''))) = lower(btrim(coalesce(l.first_name, '')))
                and lower(btrim(coalesce(p_conv.last_name, '')))  = lower(btrim(coalesce(l.last_name, '')))
              )
            )
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

  private async listChatWorkTimeline(
    entityType: "student" | "lead",
    entityId: string,
  ) {
    const result = await this.database.query<TimelineRow>(
      `
        select work.id::text as id, 'chat_work'::text as type,
          case
            when work.action = 'unassigned' then 'Снято с работы'
            else 'Взято в работу'
          end as title,
          nullif(
            trim(coalesce(target_profile.first_name, '') || ' ' || coalesce(target_profile.last_name, '')),
            ''
          ) as body,
          work.action as status, null::numeric as amount,
          work.actor_user_id,
          actor_profile.first_name as actor_first_name,
          actor_profile.last_name as actor_last_name,
          work.created_at as occurred_at
        from app.chat_work_events work
        join app.chats chat on chat.id = work.chat_id and chat.deleted_at is null
        left join app.users actor_user on actor_user.id = work.actor_user_id and actor_user.deleted_at is null
        left join app.profiles actor_profile on actor_profile.user_id = actor_user.id and actor_profile.deleted_at is null
        left join app.users target_user on target_user.id = work.target_user_id and target_user.deleted_at is null
        left join app.profiles target_profile on target_profile.user_id = target_user.id and target_profile.deleted_at is null
        where chat.type = 'administration'
          and (
            ($1 = 'student' and (
              chat.student_id = $2::uuid
              or exists (
                select 1
                from app.user_crm_links link
                where link.entity_type = 'student'
                  and link.entity_id = $2::uuid
                  and link.user_id = chat.owner_user_id
                  and link.deleted_at is null
              )
            ))
            or ($1 = 'lead' and (
              chat.lead_id = $2::uuid
              or exists (
                select 1
                from app.user_crm_links link
                where link.entity_type = 'lead'
                  and link.entity_id = $2::uuid
                  and link.user_id = chat.owner_user_id
                  and link.deleted_at is null
              )
            ))
          )
        order by work.created_at desc, work.id desc
        limit 50
      `,
      [entityType, entityId],
    );
    return (result?.rows ?? []).map((row) => this.toTimelineDto(row));
  }

  private async listClientSummaryLessons(
    studentIds: string[],
  ): Promise<LessonRow[]> {
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
    return result?.rows ?? [];
  }

  private async listClientSummaryTasks(
    studentIds: string[],
  ): Promise<TaskRow[]> {
    const result = await this.database.query<TaskRow>(
      `
        select task.id, task.entity_type, task.entity_id, task.assigned_to,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          assigned_profile.id as assigned_profile_id,
          creator_profile.first_name as creator_first_name,
          creator_profile.last_name as creator_last_name,
          creator_profile.id as creator_profile_id,
          student_profile.first_name as entity_first_name,
          student_profile.last_name as entity_last_name,
          null::text as entity_name,
          task.title, task.description, task.status, task.due_at,
          task.created_by, task.created_at
        from app.tasks task
        left join app.users assigned_user on assigned_user.id = task.assigned_to and assigned_user.deleted_at is null
        left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
        left join app.users creator_user on creator_user.id = task.created_by and creator_user.deleted_at is null
        left join app.profiles creator_profile on creator_profile.user_id = creator_user.id and creator_profile.deleted_at is null
        left join app.students student on student.id = task.entity_id and student.deleted_at is null
        left join app.profiles student_profile on student_profile.id = student.profile_id and student_profile.deleted_at is null
        where task.deleted_at is null
          and task.entity_type = 'student'
          and task.entity_id = any($1::uuid[])
          and task.status not in ('done', 'completed', 'cancelled')
        order by task.due_at nulls last, task.created_at desc, task.id desc
        limit 20
      `,
      [studentIds],
    );
    return result?.rows ?? [];
  }

  private async listClientSummaryPayments(
    studentIds: string[],
  ): Promise<PaymentRow[]> {
    const result = await this.database.query<PaymentRow>(
      `
        select pay.id, pay.student_id, p.user_id as student_user_id,
          p.first_name as student_first_name, p.last_name as student_last_name,
          pay.amount, pay.currency, pay.payment_date, pay.method,
          pay.external_id, pay.notes, pay.created_by, pay.created_at
        from app.payments pay
        join app.students s on s.id = pay.student_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where pay.deleted_at is null
          and pay.student_id = any($1::uuid[])
        order by pay.payment_date desc, pay.id desc
        limit 20
      `,
      [studentIds],
    );
    return result?.rows ?? [];
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

  /**
   * KVA-156: students linked to the account-holder via Families.
   *
   * The account-holder's user maps to a profile (app.profiles.user_id). We find
   * the active families where that profile is a parent/payer member, then return
   * the active STUDENT members of those families. Only active rows are
   * considered (deleted_at is null on families, family_members and students),
   * and the result shape mirrors listClientStudents so toStudentDto stays valid.
   */
  private async listFamilyLinkedStudents(
    userId: string,
  ): Promise<StudentRow[]> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          '{}'::uuid[] as teacher_user_ids
        from app.profiles acct
        join app.family_members parent_m
          on parent_m.entity_type = 'profile'
          and parent_m.entity_id = acct.id
          and parent_m.role in ('parent', 'payer')
          and parent_m.deleted_at is null
        join app.families f
          on f.id = parent_m.family_id and f.deleted_at is null
        join app.family_members child_m
          on child_m.family_id = f.id
          and child_m.entity_type = 'student'
          and child_m.deleted_at is null
        join app.students s
          on s.id = child_m.entity_id and s.deleted_at is null
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where acct.user_id = $1 and acct.deleted_at is null
        order by s.created_at desc
      `,
      [userId],
    );
    return result.rows;
  }

  private async listManuallyLinkedStudents(
    userId: string,
  ): Promise<StudentRow[]> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          '{}'::uuid[] as teacher_user_ids
        from app.user_crm_links link
        join app.students s
          on s.id = link.entity_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where link.user_id = $1
          and link.entity_type = 'student'
          and link.deleted_at is null
        order by s.created_at desc
      `,
      [userId],
    );
    return result.rows;
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

  private async assertCanReadEntityComments(
    actor: ActorContext,
    entityType: string,
    entityId: string,
  ) {
    if (entityType === "student") {
      const student = await findStudent(this.database, entityId);
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
    kind: string,
  ) {
    // Staff (manager/admin) may write any stream.
    if (isManagerOrAdminRole(actor.role)) {
      this.policy.assertCanWriteCrm(actor);
      await this.assertEntityExistsForComment(dto.entityType, dto.entityId);
      return;
    }

    // Teachers may write their own «Заметки преподавателя» (teacher_note) and
    // client-visible progress notes — but NEVER administrator comments.
    if (
      actor.role === "teacher" &&
      dto.entityType === "student" &&
      (kind === "teacher_note" || kind === "progress")
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
      const student = await findStudent(this.database, entityId);
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
    // Defense-in-depth on customData (JSONB): bound depth/breadth/string size so
    // a pathological patch can't bloat the row or DoS queries (KVA).
    this.assertJsonWithinLimits(value, 0);
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).filter(
        ([, entryValue]) => entryValue !== undefined,
      ),
    );
  }

  private assertJsonWithinLimits(value: unknown, depth: number): void {
    const MAX_DEPTH = 6;
    const MAX_KEYS = 100;
    const MAX_STRING = 10_000;
    if (depth > MAX_DEPTH) {
      throw new BadRequestException("customData: слишком глубокая вложенность.");
    }
    if (typeof value === "string") {
      if (value.length > MAX_STRING) {
        throw new BadRequestException("customData: слишком длинное значение.");
      }
      return;
    }
    if (Array.isArray(value)) {
      if (value.length > MAX_KEYS) {
        throw new BadRequestException("customData: слишком большой массив.");
      }
      for (const item of value) this.assertJsonWithinLimits(item, depth + 1);
      return;
    }
    if (value && typeof value === "object") {
      const keys = Object.keys(value as Record<string, unknown>);
      if (keys.length > MAX_KEYS) {
        throw new BadRequestException("customData: слишком много полей.");
      }
      for (const key of keys) {
        this.assertJsonWithinLimits(
          (value as Record<string, unknown>)[key],
          depth + 1,
        );
      }
    }
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

  // ponytail: import placeholders (hollihop-client-*@migration.invalid etc.) are
  // real students/leads without a HolliHop email. Hide the fake address from the
  // UI instead of showing noise — never delete the record.
  private presentableEmail(value: string | null | undefined): string | null {
    return value && this.isDeliverableEmail(value) ? value : null;
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
      email: this.presentableEmail(row.email),
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
      disciplines: row.disciplines ?? [],
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
    // KVA-238: зарплатные поля и явные связи карточки педагога.
    if (row.salary !== undefined) {
      teacher.salary = row.salary === null ? null : Number(row.salary);
    }
    if (row.current_rate !== undefined) {
      teacher.currentRate =
        row.current_rate === null ? null : Number(row.current_rate);
    }
    if (row.disciplines !== undefined) {
      teacher.disciplines = row.disciplines ?? [];
    }
    if (row.assigned_branches !== undefined) {
      teacher.assignedBranches = row.assigned_branches ?? [];
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
      teacherRate:
        row.teacher_rate === null || row.teacher_rate === undefined
          ? null
          : Number(row.teacher_rate),
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
      assignedProfileId: row.assigned_profile_id ?? null,
      creatorProfileId: row.creator_profile_id ?? null,
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
      kind: row.kind,
      // Back-compat flag for clients still keying off `progress`.
      progress: row.kind === "progress",
      createdAt: row.created_at,
    };
  }

  // Comment kinds this role may read for an entity. admin_comment is staff-only
  // (teachers/clients never see it); teacher_note is teacher + staff; progress is
  // visible to everyone including the client.
  private allowedCommentKinds(role: ActorContext["role"]): string[] {
    if (isManagerOrAdminRole(role)) {
      return ["admin_comment", "teacher_note", "progress"];
    }
    if (role === "teacher") return ["teacher_note", "progress"];
    return ["progress"];
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

  private toLeadDto(row: LeadRow) {
    return {
      id: row.id,
      statusId: row.status_id,
      statusName: row.status_name,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      email: this.presentableEmail(row.email),
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

  private toGroupDto(row: GroupRow) {
    return {
      id: row.id,
      teacherId: row.teacher_id,
      branchId: row.branch_id,
      roomId: row.room_id,
      name: row.name,
      pricePerLesson:
        row.price_per_lesson === null ? null : Number(row.price_per_lesson),
      // KVA-238: null = брать ставку педагога, 0 = «входит в оклад».
      teacherRate:
        row.teacher_rate === null || row.teacher_rate === undefined
          ? null
          : Number(row.teacher_rate),
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
      requiresReason: row.requires_reason ?? false,
      isTerminal: row.is_terminal ?? false,
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
    await this.audit.record({
      actor,
      action: "crm.family_member_added",
      entityType: "family",
      entityId: familyId,
      metadata: {
        memberId: row.id,
        entityType: dto.entityType,
        entityId: dto.entityId,
        role: dto.role,
      },
    });
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
    await this.audit.record({
      actor,
      action: "crm.family_member_removed",
      entityType: "family_member",
      entityId: memberId,
    });
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
    await this.audit.record({
      actor,
      action: "crm.family_primary_payer_set",
      entityType: "family",
      entityId: familyId,
      metadata: { memberId },
    });
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
  // Uses a pg advisory lock (per-user) to serialize concurrent first messages
  // so that both the check and the create happen inside a single transaction,
  // preventing duplicate leads from a race between two rapid chat messages.
  async autoCreateLeadFromChat(
    actor: ActorContext,
    senderUserId: string,
  ): Promise<{ leadId: string | null; created: boolean }> {
    type Sentinel =
      | { linkedLeadId: string | null }
      | { noProfile: true }
      | { createdLeadId: string; leadName: string };

    const sentinel = await this.database.transaction<Sentinel>(async (client) => {
      // 1. Acquire an advisory lock scoped to this transaction — serializes
      //    concurrent autoCreateLeadFromChat calls for the same senderUserId.
      await client.query(
        `select pg_advisory_xact_lock(hashtext($1))`,
        [`autolead:${senderUserId}`],
      );

      // 2. Re-check the link inside the transaction (after the lock is held).
      const linkedRes = await client.query<{ entity_type: string; entity_id: string }>(
        `select entity_type, entity_id from app.user_crm_links
          where user_id = $1 and entity_type in ('lead', 'student') and deleted_at is null
          limit 1`,
        [senderUserId],
      );
      if (linkedRes.rows[0]) {
        const existing = linkedRes.rows[0];
        return {
          linkedLeadId: existing.entity_type !== "student" ? existing.entity_id : null,
        };
      }

      // 3. Fetch the user profile.
      const profileRes = await client.query<{
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
      if (!profile) return { noProfile: true };

      // 4. Look up the «Новый» status (null fallback is fine).
      const statusRes = await client.query<{ id: string }>(
        `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
      );
      const newStatusId = statusRes.rows[0]?.id ?? null;
      const matchedPhone = this.normalizeContactPhone(profile.phone);

      // 5. Insert the lead and the link row in the same transaction.
      const insertedLead = await client.query<{ id: string }>(
        `insert into app.leads (first_name, last_name, phone, source, status_id, created_by)
         values ($1, $2, $3, 'Через приложение', $4, $5)
         returning id`,
        [profile.first_name, profile.last_name, profile.phone, newStatusId, actor.userId],
      );
      const createdLeadId = insertedLead.rows[0].id;
      await client.query(
        `insert into app.user_crm_links
           (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
         values ($1, 'lead', $2, $3, 'auto_phone', $4, now())
         on conflict do nothing`,
        [senderUserId, createdLeadId, matchedPhone, actor.userId],
      );
      return {
        createdLeadId,
        leadName:
          [profile.first_name, profile.last_name].filter(Boolean).join(" ").trim() ||
          "Без имени",
      };
    });

    if ("linkedLeadId" in sentinel) {
      return { leadId: sentinel.linkedLeadId, created: false };
    }
    if ("noProfile" in sentinel) {
      return { leadId: null, created: false };
    }

    // 6. Audit only on actual creation, outside the transaction.
    await this.audit.record({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: sentinel.createdLeadId,
      metadata: { fromApp: true, userId: senderUserId },
    });
    this.notifyNewLeadSafe(sentinel.createdLeadId, sentinel.leadName, "Через приложение");
    return { leadId: sentinel.createdLeadId, created: true };
  }

  // Public site form → lead. No actor: the caller is the webhook endpoint
  // authenticated by a shared secret, so created_by stays null and the funnel
  // entry status «Новый» is stamped like the chat-created leads do.
  async createLeadFromSiteWebhook(dto: {
    name: string;
    phone: string;
    email?: string;
    discipline?: string;
    comment?: string;
    source?: string;
  }): Promise<{ leadId: string }> {
    // Keep the canonical +7 form when the phone normalizes, otherwise store
    // the raw value — losing a site lead over formatting is worse than a
    // messy phone that a manager can fix by hand.
    const phone = normalizePhoneRu(dto.phone).canonical ?? dto.phone.trim();
    const source = dto.source?.trim() || "site";
    const notes =
      [
        dto.discipline?.trim() ? `Дисциплина: ${dto.discipline.trim()}` : null,
        dto.comment?.trim() || null,
      ]
        .filter(Boolean)
        .join("\n") || null;
    const statusRow = await this.database.query<{ id: string }>(
      `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
    );
    const inserted = await this.database.query<{ id: string }>(
      `
        insert into app.leads (first_name, phone, email, source, notes, status_id)
        values ($1, $2, $3, $4, $5, $6)
        returning id
      `,
      [
        dto.name.trim(),
        phone,
        dto.email?.trim().toLowerCase() || null,
        source,
        notes,
        statusRow.rows[0]?.id ?? null,
      ],
    );
    const leadId = inserted.rows[0].id;
    await this.audit.record({
      action: "crm.lead_created",
      entityType: "lead",
      entityId: leadId,
      metadata: { fromSiteWebhook: true, source },
    });
    this.realtime.emitCrmChanged({ entity: "lead", action: "created", id: leadId });
    this.notifyNewLeadSafe(leadId, dto.name.trim(), source);
    return { leadId };
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

  // ──────────────────────────────────────────────────────────────────────────
  // Client (lead/student) ↔ app user links. The reverse of profile→entity
  // linking: here staff link an app user to a CRM client by matching phone, so
  // the card can show "linked user" + a chat target.
  // ──────────────────────────────────────────────────────────────────────────

  private assertClientEntityType(
    entityType: string,
  ): asserts entityType is "lead" | "student" {
    if (entityType !== "lead" && entityType !== "student") {
      throw new BadRequestException(
        "Тип сущности должен быть 'lead' или 'student'.",
      );
    }
  }

  // The client's raw phone: leads carry it directly, students inherit it from
  // their linked profile.
  private async getClientPhone(
    entityType: "lead" | "student",
    entityId: string,
  ): Promise<string | null> {
    if (entityType === "lead") {
      const result = await this.database.query<{ phone: string | null }>(
        `
          select phone
          from app.leads
          where id = $1 and deleted_at is null
          limit 1
        `,
        [entityId],
      );
      return result.rows[0]?.phone ?? null;
    }
    const result = await this.database.query<{ phone: string | null }>(
      `
        select p.phone
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where s.id = $1 and s.deleted_at is null
        limit 1
      `,
      [entityId],
    );
    return result.rows[0]?.phone ?? null;
  }

  // App users currently linked to this client (via user_crm_links). For a
  // student we also fold in the student's own app account (their profile owner),
  // which may not have an explicit link row.
  async getClientLinkedUsers(
    actor: ActorContext,
    entityType: string,
    entityId: string,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    this.assertClientEntityType(entityType);

    const linked = await this.database.query<{
      user_id: string;
      name: string;
      phone: string | null;
      link_source: string;
    }>(
      `
        select link.user_id,
          coalesce(
            nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
            u.email,
            'Пользователь'
          ) as name,
          p.phone,
          link.link_source
        from app.user_crm_links link
        join app.users u on u.id = link.user_id
          and u.deleted_at is null
          and u.is_app_account = true
        left join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where link.deleted_at is null
          and link.entity_type = $1::app.crm_entity_type
          and link.entity_id = $2
        order by link.created_at desc, link.id desc
      `,
      [entityType, entityId],
    );

    const items = linked.rows.map((row) => ({
      userId: row.user_id,
      name: row.name,
      phone: row.phone,
      linkSource: row.link_source,
    }));

    if (entityType === "student") {
      const own = await this.database.query<{
        user_id: string;
        name: string;
        phone: string | null;
      }>(
        `
          select u.id as user_id,
            coalesce(
              nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
              u.email,
              'Пользователь'
            ) as name,
            p.phone
          from app.students s
          join app.profiles p on p.id = s.profile_id and p.deleted_at is null
          join app.users u on u.id = p.user_id
            and u.deleted_at is null
            and u.is_app_account = true
          where s.id = $1 and s.deleted_at is null
          limit 1
        `,
        [entityId],
      );
      const self = own.rows[0];
      if (self && !items.some((item) => item.userId === self.user_id)) {
        items.push({
          userId: self.user_id,
          name: self.name,
          phone: self.phone,
          linkSource: "self",
        });
      }
    }

    return { items };
  }

  // App users whose normalized phone matches the client's, excluding those
  // already linked to this entity. Empty when the client has no usable phone.
  async listClientUserCandidates(
    actor: ActorContext,
    entityType: string,
    entityId: string,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    this.assertClientEntityType(entityType);

    const rawPhone = await this.getClientPhone(entityType, entityId);
    const normalizedPhone = this.normalizeContactPhone(rawPhone);
    if (!normalizedPhone) {
      return { items: [] };
    }

    const result = await this.database.query<{
      user_id: string;
      name: string;
      phone: string | null;
      email: string | null;
    }>(
      `
        select u.id as user_id,
          coalesce(
            nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''),
            u.email,
            'Пользователь'
          ) as name,
          p.phone,
          u.email
        from app.users u
        join app.profiles p on p.user_id = u.id and p.deleted_at is null
        where u.deleted_at is null
          and u.is_app_account = true
          and ${normalizedPhoneExpr('p.phone')} = $1
          and not exists (
            select 1
            from app.user_crm_links existing
            where existing.entity_type = $2::app.crm_entity_type
              and existing.entity_id = $3
              and existing.deleted_at is null
              and existing.user_id = u.id
          )
        order by u.created_at desc, u.id desc
        limit 50
      `,
      [normalizedPhone, entityType, entityId],
    );

    return {
      items: result.rows.map((row) => ({
        userId: row.user_id,
        name: row.name,
        phone: row.phone,
        email: row.email,
      })),
    };
  }

  // Manually link an app user to a client. Upserts on the active
  // (entity_type, entity_id) unique index so one client maps to one user.
  async linkUserToClient(
    actor: ActorContext,
    entityType: string,
    entityId: string,
    userId: string,
  ) {
    this.policy.assertCanWriteCrm(actor);
    this.assertClientEntityType(entityType);

    const userRow = await this.database.query<{ id: string }>(
      `
        select id
        from app.users
        where id = $1 and deleted_at is null and is_app_account = true
        limit 1
      `,
      [userId],
    );
    if (!userRow.rows[0]) {
      throw new BadRequestException(
        "Пользователь приложения не найден.",
      );
    }

    const rawPhone = await this.getClientPhone(entityType, entityId);
    const matchedPhone = this.normalizeContactPhone(rawPhone);

    await this.database.query(
      `
        insert into app.user_crm_links
          (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
        values ($1, $2::app.crm_entity_type, $3, $4, 'manual_phone', $5, now())
        on conflict (entity_type, entity_id) where deleted_at is null
        do update set
          user_id = excluded.user_id,
          matched_phone = excluded.matched_phone,
          link_source = 'manual_phone',
          deleted_at = null,
          confirmed_at = now()
      `,
      [userId, entityType, entityId, matchedPhone, actor.userId],
    );

    await this.audit.record({
      actor,
      action: "crm.client_user_linked",
      entityType,
      entityId,
      metadata: { userId },
    });

    return this.getClientLinkedUsers(actor, entityType, entityId);
  }
}
