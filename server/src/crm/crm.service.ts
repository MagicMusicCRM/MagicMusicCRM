import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { AuditService } from "../audit/audit.service";
import { LeadIntakePort } from "../common/lead-intake.port";
import { branchIdExpr, extractBranchId } from "./branch-scope";
import {
  rethrowCreatePersonError,
  requiredTrim,
  sanitizeJsonObject,
  trimOptional,
} from "./crm-util";
import { audienceForStudent } from "./audience";
import { StudentRow, findStudent } from "./student-read";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CreateStudentDto } from "./dto/create-student.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { StudentSearchQuery } from "./dto/student-search.query";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { UpsertLeadDto } from "./dto/upsert-lead.dto";
import { CrmPolicy } from "./crm.policy";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { TasksService } from "./tasks.service";
import { ScheduleService } from "./schedule.service";
import { TimelineService } from "./timeline.service";
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
    private readonly schedule: ScheduleService,
    private readonly timeline: TimelineService,
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
    const firstName = requiredTrim(
      dto.firstName,
      "Имя ученика обязательно.",
    );
    const lastName = trimOptional(dto.lastName);
    const phone = trimOptional(dto.phone);
    const email = trimOptional(dto.email)?.toLowerCase() ?? null;
    const status = trimOptional(dto.status) ?? "active";
    const fullName = [firstName, lastName].filter(Boolean).join(" ");
    const leadId = dto.leadId ?? null;
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
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
      rethrowCreatePersonError(error);
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
      this.schedule.listLessons(actor, { studentId, limit: 100 }),
      canReadFinance
        ? this.finance.listPayments(actor, { studentId, limit: 100 }).catch(() => emptyList)
        : Promise.resolve(emptyList),
      this.tasks.listTasks(actor, { studentId, limit: 100 }),
      this.timeline.listComments(actor, {
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
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
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
        trimOptional(dto.firstName),
        trimOptional(dto.lastName),
        trimOptional(dto.phone),
        trimOptional(dto.email)?.toLowerCase() ?? null,
        trimOptional(dto.status),
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

    const email = trimOptional(student.email ?? undefined)?.toLowerCase();
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
        sanitizeJsonObject(dto.customDataPatch),
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
        sanitizeJsonObject(dto.customDataPatch),
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

}
