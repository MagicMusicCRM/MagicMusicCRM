import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
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
import { responsibleUserIdFromCustomDataPatch } from "./responsible-eligibility";
import { diffEntityFields, isDeliverableEmail } from "./crm-mappers";
import {
  ValidatedCustomFields,
  ValidatedStudentCreate,
} from "./clients/client-write.validator";

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
import { findStudent } from "./student-read";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CreateStudentDto } from "./dto/create-student.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { StudentSearchQuery } from "./dto/student-search.query";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { CrmPolicy } from "./crm.policy";
import {
  toStudentDto,
} from "./students/student-presenter";
import { StudentDirectoryService } from "./students/student-directory.service";
import { StudentSelfSummaryService } from "./students/student-self-summary.service";
import { StudentCardTimelineService } from "./students/student-card-timeline.service";
import { StudentMutationExecutor } from "./students/student-mutation.executor";

@Injectable()
export class CrmService {
  private readonly logger = new Logger(CrmService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly directory: StudentDirectoryService,
    private readonly selfSummary: StudentSelfSummaryService,
    private readonly cardTimeline: StudentCardTimelineService,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeBus,
    private readonly studentMutations: StudentMutationExecutor,
  ) {}

  getMySummary(actor: ActorContext) {
    return this.selfSummary.getMySummary(actor);
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
      const student = await this.studentMutations.create({
        firstName,
        lastName,
        email,
        fullName,
        phone,
        status,
        leadId,
        customDataPatch,
        requestedResponsibleId,
        branchId,
        sourceId: validated?.sourceId ?? null,
        customFields: validated?.customFields,
      });
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

  getStudentCard(actor: ActorContext, studentId: string) {
    return this.cardTimeline.getStudentCard(actor, studentId);
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
    const { beforeStudent, student } = await this.studentMutations.update({
      studentId,
      firstName: trimOptional(dto.firstName),
      lastName: trimOptional(dto.lastName),
      phone: trimOptional(dto.phone),
      email: trimOptional(dto.email)?.toLowerCase() ?? null,
      status: dto.status === undefined ? null : dto.status.trim(),
      customDataPatch: initialCustomData,
      requestedResponsibleId,
      branchId,
      clearResponsible: dto.clearResponsible ?? false,
      sourceId: dto.sourceId ?? null,
      customFields: customFields?.values,
    });
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

  private hashEmail(value: string): string {
    return createHash("sha256").update(value.toLowerCase()).digest("hex");
  }

}
