import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import type { QueryResult, QueryResultRow } from "pg";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { audienceForHomework } from "./audience";
import { CrmPolicy } from "./crm.policy";
import { AddHomeworkAttachmentDto } from "./dto/add-homework-attachment.dto";
import { CreateHomeworkDto } from "./dto/create-homework.dto";
import { HomeworkQuery } from "./dto/homework.query";
import { UpdateHomeworkDto } from "./dto/update-homework.dto";

interface HomeworkRow {
  id: string;
  lesson_id: string | null;
  student_id: string | null;
  lead_id: string | null;
  assigned_by: string | null;
  title: string;
  description: string | null;
  status: string;
  due_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

interface HomeworkScopeRow {
  student_id: string | null;
  lead_id: string | null;
  teacher_user_id: string | null;
}

interface HomeworkClientAccessRow extends HomeworkScopeRow {
  client_can_access: boolean;
}

interface LessonTargetRow {
  id: string;
  student_matches: boolean;
  lead_id: string | null;
  is_trial: boolean;
  teacher_user_id: string | null;
}

interface HomeworkQueryExecutor {
  query<T extends QueryResultRow = QueryResultRow>(
    query: string,
    params?: unknown[],
  ): Promise<QueryResult<T>>;
}

/**
 * Student and pre-conversion lead homework. A teacher is scoped to the lesson
 * they are assigned to; clients are scoped through direct, manual-link or
 * parent/payer family access. Management roles retain the full operational
 * view. Conversion moves lead rows to the resulting student transactionally.
 */
@Injectable()
export class HomeworkService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  private toHomeworkDto(row: HomeworkRow) {
    return {
      id: row.id,
      lessonId: row.lesson_id,
      studentId: row.student_id,
      leadId: row.lead_id,
      assignedBy: row.assigned_by,
      title: row.title,
      description: row.description,
      status: row.status,
      dueAt: row.due_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  async listHomeworks(actor: ActorContext, query: HomeworkQuery) {
    const conditions: string[] = ["lh.deleted_at is null"];
    const params: unknown[] = [];

    if (actor.role === "client") {
      params.push(actor.userId);
      conditions.push(this.clientAccessSql(`$${params.length}`));
    } else {
      this.policy.assertCanReadOperationalData(actor);
      if (actor.role === "teacher") {
        params.push(actor.userId);
        conditions.push(
          `exists (
            select 1
            from app.lessons own_lesson
            join app.teachers own_teacher
              on own_teacher.id = own_lesson.teacher_id
             and own_teacher.deleted_at is null
            join app.profiles own_teacher_profile
              on own_teacher_profile.id = own_teacher.profile_id
             and own_teacher_profile.deleted_at is null
            where own_lesson.id = lh.lesson_id
              and own_lesson.deleted_at is null
              and own_teacher_profile.user_id = $${params.length}
          )`,
        );
      }
    }

    if (query.studentId) {
      params.push(query.studentId);
      conditions.push(`lh.student_id = $${params.length}`);
    }
    if (query.leadId) {
      params.push(query.leadId);
      conditions.push(`lh.lead_id = $${params.length}`);
    }
    if (query.lessonId) {
      params.push(query.lessonId);
      conditions.push(`lh.lesson_id = $${params.length}`);
    }
    if (query.status) {
      params.push(query.status);
      conditions.push(`lh.status = $${params.length}`);
    }

    const limit = Math.min(query.limit ?? 100, 200);
    params.push(limit);
    const result = await this.database.query<HomeworkRow>(
      `
        select lh.id, lh.lesson_id, lh.student_id, lh.lead_id,
          lh.assigned_by, lh.title, lh.description, lh.status, lh.due_at,
          lh.created_at, lh.updated_at
        from app.lesson_homeworks lh
        where ${conditions.join(" and ")}
        order by lh.created_at desc
        limit $${params.length}
      `,
      params,
    );
    return { items: result.rows.map((row) => this.toHomeworkDto(row)) };
  }

  async createHomework(actor: ActorContext, dto: CreateHomeworkDto) {
    this.policy.assertCanReadOperationalData(actor);
    this.assertExactlyOneTarget(dto.studentId, dto.leadId);

    if (dto.leadId && !dto.lessonId) {
      throw new BadRequestException(
        "Для задания лида обязательно пробное занятие.",
      );
    }
    if (actor.role === "teacher" && !dto.lessonId) {
      throw new BadRequestException(
        "Преподаватель может назначить задание только к своему занятию.",
      );
    }
    if (!dto.leadId && actor.role === "teacher") {
      await this.assertLessonTarget(actor, dto, this.database);
    }

    const insert = (executor: HomeworkQueryExecutor) =>
      executor.query<HomeworkRow>(
      `
        insert into app.lesson_homeworks
          (lesson_id, student_id, lead_id, assigned_by, title, description,
           status, due_at)
        values ($1, $2, $3, $4, $5, $6, 'assigned', $7)
        returning id, lesson_id, student_id, lead_id, assigned_by, title,
          description, status, due_at, created_at, updated_at
      `,
      [
        dto.lessonId ?? null,
        dto.studentId ?? null,
        dto.leadId ?? null,
        actor.userId,
        dto.title.trim(),
        dto.description?.trim() || null,
        dto.dueAt ?? null,
      ],
    );
    const result = dto.leadId
      ? await this.database.transaction(async (client) => {
          await client.query(
            `select pg_advisory_xact_lock(
              hashtextextended($1::uuid::text, 0)
            )`,
            [dto.leadId],
          );
          await this.assertLessonTarget(actor, dto, client);
          return insert(client);
        })
      : await insert(this.database);
    const homework = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.homework_assigned",
      entityType: homework.lead_id ? "lead" : "student",
      entityId: homework.lead_id ?? homework.student_id!,
      metadata: { homeworkId: homework.id, lessonId: homework.lesson_id },
    });
    await this.publishHomeworkChanged(homework.id, "created");
    return this.toHomeworkDto(homework);
  }

