import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { managerAdminRolesSql } from "../common/security/role-sql";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { TaskBoardQuery } from "./dto/task-board.query";
import { UpsertTaskDto } from "./dto/upsert-task.dto";
import { branchIdExpr } from "./branch-scope";
import { CrmPolicy } from "./crm.policy";
import {
  TaskRow,
  formatLessonTimeMoscow,
  toTaskDto,
} from "./crm-mappers";

/**
 * Tasks domain, extracted from CrmService (SRP): the task board (list with
 * row-level RBAC + rich filters), create/update, and the fire-and-forget
 * "new task" notification to the assignee. Touches `app.tasks` and the shared
 * db/audit/policy/realtime/notifications collaborators. CrmService injects this
 * back for the student-card aggregate.
 */
@Injectable()
export class TasksService {
  private readonly logger = new Logger(TasksService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeBus,
  ) {}

  /**
   * Client self-view: open tasks across the caller's own students, used by
   * CrmService.getMySummary. Un-gated by CrmPolicy — ownership is established
   * upstream. Owns the task SQL that previously lived inline in CrmService.
   */
  async listOpenTasksForStudents(studentIds: string[]) {
    if (!studentIds.length) return [];
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
    return (result?.rows ?? []).map((row) => toTaskDto(row));
  }

  async listTasks(actor: ActorContext, query: TaskBoardQuery) {
    // Reading tasks is operational data (shown in client cards to admin/teacher),
    // not a manager-only management op; row-level RBAC is enforced in the SQL below.
    this.policy.assertCanReadOperationalData(actor);
    const limit = Math.min(query.limit ?? 50, 100);
    const result = await this.database.query<TaskRow>(
      `
        select task.id, task.entity_type, task.entity_id, task.assigned_to,
          assigned_profile.first_name as assigned_first_name,
          assigned_profile.last_name as assigned_last_name,
          assigned_profile.id as assigned_profile_id,
          creator_profile.first_name as creator_first_name,
          creator_profile.last_name as creator_last_name,
          creator_profile.id as creator_profile_id,
          coalesce(student_profile.first_name, teacher_profile.first_name) as entity_first_name,
          coalesce(student_profile.last_name, teacher_profile.last_name) as entity_last_name,
          coalesce(
            nullif(concat_ws(' ', lead.first_name, lead.last_name), ''),
            grp.name
          ) as entity_name,
          coalesce(
            nullif(${branchIdExpr("student")}, ''),
            nullif(${branchIdExpr("lead")}, ''),
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
          nullif(${branchIdExpr("student")}, ''),
          nullif(${branchIdExpr("lead")}, ''),
          grp.branch_id::text,
          lesson.branch_id::text
        ) and branch.deleted_at is null
        where task.deleted_at is null
          and (
            ${managerAdminRolesSql("$1")}
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
              nullif(${branchIdExpr("student")}, ''),
              nullif(${branchIdExpr("lead")}, ''),
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
    return { items: result.rows.map((row) => toTaskDto(row)) };
  }

  async createTask(actor: ActorContext, dto: UpsertTaskDto) {
    this.policy.assertManagerOnly(actor);
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
    this.realtime.emitCrmChanged({
      entity: "task",
      action: "created",
      id: task.id,
      // Scope to the assignee so their client can pop «У вас новая задача».
      affectedUserIds: task.assigned_to ? [task.assigned_to] : null,
    });
    if (task.assigned_to && task.assigned_to !== actor.userId) {
      this.notifyNewTaskSafe(task.assigned_to, task.title, task.due_at);
    }
    return toTaskDto(task);
  }

  // Fire-and-forget "new task" notification to the assignee ("У вас новая
  // задача"). A notification failure must NEVER break task creation.
  private notifyNewTaskSafe(
    userId: string,
    title: string,
    dueAt: Date | string | null,
  ): void {
    const when = dueAt
      ? ` (срок ${formatLessonTimeMoscow(dueAt)} по Москве)`
      : "";
    try {
      void this.notifications
        .notifyUser({
          userId,
          title: "У вас новая задача",
          body: `«${title}»${when}`,
          // Without an explicit list notifyUser defaults to ['in_app'], which
          // only lights up the bell: mobile assignees would never be told.
          channels: ["in_app", "push"],
        })
        .catch((error: unknown) => {
          this.logger.warn(`New task notification failed: ${String(error)}`);
        });
    } catch (error: unknown) {
      this.logger.warn(`New task notification failed: ${String(error)}`);
    }
  }

  async updateTask(actor: ActorContext, taskId: string, dto: UpsertTaskDto) {
    this.policy.assertManagerOnly(actor);
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
    this.realtime.emitCrmChanged({
      entity: "task",
      action: "updated",
      id: task.id,
    });
    return toTaskDto(task);
  }
}
