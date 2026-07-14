import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { AddHomeworkAttachmentDto } from "./dto/add-homework-attachment.dto";
import { CreateHomeworkDto } from "./dto/create-homework.dto";
import { HomeworkQuery } from "./dto/homework.query";
import { UpdateHomeworkDto } from "./dto/update-homework.dto";

interface HomeworkRow {
  id: string;
  lesson_id: string | null;
  student_id: string;
  assigned_by: string | null;
  title: string;
  description: string | null;
  status: string;
  due_at: Date | string | null;
  created_at: Date | string;
  updated_at: Date | string;
}

/**
 * Lesson-homework domain, extracted from CrmService (SRP): assignment, listing,
 * status updates, client submission, and attachments. Self-contained — touches
 * only `app.lesson_homeworks` / `app.homework_attachments` and depends on the
 * shared database/audit/policy collaborators, nothing else in CrmService.
 */
@Injectable()
export class HomeworkService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
  ) {}

  private toHomeworkDto(row: HomeworkRow) {
    return {
      id: row.id,
      lessonId: row.lesson_id,
      studentId: row.student_id,
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
      // Clients only see homeworks assigned to a student they own.
      params.push(actor.userId);
      conditions.push(
        `lh.student_id in (
          select s.id
          from app.students s
          join app.profiles p
            on p.id = s.profile_id and p.deleted_at is null
          where p.user_id = $${params.length} and s.deleted_at is null
        )`,
      );
    } else {
      this.policy.assertCanReadOperationalData(actor);
      if (query.studentId) {
        params.push(query.studentId);
        conditions.push(`lh.student_id = $${params.length}`);
      }
      if (query.lessonId) {
        params.push(query.lessonId);
        conditions.push(`lh.lesson_id = $${params.length}`);
      }
    }
    if (query.status) {
      params.push(query.status);
      conditions.push(`lh.status = $${params.length}`);
    }
    const limit = Math.min(query.limit ?? 100, 200);
    params.push(limit);
    const result = await this.database.query<HomeworkRow>(
      `
        select lh.id, lh.lesson_id, lh.student_id, lh.assigned_by, lh.title,
          lh.description, lh.status, lh.due_at, lh.created_at, lh.updated_at
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
    const result = await this.database.query<HomeworkRow>(
      `
        insert into app.lesson_homeworks
          (lesson_id, student_id, assigned_by, title, description, status, due_at)
        values ($1, $2, $3, $4, $5, 'assigned', $6)
        returning id, lesson_id, student_id, assigned_by, title, description,
          status, due_at, created_at, updated_at
      `,
      [
        dto.lessonId ?? null,
        dto.studentId,
        actor.userId,
        dto.title.trim(),
        dto.description?.trim() || null,
        dto.dueAt ?? null,
      ],
    );
    const homework = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.homework_assigned",
      entityType: "student",
      entityId: homework.student_id,
      metadata: { homeworkId: homework.id },
    });
    return this.toHomeworkDto(homework);
  }

  async updateHomework(
    actor: ActorContext,
    homeworkId: string,
    dto: UpdateHomeworkDto,
  ) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<HomeworkRow>(
      `
        update app.lesson_homeworks
        set title = coalesce($2, title),
            description = coalesce($3, description),
            due_at = coalesce($4, due_at),
            status = coalesce($5, status),
            updated_at = now()
        where id = $1 and deleted_at is null
        returning id, lesson_id, student_id, assigned_by, title, description,
          status, due_at, created_at, updated_at
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
      entityType: "student",
      entityId: homework.student_id,
      metadata: { homeworkId: homework.id },
    });
    return this.toHomeworkDto(homework);
  }

  async submitHomework(actor: ActorContext, homeworkId: string) {
    const owner = await this.loadHomeworkOwner(homeworkId);
    if (!owner) throw new NotFoundException("Задание не найдено.");
    if (owner.student_user_id !== actor.userId) {
      throw new ForbiddenException("Недостаточно прав для сдачи задания.");
    }
    const result = await this.database.query<HomeworkRow>(
      `
        update app.lesson_homeworks
        set status = 'submitted', updated_at = now()
        where id = $1 and deleted_at is null
        returning id, lesson_id, student_id, assigned_by, title, description,
          status, due_at, created_at, updated_at
      `,
      [homeworkId],
    );
    const homework = result.rows[0];
    if (!homework) throw new NotFoundException("Задание не найдено.");
    await this.audit.record({
      actor,
      action: "crm.homework_submitted",
      entityType: "student",
      entityId: homework.student_id,
      metadata: { homeworkId: homework.id },
    });
    return this.toHomeworkDto(homework);
  }

  async addHomeworkAttachment(
    actor: ActorContext,
    homeworkId: string,
    dto: AddHomeworkAttachmentDto,
  ) {
    const kind = dto.kind ?? "assignment";
    if (kind === "submission") {
      const owner = await this.loadHomeworkOwner(homeworkId);
      if (!owner) throw new NotFoundException("Задание не найдено.");
      if (owner.student_user_id !== actor.userId) {
        throw new ForbiddenException(
          "Недостаточно прав для прикрепления решения.",
        );
      }
    } else {
      this.policy.assertCanReadOperationalData(actor);
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
      entityType: "student",
      entityId: homeworkId,
      metadata: { attachmentId: attachment.id, fileId: dto.fileId, kind },
    });
    return { id: attachment.id, homeworkId, fileId: dto.fileId, kind };
  }

  /** Resolve the assigning teacher + owning client of a homework's student. */
  private async loadHomeworkOwner(
    homeworkId: string,
  ): Promise<{ assigned_by: string | null; student_user_id: string | null } | null> {
    const result = await this.database.query<{
      assigned_by: string | null;
      student_user_id: string | null;
    }>(
      `
        select lh.assigned_by, p.user_id as student_user_id
        from app.lesson_homeworks lh
        join app.students s on s.id = lh.student_id
        left join app.profiles p
          on p.id = s.profile_id and p.deleted_at is null
        where lh.id = $1 and lh.deleted_at is null
        limit 1
      `,
      [homeworkId],
    );
    return result.rows[0] ?? null;
  }
}