  async updateHomework(
    actor: ActorContext,
    homeworkId: string,
    dto: UpdateHomeworkDto,
  ) {
    const scope = await this.assertCanManageHomework(actor, homeworkId);
    const result = await this.database.query<HomeworkRow>(
      `
        update app.lesson_homeworks
        set title = coalesce($2, title),
            description = coalesce($3, description),
            due_at = coalesce($4, due_at),
            status = coalesce($5, status),
            updated_at = now()
        where id = $1 and deleted_at is null
        returning id, lesson_id, student_id, lead_id, assigned_by, title,
          description, status, due_at, created_at, updated_at
      `,
      [
        homeworkId,
        dto.title?.trim() ?? null,
        dto.description?.trim() ?? null,
        dto.dueAt ?? null,
        dto.status ?? null,
      ],
    );
    const homework = result.rows[0];
    if (!homework) throw new NotFoundException("Задание не найдено.");
    await this.audit.record({
      actor,
      action: "crm.homework_updated",
      entityType: scope.lead_id ? "lead" : "student",
      entityId: scope.lead_id ?? scope.student_id!,
      metadata: { homeworkId: homework.id },
    });
    await this.publishHomeworkChanged(homework.id, "updated");
    return this.toHomeworkDto(homework);
  }

  async submitHomework(actor: ActorContext, homeworkId: string) {
    if (actor.role !== "client") {
      throw new ForbiddenException("Недостаточно прав для сдачи задания.");
    }
    const access = await this.loadHomeworkClientAccess(
      homeworkId,
      actor.userId,
    );
    if (!access) throw new NotFoundException("Задание не найдено.");
    if (!access.client_can_access) {
      throw new ForbiddenException("Недостаточно прав для сдачи задания.");
    }

    const result = await this.database.query<HomeworkRow>(
      `
        update app.lesson_homeworks
        set status = 'submitted', updated_at = now()
        where id = $1 and deleted_at is null
        returning id, lesson_id, student_id, lead_id, assigned_by, title,
          description, status, due_at, created_at, updated_at
      `,
      [homeworkId],
    );
    const homework = result.rows[0];
    if (!homework) throw new NotFoundException("Задание не найдено.");
    await this.audit.record({
      actor,
      action: "crm.homework_submitted",
      entityType: homework.lead_id ? "lead" : "student",
      entityId: homework.lead_id ?? homework.student_id!,
      metadata: { homeworkId: homework.id },
    });
    await this.publishHomeworkChanged(homework.id, "updated");
    return this.toHomeworkDto(homework);
  }

