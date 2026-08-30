import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { createHash } from "node:crypto";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { NotificationsService } from "../../notifications/notifications.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { APPEAL_KEY, resolveAppealDate } from "../appeal-date";
import { extractBranchId } from "../branch-scope";
import type {
  ValidatedCustomFields,
  ValidatedStudentCreate,
} from "../clients/client-write.validator";
import { diffEntityFields, isDeliverableEmail } from "../crm-mappers";
import { CrmPolicy } from "../crm.policy";
import {
  requiredTrim,
  rethrowCreatePersonError,
  sanitizeJsonObject,
  trimOptional,
} from "../crm-util";
import { CreateStudentDto } from "../dto/create-student.dto";
import { UpdateStudentDto } from "../dto/update-student.dto";
import { ensureResponsibleSafe } from "../responsible";
import { responsibleUserIdFromCustomDataPatch } from "../responsible-eligibility";
import { findStudent, type StudentRow } from "../student-read";
import { StudentMutationExecutor } from "./student-mutation.executor";
import type {
  PreparedStudentCreate,
  PreparedStudentUpdate,
  StudentWriteSnapshot,
} from "./student-mutation.types";
import { toStudentDto } from "./student-presenter";

const STUDENT_AUDITED_FIELDS = [
  "status",
  "first_name",
  "last_name",
  "phone",
  "email",
];

