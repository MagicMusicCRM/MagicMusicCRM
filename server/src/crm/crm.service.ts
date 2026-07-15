import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { AuditService } from "../audit/audit.service";
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
import { StudentSearchQuery } from "./dto/student-search.query";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { CrmPolicy } from "./crm.policy";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { TasksService } from "./tasks.service";
import { ScheduleService } from "./schedule.service";
import { TimelineService } from "./timeline.service";

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

@Injectable()
export class CrmService {
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

  // ponytail: generic case-insensitive text-filter helper (misnamed "Lead" for
  // history). Copied for buildStudentSearchFilter; LeadsService keeps its own.
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

  private toNumericStat(value: string | number | null | undefined): number {
    if (value === null || value === undefined) return 0;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }

}
