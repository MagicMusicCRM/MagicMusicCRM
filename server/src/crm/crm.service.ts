import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { AuditService } from "../audit/audit.service";
import { extractBranchId } from "./branch-scope";
import {
  rethrowCreatePersonError,
  requiredTrim,
  sanitizeJsonObject,
  trimOptional,
} from "./crm-util";
import { audienceForStudent } from "./audience";
import { APPEAL_KEY, resolveAppealDate } from "./appeal-date";
import { ensureResponsibleSafe } from "./responsible";
import {
  applyEligibleResponsibleToCustomData,
  assertEligibleResponsible,
  responsibleUserIdFromCustomDataPatch,
} from "./responsible-eligibility";
import {
  diffEntityFields,
  isDeliverableEmail,
  toTimelineDto,
} from "./crm-mappers";
import {
  ValidatedCustomFields,
  ValidatedStudentCreate,
} from "./clients/client-write.validator";
import {
  replaceTypedClientValues,
  saveTypedClientValues,
} from "./clients/client-config.repository";

/**
 * Student fields worth an audit entry. Name/phone/email live on
 * profiles/users, but they are what staff edit on the card, so they are audited
 * as the student's fields. custom_data is diffed per key by diffEntityFields.
 */
const STUDENT_AUDITED_FIELDS = [
  "status",
  "first_name",
  "last_name",
  "phone",
  "email",
];
import { StudentRow, findStudent } from "./student-read";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { ChatWorkTimelineService } from "../messenger/chat-work-timeline.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CreateStudentDto } from "./dto/create-student.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { StudentSearchQuery } from "./dto/student-search.query";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { CrmPolicy } from "./crm.policy";
import { SharedTaskService } from "./tasks/shared-task.service";
import { ScheduleReadService } from "./schedule/schedule-read.service";
import { TimelineService } from "./timeline.service";
import { StudentFunnelService } from "./student-funnel.service";
import {
  toStudentDto,
} from "./students/student-presenter";
import { StudentDirectoryService } from "./students/student-directory.service";

@Injectable()
export class CrmService {
  private readonly logger = new Logger(CrmService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly directory: StudentDirectoryService,
    private readonly tasks: SharedTaskService,
    private readonly scheduleRead: ScheduleReadService,
    private readonly timeline: TimelineService,
    private readonly notifications: NotificationsService,
    private readonly chatWork: ChatWorkTimelineService,
    private readonly realtime: RealtimeBus,
    private readonly studentFunnel: StudentFunnelService,
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
    // Commerce has its own actor-scoped projection boundary. The base self
    // summary only composes the non-financial lesson/task sections.
    let upcomingLessons: unknown[] = [];
    let openTasks: unknown[] = [];
    if (studentIds.length) {
      [upcomingLessons, openTasks] = await Promise.all([
        this.scheduleRead
          .listUpcomingLessonsForStudents(studentIds)
          .catch(() => []),
        Promise.all(
          studentIds.map((studentId) =>
            this.tasks.list(actor, {
              state: "open",
              linkedEntityType: "student",
              linkedEntityId: studentId,
              limit: 20,
            }),
          ),
        )
          .then((results) => results.flatMap((result) => result.items))
          .catch(() => []),
      ]);
    }

    return {
      students: students.map((row) => toStudentDto(row)),
      upcomingLessons,
      tasks: openTasks,
    };
  }

  listStudents(actor: ActorContext, query: CrmListQuery) {
    return this.directory.listStudents(actor, query);
  }

  searchStudents(
    actor: ActorContext,
    query: StudentSearchQuery,
  ) {
    return this.directory.searchStudents(actor, query);
  }