  async addHomeworkAttachment(
    actor: ActorContext,
    homeworkId: string,
    dto: AddHomeworkAttachmentDto,
  ) {
    const kind = dto.kind ?? "assignment";
    let scope: HomeworkScopeRow;
    if (kind === "submission") {
      if (actor.role !== "client") {
        throw new ForbiddenException(
          "Недостаточно прав для прикрепления решения.",
        );
      }
      const access = await this.loadHomeworkClientAccess(
        homeworkId,
        actor.userId,
      );
      if (!access) throw new NotFoundException("Задание не найдено.");
      if (!access.client_can_access) {
        throw new ForbiddenException(
          "Недостаточно прав для прикрепления решения.",
        );
      }
      scope = access;
    } else {
      scope = await this.assertCanManageHomework(actor, homeworkId);
    }

    const result = await this.database.query<{ id: string }>(
      `
        insert into app.homework_attachments
          (homework_id, file_id, uploaded_by, kind)
        values ($1, $2, $3, $4)
        returning id
      `,
      [homeworkId, dto.fileId, actor.userId, kind],
    );
    const attachment = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.homework_attachment_added",
      entityType: scope.lead_id ? "lead" : "student",
      entityId: scope.lead_id ?? scope.student_id!,
      metadata: { attachmentId: attachment.id, fileId: dto.fileId, kind },
    });
    await this.publishHomeworkChanged(homeworkId, "updated");
    return { id: attachment.id, homeworkId, fileId: dto.fileId, kind };
  }

  private async publishHomeworkChanged(
    homeworkId: string,
    action: "created" | "updated",
  ): Promise<void> {
    const affectedUserIds = await audienceForHomework(
      this.database,
      homeworkId,
    );
    this.realtime.emitCrmChanged({
      entity: "homework",
      action,
      id: homeworkId,
      affectedUserIds,
    });
  }

  private assertExactlyOneTarget(
    studentId: string | undefined,
    leadId: string | undefined,
  ): void {
    if (Boolean(studentId) === Boolean(leadId)) {
      throw new BadRequestException(
        "Укажите ровно одного получателя задания: ученика или лида.",
      );
    }
  }

  private async assertLessonTarget(
    actor: ActorContext,
    dto: CreateHomeworkDto,
    executor: HomeworkQueryExecutor,
  ): Promise<void> {
    const result = await executor.query<LessonTargetRow>(
      `
        select l.id,
          (
            l.student_id = $2::uuid
            or exists (
              select 1
              from app.group_students gs
              where gs.group_id = l.group_id
                and gs.student_id = $2::uuid
                and gs.left_at is null
            )
          ) as student_matches,
          l.lead_id, l.is_trial, teacher_profile.user_id as teacher_user_id
        from app.lessons l
        left join app.teachers teacher
          on teacher.id = l.teacher_id and teacher.deleted_at is null
        left join app.profiles teacher_profile
          on teacher_profile.id = teacher.profile_id
         and teacher_profile.deleted_at is null
        where l.id = $1 and l.deleted_at is null
        limit 1
      `,
      [dto.lessonId, dto.studentId ?? null],
    );
    const lesson = result.rows[0];
    if (!lesson) throw new NotFoundException("Урок не найден.");
    if (dto.leadId && (lesson.lead_id !== dto.leadId || !lesson.is_trial)) {
      throw new BadRequestException(
        "Задание лида должно относиться к его пробному занятию.",
      );
    }
    if (dto.studentId && !lesson.student_matches) {
      throw new BadRequestException("Ученик не относится к этому занятию.");
    }
    if (
      actor.role === "teacher" &&
      lesson.teacher_user_id !== actor.userId
    ) {
      throw new ForbiddenException(
        "Преподаватель может назначать задания только к своим занятиям.",
      );
    }
  }

  private async assertCanManageHomework(
    actor: ActorContext,
    homeworkId: string,
  ): Promise<HomeworkScopeRow> {
    this.policy.assertCanReadOperationalData(actor);
    const scope = await this.loadHomeworkScope(homeworkId);
    if (!scope) throw new NotFoundException("Задание не найдено.");
    if (isManagerOrAdminRole(actor.role)) return scope;
    if (
      actor.role === "teacher" &&
      scope.teacher_user_id === actor.userId
    ) {
      return scope;
    }
    throw new NotFoundException("Задание не найдено.");
  }

  private async loadHomeworkScope(
    homeworkId: string,
  ): Promise<HomeworkScopeRow | null> {
    const result = await this.database.query<HomeworkScopeRow>(
      `
        select lh.student_id, lh.lead_id,
          teacher_profile.user_id as teacher_user_id
        from app.lesson_homeworks lh
        left join app.lessons lesson
          on lesson.id = lh.lesson_id and lesson.deleted_at is null
        left join app.teachers teacher
          on teacher.id = lesson.teacher_id and teacher.deleted_at is null
        left join app.profiles teacher_profile
          on teacher_profile.id = teacher.profile_id
         and teacher_profile.deleted_at is null
        where lh.id = $1 and lh.deleted_at is null
        limit 1
      `,
      [homeworkId],
    );
    return result.rows[0] ?? null;
  }

  private async loadHomeworkClientAccess(
    homeworkId: string,
    userId: string,
  ): Promise<HomeworkClientAccessRow | null> {
    const result = await this.database.query<HomeworkClientAccessRow>(
      `
        select lh.student_id, lh.lead_id, null::uuid as teacher_user_id,
          ${this.clientAccessSql("$2")} as client_can_access
        from app.lesson_homeworks lh
        where lh.id = $1 and lh.deleted_at is null
        limit 1
      `,
      [homeworkId, userId],
    );
    return result.rows[0] ?? null;
  }

  private clientAccessSql(userIdExpression: string): string {
    return `(
      exists (
        select 1
        from app.students own_student
        join app.profiles own_profile
          on own_profile.id = own_student.profile_id
         and own_profile.deleted_at is null
        where own_student.id = lh.student_id
          and own_student.deleted_at is null
          and own_profile.user_id = ${userIdExpression}
      )
      or exists (
        select 1
        from app.user_crm_links student_link
        where student_link.user_id = ${userIdExpression}
          and student_link.entity_type = 'student'
          and student_link.entity_id = lh.student_id
          and student_link.deleted_at is null
      )
      or exists (
        select 1
        from app.profiles account_profile
        join app.family_members parent_member
          on parent_member.entity_type = 'profile'
         and parent_member.entity_id = account_profile.id
         and parent_member.role in ('parent', 'payer')
         and parent_member.deleted_at is null
        join app.families family
          on family.id = parent_member.family_id and family.deleted_at is null
        join app.family_members student_member
          on student_member.family_id = family.id
         and student_member.entity_type = 'student'
         and student_member.entity_id = lh.student_id
         and student_member.deleted_at is null
        where account_profile.user_id = ${userIdExpression}
          and account_profile.deleted_at is null
      )
      or exists (
        select 1
        from app.user_crm_links lead_link
        where lead_link.user_id = ${userIdExpression}
          and lead_link.entity_type = 'lead'
          and lead_link.entity_id = lh.lead_id
          and lead_link.deleted_at is null
      )
      or exists (
        select 1
        from app.profiles account_profile
        join app.family_members parent_member
          on parent_member.entity_type = 'profile'
         and parent_member.entity_id = account_profile.id
         and parent_member.role in ('parent', 'payer')
         and parent_member.deleted_at is null
        join app.families family
          on family.id = parent_member.family_id and family.deleted_at is null
        join app.family_members lead_member
          on lead_member.family_id = family.id
         and lead_member.entity_type = 'lead'
         and lead_member.entity_id = lh.lead_id
         and lead_member.deleted_at is null
        where account_profile.user_id = ${userIdExpression}
          and account_profile.deleted_at is null
      )
    )`;
  }
}
