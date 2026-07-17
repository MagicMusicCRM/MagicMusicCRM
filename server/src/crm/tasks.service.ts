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
import { TaskHistoryQuery } from "./dto/task-history.query";
import { UpsertTaskDto } from "./dto/upsert-task.dto";
import { branchIdExpr } from "./branch-scope";
import { CrmPolicy } from "./crm.policy";
import {
  TaskHistoryRow,
  TaskRow,
  diffTaskRows,
  formatLessonTimeMoscow,
  toTaskDto,
  toTaskHistoryDto,
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

  // The FROM + row-level-RBAC + filter WHERE shared by the board list and the
  // calendar count, so a per-day count can never diverge from the list it
  // summarises. Params: $1 role, $2 userId, $4 studentId, $5 status, $6 q,
  // $7 entityType, $8 entityId, $9 assignedTo, $10 createdBy, $11 branchId,
  // $12 priority, $13 taskType, $14 communicationMethod, $15 from, $16 to.
  // ($3 is the list's LIMIT — unreferenced here.)
  private readonly taskScopeSql = `
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
          and ($12::text is null or task.priority = $12)
          and (
            $13::text is null
            or lower(coalesce(task.title, '') || ' ' || coalesce(task.description, '')) like lower('%' || $13 || '%')
          )
          and (
            $14::text is null
            or lower(coalesce(task.title, '') || ' ' || coalesce(task.description, '')) like lower('%' || $14 || '%')
          )
          and ($15::timestamptz is null or task.due_at >= $15)
          and ($16::timestamptz is null or task.due_at < $16)`;

  private taskScopeParams(query: TaskBoardQuery, actor: ActorContext, limit = 0) {
    return [
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
    ];
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
          task.title, task.description, task.status, task.priority,
          task.due_at, task.due_all_day,
          task.created_by, task.created_at
        ${this.taskScopeSql}
        order by task.due_at nulls last, task.created_at desc
        limit $3
      `,
      this.taskScopeParams(query, actor, limit),
    );
    return { items: result.rows.map((row) => toTaskDto(row)) };
  }

  /**
   * Per-day task counts for the calendar (year/month grids), bucketed by the
   * Moscow date of the deadline — the same zone the «срок … по Москве»
   * notification uses — and filtered identically to the board list, so the
   * number on a day cell always matches the list you get by opening that day.
   */
  async taskCalendar(actor: ActorContext, query: TaskBoardQuery) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ day: string; count: number }>(
      `
        select
          to_char((task.due_at at time zone 'Europe/Moscow')::date, 'YYYY-MM-DD') as day,
          count(*)::int as count
        ${this.taskScopeSql}
          and task.due_at is not null
        group by 1
        order by 1
      `,
      this.taskScopeParams(query, actor),
    );
    return {
      items: result.rows.map((row) => ({ day: row.day, count: row.count })),
    };
  }

  async createTask(actor: ActorContext, dto: UpsertTaskDto) {
    this.policy.assertManagerOnly(actor);
    if (!dto.entityType || !dto.entityId || !dto.title) {
      throw new BadRequestException(
        "Тип, объект и название задачи обязательны.",
      );
    }
    // Owner rule: «для задачи нужно обязательно выбрать срок выполнения». A task
    // without a deadline is invisible in the day view and never triggers a
    // reminder, so the create path refuses one. The «без времени» case still
    // carries a date — it sets due_all_day, not a null due_at.
    if (!dto.dueAt) {
      throw new BadRequestException("Для задачи обязателен срок выполнения.");
    }
    // Read out here: the guard above narrows dto.title, but that narrowing does
    // not survive into the transaction callback.
    const title = dto.title.trim();
    const task = await this.database.transaction(async (client) => {
      const result = await client.query<TaskRow>(
        `
          insert into app.tasks (
            entity_type, entity_id, assigned_to, title, description,
            status, priority, due_at, due_all_day, created_by
          )
          values ($1::app.crm_entity_type, $2, $3, $4, $5, coalesce($6, 'open'),
            coalesce($7, 'medium'), $8, coalesce($9, false), $10)
          returning id, entity_type, entity_id, assigned_to, title, description,
            status, priority, due_at, due_all_day, created_by, created_at
        `,
        [
          dto.entityType,
          dto.entityId,
          dto.assignedTo ?? null,
          title,
          dto.description?.trim() || null,
          dto.status ?? null,
          dto.priority ?? null,
          dto.dueAt ?? null,
          dto.dueAllDay ?? null,
          actor.userId,
        ],
      );
      const created = result.rows[0];
      // Anchors the feed: without a 'created' event the earliest entry would be
      // the first edit, and the task would appear to have sprung from nowhere.
      await client.query(
        `
          insert into app.task_history (
            task_id, field, old_value, new_value, new_user_id, changed_by, source
          )
          values ($1, 'created', null, $2, $3, $4, 'app')
        `,
        [created.id, created.title, created.assigned_to, actor.userId],
      );
      return created;
    });
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
    // The update and its history rows go in ONE transaction: a task whose due
    // date moved but whose «кто перенёс» row was lost is exactly the state the
    // supervisor screen exists to prevent, so a failed log must roll the edit back.
    const { task, changes } = await this.database.transaction(async (client) => {
      // `for update` holds the row across read-modify-log: two concurrent PATCHes
      // would otherwise both read the same "before" and log the same old value,
      // making the feed claim a change that never happened.
      const before = await client.query<TaskRow>(
        `
          select id, entity_type, entity_id, assigned_to, title, description,
            status, priority, due_at, due_all_day, created_by, created_at
          from app.tasks
          where id = $1 and deleted_at is null
          for update
        `,
        [taskId],
      );
      const previous = before.rows[0];
      if (!previous) throw new NotFoundException("Задача не найдена.");

      const after = await client.query<TaskRow>(
        `
          update app.tasks
          set entity_type = coalesce($2::app.crm_entity_type, entity_type),
            entity_id = coalesce($3, entity_id),
            assigned_to = coalesce($4, assigned_to),
            title = coalesce($5, title),
            description = coalesce($6, description),
            status = coalesce($7, status),
            priority = coalesce($8, priority),
            due_at = coalesce($9::timestamptz, due_at),
            due_all_day = coalesce($10, due_all_day),
            updated_at = now()
          where id = $1 and deleted_at is null
          returning id, entity_type, entity_id, assigned_to, title, description,
            status, priority, due_at, due_all_day, created_by, created_at
        `,
        [
          taskId,
          dto.entityType,
          dto.entityId,
          dto.assignedTo ?? null,
          dto.title?.trim() || null,
          dto.description?.trim() || null,
          dto.status ?? null,
          dto.priority ?? null,
          dto.dueAt ?? null,
          dto.dueAllDay ?? null,
        ],
      );
      const updated = after.rows[0];
      if (!updated) throw new NotFoundException("Задача не найдена.");

      const diff = diffTaskRows(previous, updated);
      for (const change of diff) {
        await client.query(
          `
            insert into app.task_history (
              task_id, field, old_value, new_value,
              old_user_id, new_user_id, changed_by, source
            )
            values ($1, $2, $3, $4, $5, $6, $7, 'app')
          `,
          [
            taskId,
            change.field,
            change.oldValue,
            change.newValue,
            change.oldUserId ?? null,
            change.newUserId ?? null,
            actor.userId,
          ],
        );
      }
      return { task: updated, changes: diff };
    });

    await this.audit.record({
      actor,
      action: "crm.task_updated",
      entityType: "task",
      entityId: task.id,
      // The audit event used to say only «задача обновлена». The diff is the
      // whole point of the event, and task_history is per-task — this keeps the
      // cross-entity audit stream self-describing too.
      metadata: {
        changes: changes.map((change) => ({
          field: change.field,
          from: change.oldValue,
          to: change.newValue,
        })),
      },
    });
    this.realtime.emitCrmChanged({
      entity: "task",
      action: "updated",
      id: task.id,
    });
    return toTaskDto(task);
  }

  /**
   * Soft-delete a task. The schema has always had `deleted_at` and every read
   * filters on it, but no endpoint ever set it — so «Удалить» had nothing to
   * call and the «Отменить» status was the only way to retire a task, which
   * merely hid it behind a filter. This removes it for good (recoverably).
   */
  async deleteTask(actor: ActorContext, taskId: string) {
    this.policy.assertManagerOnly(actor);
    const result = await this.database.query<{ id: string }>(
      `
        update app.tasks
        set deleted_at = now(), updated_at = now()
        where id = $1 and deleted_at is null
        returning id
      `,
      [taskId],
    );
    if (!result.rows[0]) throw new NotFoundException("Задача не найдена.");
    await this.audit.record({
      actor,
      action: "crm.task_deleted",
      entityType: "task",
      entityId: taskId,
    });
    this.realtime.emitCrmChanged({
      entity: "task",
      action: "deleted",
      id: taskId,
    });
    return { id: taskId, deleted: true };
  }

  /**
   * AmoCRM-style feed for one task: every field change, newest first, with the
   * author resolved to a name. Names are joined at read time rather than frozen
   * into the log, so a renamed employee reads correctly in old events.
   */
  async listTaskHistory(actor: ActorContext, taskId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<TaskHistoryRow>(
      `
        select history.id, history.field, history.old_value, history.new_value,
          history.changed_at, history.source,
          history.changed_by,
          author_profile.id as author_profile_id,
          author_profile.first_name as author_first_name,
          author_profile.last_name as author_last_name,
          history.old_user_id,
          old_profile.first_name as old_user_first_name,
          old_profile.last_name as old_user_last_name,
          history.new_user_id,
          new_profile.first_name as new_user_first_name,
          new_profile.last_name as new_user_last_name
        from app.task_history history
        left join app.profiles author_profile
          on author_profile.user_id = history.changed_by and author_profile.deleted_at is null
        left join app.profiles old_profile
          on old_profile.user_id = history.old_user_id and old_profile.deleted_at is null
        left join app.profiles new_profile
          on new_profile.user_id = history.new_user_id and new_profile.deleted_at is null
        where history.task_id = $1
        order by history.changed_at desc, history.id desc
        limit 200
      `,
      [taskId],
    );
    return { items: result.rows.map((row) => toTaskHistoryDto(row)) };
  }

  /**
   * Supervisor control feed (spec §2.2: «чтобы директор и управляющий могли
   * видеть, кто какие задачи когда переносит»). Defaults to due-date moves,
   * which is the case the customer asked to control, but any field can be pulled.
   */
  async listTaskHistoryFeed(actor: ActorContext, query: TaskHistoryQuery) {
    // Deliberately stricter than the per-task feed: this is a cross-task
    // oversight view of who did what, not operational data for the shop floor.
    this.policy.assertManagerOnly(actor);
    const limit = Math.min(query.limit ?? 50, 200);
    const result = await this.database.query<TaskHistoryRow>(
      `
        select history.id, history.field, history.old_value, history.new_value,
          history.changed_at, history.source,
          history.changed_by,
          author_profile.id as author_profile_id,
          author_profile.first_name as author_first_name,
          author_profile.last_name as author_last_name,
          history.old_user_id,
          old_profile.first_name as old_user_first_name,
          old_profile.last_name as old_user_last_name,
          history.new_user_id,
          new_profile.first_name as new_user_first_name,
          new_profile.last_name as new_user_last_name,
          history.task_id,
          task.title as task_title,
          task.entity_type as task_entity_type,
          task.entity_id as task_entity_id
        from app.task_history history
        join app.tasks task on task.id = history.task_id and task.deleted_at is null
        left join app.profiles author_profile
          on author_profile.user_id = history.changed_by and author_profile.deleted_at is null
        left join app.profiles old_profile
          on old_profile.user_id = history.old_user_id and old_profile.deleted_at is null
        left join app.profiles new_profile
          on new_profile.user_id = history.new_user_id and new_profile.deleted_at is null
        where ($1::text is null or history.field = $1)
          and ($2::uuid is null or history.changed_by = $2)
          and ($3::timestamptz is null or history.changed_at >= $3)
          and ($4::timestamptz is null or history.changed_at < $4)
        order by history.changed_at desc, history.id desc
        limit $5
      `,
      [
        query.field ?? "due_at",
        query.changedBy ?? null,
        query.from ?? null,
        query.to ?? null,
        limit,
      ],
    );
    return { items: result.rows.map((row) => toTaskHistoryDto(row)) };
  }
}