  async createStudent(
    actor: ActorContext,
    dto: CreateStudentDto,
    validated?: ValidatedStudentCreate,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const firstName = requiredTrim(dto.firstName, "Имя ученика обязательно.");
    const lastName = trimOptional(dto.lastName);
    const phone = trimOptional(dto.phone);
    const email = trimOptional(dto.email)?.toLowerCase() ?? null;
    const status = trimOptional(dto.status) ?? "active";
    const fullName = [firstName, lastName].filter(Boolean).join(" ");
    const leadId = dto.leadId ?? null;
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
    const requestedResponsibleId =
      responsibleUserIdFromCustomDataPatch(customDataPatch);
    const branchId = extractBranchId(dto.customDataPatch);

    if (leadId) {
      const lead = await this.database.query<{
        id: string;
        custom_data: Record<string, unknown> | null;
        created_at: Date | string;
      }>(
        "select id, custom_data, created_at from app.leads where id = $1 and deleted_at is null limit 1",
        [leadId],
      );
      const leadRow = lead.rows[0];
      if (!leadRow) throw new NotFoundException("Лид не найден.");

      const existingStudent = await this.database.query<{ id: string }>(
        "select id from app.students where lead_id = $1 and deleted_at is null limit 1",
        [leadId],
      );
      if (existingStudent.rows[0]) {
        throw new ConflictException("Этот лид уже конвертирован в ученика.");
      }

      // ✔ Решение владельца 16.07: «дату обращения оставляем на стороне
      // students». Конвертация — единственный момент, когда её ещё можно
      // узнать, поэтому здесь она и фиксируется: у импортированного лида это
      // исходная дата HolliHop, у пришедшего через приложение — момент, когда
      // он стал тут лидом. Явное значение от клиента не трогаем.
      if (!customDataPatch[APPEAL_KEY]) {
        const appeal = resolveAppealDate(
          leadRow.custom_data,
          leadRow.created_at,
        );
        if (appeal.value) customDataPatch[APPEAL_KEY] = appeal.value;
      }
    }

    try {
      const result = await this.database.transaction(async (client) => {
        await this.studentFunnel.assertCreateStatus(client, branchId, status);
        if (leadId) {
          await client.query(
            "select pg_advisory_xact_lock(hashtextextended($1::uuid::text, 0))",
            [leadId],
          );
          const existingStudent = await client.query<{ id: string }>(
            "select id from app.students where lead_id = $1 and deleted_at is null limit 1",
            [leadId],
          );
          if (existingStudent.rows[0]) {
            throw new ConflictException(
              "Этот лид уже конвертирован в ученика.",
            );
          }
        }
        let transactionCustomData = { ...customDataPatch };
        if (requestedResponsibleId) {
          const responsible = await assertEligibleResponsible(
            client,
            requestedResponsibleId,
            { lock: true },
          );
          transactionCustomData = applyEligibleResponsibleToCustomData(
            transactionCustomData,
            responsible,
          );
        }
        const inserted = await client.query<StudentRow>(
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
            insert into app.students (
              profile_id, status, lead_id, custom_data, branch_id, source_id
            )
            select id, $6, $7, $8::jsonb, $9::uuid, $10::uuid
            from inserted_profile
            returning id, status, profile_id, lead_id, source_id, custom_data, created_at,
              blacklisted, blacklist_reason
          ),
          inserted_student_link as (
            insert into app.user_crm_links (
              user_id, entity_type, entity_id, link_source, created_by, confirmed_at
            )
            select linked.user_id, 'student', s.id, 'manual_phone',
              linked.created_by, now()
            from inserted_student s
            join lateral (
              select ucl.user_id, ucl.created_by
              from app.user_crm_links ucl
              where ucl.entity_type = 'lead'
                and ucl.entity_id = s.lead_id
                and ucl.deleted_at is null
              order by ucl.confirmed_at desc nulls last, ucl.created_at desc
              limit 1
            ) linked on true
            where s.lead_id is not null
            on conflict do nothing
            returning entity_id
          )
          select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
            s.lead_id, s.source_id, source.display_name as source_name,
            s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
            '{}'::uuid[] as teacher_user_ids
          from inserted_student s
          join inserted_profile p on p.id = s.profile_id
          join inserted_user u on u.id = p.user_id
          left join app.lead_sources source on source.id = s.source_id
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
            JSON.stringify(transactionCustomData),
            branchId,
            validated?.sourceId ?? null,
          ],
        );
        if (validated) {
          await saveTypedClientValues(
            client,
            "student",
            inserted.rows[0]!.id,
            validated.customFields,
          );
        }
        return inserted;
      });
      const student = result.rows[0];
      // Chat re-bucketing is part of the insert CTE above, so conversion and
      // the student user_crm_link commit (or roll back) together.
      // Contract 5: creating admin/manager/director becomes «Ответственный»
      // when the card has none. Await before audit/realtime publication.
      if (!requestedResponsibleId) {
        await ensureResponsibleSafe(
          this.database,
          actor,
          "student",
          student.id,
        );
      }
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
      return {
        ...toStudentDto(student),
        ...(validated ? { warnings: validated.warnings } : {}),
      };
    } catch (error) {
      rethrowCreatePersonError(error);
    }
  }

  /** Read one student subject to the regular row-level policy. */
  getStudent(actor: ActorContext, studentId: string) {
    return this.directory.getStudent(actor, studentId);
  }

  async getStudentCard(actor: ActorContext, studentId: string) {
    const student = await findStudent(this.database, studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");
    this.policy.assertCanReadStudent(actor, {
      profileUserId: student.profile_user_id,
      teacherUserIds: student.teacher_user_ids ?? [],
    });

    // Commerce is projected separately at /crm/students/:id/commerce. Keeping
    // the base card finance-free prevents mixed-scope DTOs and cache entries.
    // ScheduleReadService owns the detailed actor-scoped lesson list; the
    // legacy schedule dependency remains only for the distinct upcoming query.
    const emptyList = { items: [] as never[] };

    const [groups, lessons, tasks, comments, links, chatWork, fieldAudit] =
      await Promise.all([
        this.listStudentGroups(actor, studentId, { limit: 100 }),
        this.scheduleRead.listLessons(actor, { studentId, limit: 100 }),
        this.tasks.list(actor, {
          linkedEntityType: "student",
          linkedEntityId: studentId,
          limit: 100,
        }),
        this.timeline
          .listComments(actor, {
            entityType: "student",
            entityId: studentId,
            limit: 100,
          })
          .catch(() => emptyList),
        this.listUserCrmLinks("student", studentId),
        this.listChatWorkTimeline("student", studentId),
        // Field edits («кто поменял телефон»). Returns empty for non-staff, and
        // is caught like the other optional sections: a missing audit list must
        // not take the whole card down.
        this.timeline
          .listFieldAudit(actor, "student", studentId, 50)
          .catch(() => emptyList),
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
        body: task.body,
        status: task.state,
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
      ...chatWork,
      ...fieldAudit.items.map((entry) => ({
        id: String(entry.id),
        type: "audit",
        title: String(entry.title),
        body: entry.body === null ? null : String(entry.body),
        status: null,
        occurredAt: entry.occurredAt,
      })),
    ].sort(
      (a, b) =>
        new Date(String(b.occurredAt)).getTime() -
        new Date(String(a.occurredAt)).getTime(),
    );

    return {
      student: toStudentDto(student),
      groups: groups.items,
      lessons: lessons.items,
      tasks: tasks.items,
      comments: comments.items,
      links,
      timeline,
    };
  }

  listStudentGroups(
    actor: ActorContext,
    studentId: string,
    query: CrmListQuery,
  ) {
    return this.directory.listStudentGroups(actor, studentId, query);
  }

  async updateStudent(
    actor: ActorContext,
    studentId: string,
    dto: UpdateStudentDto,
    customFields?: ValidatedCustomFields,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const initialCustomData = sanitizeJsonObject(dto.customDataPatch);
    const requestedResponsibleId = dto.clearResponsible
      ? undefined
      : responsibleUserIdFromCustomDataPatch(initialCustomData);
    const branchId = extractBranchId(dto.customDataPatch);
    // The update and its status-history row must land atomically: a failure in
    // between would change the status while silently dropping the history.
    const { beforeStudent, result } = await this.database.transaction(
      async (client) => {
        // Reads every editable field, not just status: the audit diff below is
        // what makes «кто поменял телефон» answerable, and it can only report
        // fields it saw beforehand. A student's name/phone/email live on
        // profiles/users, so the join is part of the snapshot.
        const before =
          (
            await client.query<{
              status: string | null;
              branch_id: string | null;
              first_name: string | null;
              last_name: string | null;
              phone: string | null;
              email: string | null;
              custom_data: Record<string, unknown> | null;
            }>(
              `select s.status, s.branch_id, s.custom_data,
                 p.first_name, p.last_name, p.phone, u.email
               from app.students s
               left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
               left join app.users u on u.id = p.user_id and u.deleted_at is null
               where s.id = $1 and s.deleted_at is null
               for update of s`,
              [studentId],
            )
          ).rows[0] ?? null;
        if (before && dto.status != null) {
          await this.studentFunnel.assertTransition(
            client,
            branchId ?? before.branch_id,
            before.status,
            dto.status.trim(),
          );
        } else if (before && branchId && branchId !== before.branch_id) {
          await this.studentFunnel.assertCreateStatus(
            client,
            branchId,
            before.status ?? "",
          );
        }
        if (dto.sourceId) {
          const source = await client.query<{ display_name: string }>(
            `select display_name from app.lead_sources
             where id = $1 and is_active and deleted_at is null limit 1`,
            [dto.sourceId],
          );
          if (!source.rows[0]) {
            throw new UnprocessableEntityException({
              code: "SOURCE_INACTIVE",
              field: "sourceId",
              message: "Выберите активный источник.",
            });
          }
        }
        let customDataPatch = { ...initialCustomData };
        if (before && requestedResponsibleId) {
          const responsible = await assertEligibleResponsible(
            client,
            requestedResponsibleId,
            { lock: true },
          );
          customDataPatch = applyEligibleResponsibleToCustomData(
            customDataPatch,
            responsible,
          );
        }
        const updated = await client.query<StudentRow>(
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
            custom_data = case when $9::boolean then
                (coalesce(s.custom_data, '{}'::jsonb) || $7::jsonb)
                  - 'responsible' - 'responsibleUserId' - 'responsibleName'
              else coalesce(s.custom_data, '{}'::jsonb) || $7::jsonb end,
            branch_id = coalesce($8::uuid, s.branch_id),
            source_id = coalesce($10::uuid, s.source_id),
            updated_at = now()
          from target
          where s.id = target.id
          returning s.id, s.status, s.profile_id, s.lead_id, s.source_id, s.custom_data,
            s.blacklisted, s.blacklist_reason, s.created_at
        )
        select us.id, us.status, us.profile_id,
          coalesce(updated_profile_dependency.user_id, p.user_id) as profile_user_id,
          us.lead_id, us.source_id, source.display_name as source_name,
          us.custom_data, us.blacklisted, us.blacklist_reason,
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
        left join app.lead_sources source on source.id = us.source_id
        left join app.lessons l on l.student_id = s.id and l.deleted_at is null
        left join app.teachers t on t.id = l.teacher_id and t.deleted_at is null
        left join app.profiles tp on tp.id = t.profile_id and tp.deleted_at is null
        group by us.id, us.status, us.profile_id, us.lead_id, us.source_id, us.custom_data,
          us.blacklisted, us.blacklist_reason, us.created_at, p.id, u.id,
          updated_profile_dependency.user_id,
          updated_profile_dependency.first_name,
          updated_profile_dependency.last_name,
          updated_profile_dependency.phone,
          updated_user_dependency.email, source.id
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
            dto.clearResponsible ?? false,
            dto.sourceId ?? null,
          ],
        );
        const updatedStudent = updated.rows[0];
        if (updatedStudent && customFields) {
          await replaceTypedClientValues(
            client,
            "student",
            studentId,
            customFields.values,
          );
        }
        if (
          updatedStudent &&
          before &&
          before.status !== updatedStudent.status
        ) {
          await client.query(
            `insert into app.student_status_history (student_id, status, branch_id)
         values ($1, $2, $3)`,
            [studentId, updatedStudent.status, branchId ?? before.branch_id],
          );
        }
        return { beforeStudent: before, result: updated };
      },
    );
    const student = result.rows[0];
    if (!student) throw new NotFoundException("Ученик не найден.");
    // Contract 5: an upsert by admin/manager/director claims the empty
    // «Ответственный» slot (never overwrites an existing one).
    if (!dto.clearResponsible && !requestedResponsibleId) {
      await ensureResponsibleSafe(this.database, actor, "student", student.id);
    }
    await this.audit.record({
      actor,
      action: "crm.student_updated",
      entityType: "student",
      entityId: student.id,
      // The diff is the event — see the same note in LeadsService.updateLead.
      metadata: {
        changes: beforeStudent
          ? diffEntityFields(
              beforeStudent as unknown as Record<string, unknown>,
              student as unknown as Record<string, unknown>,
              STUDENT_AUDITED_FIELDS,
            )
          : [],
        customFieldDefinitionIds:
          customFields?.values.map((value) => value.definitionId) ?? [],
      },
    });
    this.realtime.emitCrmChanged({
      entity: "student",
      action: "updated",
      id: student.id,
      branchId: branchId ?? beforeStudent?.branch_id ?? null,
    });
    return {
      ...toStudentDto(student),
      ...(customFields ? { warnings: customFields.warnings } : {}),
    };
  }

  async inviteStudent(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    const student = await findStudent(this.database, studentId);
    if (!student) throw new NotFoundException("Ученик не найден.");

    const email = trimOptional(student.email ?? undefined)?.toLowerCase();
    if (!email || !isDeliverableEmail(email)) {
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

  listGroupStudents(
    actor: ActorContext,
    groupId: string,
    query: CrmListQuery,
  ) {
    return this.directory.listGroupStudents(actor, groupId, query);
  }

  // Kept temporarily for compatibility with already released clients. Direct
  // lifecycle reversal is unsafe until it has a dependency preview and an
  // explicit archival plan for lessons, subscriptions and financial facts.
  async deleteStudent(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    void studentId;
    throw new ConflictException(
      "Прямое удаление ученика отключено. Используйте управляемое архивирование с предварительной проверкой связанных занятий, абонементов и финансовых операций.",
    );
  }

  // Legacy compatibility guard. The old operation deleted the student while
  // leaving lessons, subscriptions and financial history without a lifecycle
  // decision, so it must remain fail-closed until preview/commit exists.
  async returnStudentToLead(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    void studentId;
    throw new ConflictException(
      "Возврат ученика в лиды отключён. Сначала нужен управляемый сценарий с предварительной проверкой занятий, абонементов и финансовых операций.",
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

  // Chat "taken into work" events belong to the messenger schema
  // (app.chats / app.chat_work_events); read them through the messenger-owned
  // ChatWorkTimelineService instead of inlining that SQL here.
  private async listChatWorkTimeline(
    entityType: "student" | "lead",
    entityId: string,
  ) {
    const rows = await this.chatWork.listForEntity(entityType, entityId);
    return rows.map((row) => toTimelineDto(row));
  }

  // The self-view lesson/task reads live in ScheduleReadService / SharedTaskService.
  // Commerce is intentionally served through its separate projection boundary.

  private async listClientStudents(userId: string): Promise<StudentRow[]> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
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
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
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
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
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

  private hashEmail(value: string): string {
    return createHash("sha256").update(value.toLowerCase()).digest("hex");
  }

}