@Injectable()
export class StudentCommandService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeBus,
    private readonly mutations: StudentMutationExecutor,
  ) {}

  async createStudent(
    actor: ActorContext,
    dto: CreateStudentDto,
    validated?: ValidatedStudentCreate,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const command = await this.prepareCreate(dto, validated);
    try {
      const student = await this.mutations.create(command);
      const claimedVersion = await this.ensureFallbackResponsible(
        actor,
        student.id,
        command.requestedResponsibleId,
      );
      if (claimedVersion !== null) student.version = claimedVersion;
      await this.publishCreated(actor, student, command);
      return {
        ...toStudentDto(student),
        ...(validated ? { warnings: validated.warnings } : {}),
      };
    } catch (error) {
      rethrowCreatePersonError(error);
    }
  }

  async updateStudent(
    actor: ActorContext,
    studentId: string,
    dto: UpdateStudentDto,
    customFields?: ValidatedCustomFields,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const command = this.prepareUpdate(studentId, dto, customFields);
    const { beforeStudent, student } = await this.mutations
      .update(command)
      .catch((error: unknown) => rethrowCreatePersonError(error));
    if (!student) throw new NotFoundException("Ученик не найден.");
    const claimedVersion = await this.ensureUpdateFallbackResponsible(
      actor,
      dto,
      command,
      student.id,
    );
    if (claimedVersion !== null) student.version = claimedVersion;
    await this.publishUpdated(
      actor,
      student,
      beforeStudent,
      command,
      customFields,
    );
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
      studentId: student.id,
      template: "student_invite",
      title: "Приглашение в личный кабинет Magic Music",
      body:
        "Здравствуйте! Школа Magic Music подготовила для вас личный кабинет. " +
        `Установите приложение по кнопке ниже и войдите или зарегистрируйтесь с этой почтой: ${email}. ` +
        "После подтверждения почты аккаунт будет привязан к вашей карточке ученика.",
    });
    // The explicit manager action may target an already verified app account.
    // Link it immediately; new accounts are linked only after email ownership
    // is proven by AuthVerificationService.
    await this.database.query(
      `
        insert into app.user_crm_links (
          user_id, entity_type, entity_id, link_source, confirmed_at, created_by
        )
        select account.id, 'student', $1, 'auto_email', now(), $3
        from app.users account
        where lower(account.email) = lower($2)
          and account.deleted_at is null
          and account.is_app_account = true
          and account.email_verified_at is not null
        on conflict (entity_type, entity_id) where deleted_at is null
        do nothing
      `,
      [student.id, email, actor.userId],
    );
    await this.audit.record({
      actor,
      action: "crm.student_invite_sent",
      entityType: "student",
      entityId: student.id,
      metadata: { emailHash: this.hashEmail(email) },
    });
    return { studentId: student.id, email, status: "queued" };
  }

  async deleteStudent(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    void studentId;
    throw new ConflictException(
      "Прямое удаление ученика отключено. Используйте управляемое архивирование с предварительной проверкой связанных занятий, абонементов и финансовых операций.",
    );
  }

  async returnStudentToLead(actor: ActorContext, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    void studentId;
    throw new ConflictException(
      "Возврат ученика в лиды отключён. Сначала нужен управляемый сценарий с предварительной проверкой занятий, абонементов и финансовых операций.",
    );
  }

  private async prepareCreate(
    dto: CreateStudentDto,
    validated?: ValidatedStudentCreate,
  ): Promise<PreparedStudentCreate> {
    const command = this.prepareCreateCommand(dto, validated);
    const customDataPatch = await this.prepareLeadConversion(
      command.leadId,
      command.customDataPatch,
    );
    return { ...command, customDataPatch };
  }

  private prepareCreateCommand(
    dto: CreateStudentDto,
    validated?: ValidatedStudentCreate,
  ): PreparedStudentCreate {
    const firstName = requiredTrim(dto.firstName, "Имя ученика обязательно.");
    const lastName = trimOptional(dto.lastName);
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
    const leadId = dto.leadId ?? null;
    const requestedResponsibleId =
      responsibleUserIdFromCustomDataPatch(customDataPatch);
    const branchId = extractBranchId(dto.customDataPatch);
    return {
      firstName,
      lastName,
      email: trimOptional(dto.email)?.toLowerCase() ?? null,
      fullName: [firstName, lastName].filter(Boolean).join(" "),
      phone: trimOptional(dto.phone),
      status: trimOptional(dto.status) ?? "active",
      leadId,
      customDataPatch,
      requestedResponsibleId,
      branchId,
      sourceId: validated?.sourceId ?? null,
      customFields: validated?.customFields,
    };
  }

  private async prepareLeadConversion(
    leadId: string | null,
    customDataPatch: Readonly<Record<string, unknown>>,
  ): Promise<Readonly<Record<string, unknown>>> {
    if (!leadId) return customDataPatch;
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
    if (!customDataPatch[APPEAL_KEY]) {
      const appeal = resolveAppealDate(leadRow.custom_data, leadRow.created_at);
      if (appeal.value) {
        return { ...customDataPatch, [APPEAL_KEY]: appeal.value };
      }
    }
    return customDataPatch;
  }

  private prepareUpdate(
    studentId: string,
    dto: UpdateStudentDto,
    customFields?: ValidatedCustomFields,
  ): PreparedStudentUpdate {
    const customDataPatch = sanitizeJsonObject(dto.customDataPatch);
    const requestedResponsibleId = dto.clearResponsible
      ? undefined
      : responsibleUserIdFromCustomDataPatch(customDataPatch);
    const branchId = extractBranchId(dto.customDataPatch);
    return {
      studentId,
      expectedVersion: dto.expectedVersion,
      firstName: trimOptional(dto.firstName),
      lastName: trimOptional(dto.lastName),
      phone: trimOptional(dto.phone),
      email: trimOptional(dto.email)?.toLowerCase() ?? null,
      status: dto.status === undefined ? null : dto.status.trim(),
      customDataPatch,
      requestedResponsibleId,
      branchId,
      clearResponsible: dto.clearResponsible ?? false,
      sourceId: dto.sourceId ?? null,
      customFields: customFields?.values,
    };
  }

  private async ensureFallbackResponsible(
    actor: ActorContext,
    studentId: string,
    requestedResponsibleId: string | undefined,
  ): Promise<number | null> {
    if (requestedResponsibleId) return null;
    return ensureResponsibleSafe(this.database, actor, "student", studentId);
  }

  private async ensureUpdateFallbackResponsible(
    actor: ActorContext,
    dto: UpdateStudentDto,
    command: PreparedStudentUpdate,
    studentId: string,
  ): Promise<number | null> {
    if (dto.clearResponsible || command.requestedResponsibleId) return null;
    return ensureResponsibleSafe(this.database, actor, "student", studentId);
  }

  private async publishCreated(
    actor: ActorContext,
    student: StudentRow,
    command: PreparedStudentCreate,
  ): Promise<void> {
    await this.audit.record({
      actor,
      action: "crm.student_created",
      entityType: "student",
      entityId: student.id,
      metadata: { leadId: command.leadId },
    });
    this.realtime.emitCrmChanged({
      entity: "student",
      action: "created",
      id: student.id,
      branchId: command.branchId ?? null,
    });
  }

  private async publishUpdated(
    actor: ActorContext,
    student: StudentRow,
    beforeStudent: StudentWriteSnapshot | null,
    command: PreparedStudentUpdate,
    customFields?: ValidatedCustomFields,
  ): Promise<void> {
    await this.audit.record({
      actor,
      action: "crm.student_updated",
      entityType: "student",
      entityId: student.id,
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
      branchId: command.branchId ?? beforeStudent?.branch_id ?? null,
    });
  }

  private hashEmail(value: string): string {
    return createHash("sha256").update(value.toLowerCase()).digest("hex");
  }
}
