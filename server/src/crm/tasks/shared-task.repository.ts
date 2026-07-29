import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  ResolvedSharedTaskRow,
  SharedTaskMigrationEvidenceRow,
  SharedTaskReminderRow,
  SharedTaskRow,
  TaskAudienceRow,
  TaskCloseRow,
} from "./shared-task.types";

@Injectable()
export class SharedTaskRepository {
  constructor(private readonly database: DatabaseService) {}

  migrationEvidence(
    legacyTaskIds: readonly string[],
  ): Promise<{ rows: SharedTaskMigrationEvidenceRow[] }> {
    return this.database.query<SharedTaskMigrationEvidenceRow>(
      `
        select
          legacy_task_id,
          shared_task_id,
          merge_proof,
          source_fingerprint
        from app.shared_task_legacy_links
        where legacy_task_id = any($1::uuid[])
        order by legacy_task_id
      `,
      [legacyTaskIds],
    );
  }

  lock(client: PoolClient, taskId: string) {
    return client.query<SharedTaskRow>(
      `
        select *
        from app.shared_tasks
        where id = $1 and deleted_at is null
        for update
      `,
      [taskId],
    );
  }

  find(taskId: string) {
    return this.database.query<SharedTaskRow>(
      `
        select *
        from app.shared_tasks
        where id = $1 and deleted_at is null
      `,
      [taskId],
    );
  }

  audiences(client: PoolClient, taskId: string) {
    return client.query<TaskAudienceRow>(
      `
        select *
        from app.task_audiences
        where task_id = $1
        order by audience_type, target_id nulls first, id
      `,
      [taskId],
    );
  }

  audienceProjection(taskId: string) {
    return this.database.query<TaskAudienceRow>(
      `
        select *
        from app.task_audiences
        where task_id = $1
        order by audience_type, target_id nulls first, id
      `,
      [taskId],
    );
  }

  audienceProjectionForTasks(taskIds: readonly string[]) {
    if (taskIds.length === 0) {
      return Promise.resolve({ rows: [] as TaskAudienceRow[] });
    }
    return this.database.query<TaskAudienceRow>(
      `
        select *
        from app.task_audiences
        where task_id = any($1::uuid[])
        order by task_id, audience_type, target_id nulls first, id
      `,
      [taskIds],
    );
  }

  reminderProjection(taskId: string) {
    return this.database.query<SharedTaskReminderRow>(
      `
        select *
        from app.shared_task_reminders
        where task_id = $1 and status in ('pending', 'claimed')
        order by due_at, channel, id
      `,
      [taskId],
    );
  }

  reminderProjectionForTasks(taskIds: readonly string[]) {
    if (taskIds.length === 0) {
      return Promise.resolve({ rows: [] as SharedTaskReminderRow[] });
    }
    return this.database.query<SharedTaskReminderRow>(
      `
        select *
        from app.shared_task_reminders
        where task_id = any($1::uuid[])
          and status in ('pending', 'claimed')
        order by task_id, due_at, channel, id
      `,
      [taskIds],
    );
  }

  create(
    client: PoolClient,
    input: {
      id: string;
      title: string;
      body: string | null;
      allDay: boolean;
      startAt: string;
      endAt: string | null;
      linkedEntityType: string | null;
      linkedEntityId: string | null;
      version: number;
      createdBy: string;
    },
  ) {
    return client.query<SharedTaskRow>(
      `
        insert into app.shared_tasks (
          id, title, body, all_day, start_at, end_at,
          linked_entity_type, linked_entity_id, version, created_by
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        returning *
      `,
      [
        input.id,
        input.title,
        input.body,
        input.allDay,
        input.startAt,
        input.endAt,
        input.linkedEntityType,
        input.linkedEntityId,
        input.version,
        input.createdBy,
      ],
    );
  }

  update(
    client: PoolClient,
    taskId: string,
    input: {
      title: string;
      body: string | null;
      allDay: boolean;
      startAt: string;
      endAt: string | null;
      linkedEntityType: string | null;
      linkedEntityId: string | null;
      version: number;
    },
  ) {
    return client.query<SharedTaskRow>(
      `
        update app.shared_tasks
        set title = $2, body = $3, all_day = $4, start_at = $5,
            end_at = $6, linked_entity_type = $7, linked_entity_id = $8,
            version = $9, updated_at = now()
        where id = $1 and state = 'open' and deleted_at is null
        returning *
      `,
      [
        taskId,
        input.title,
        input.body,
        input.allDay,
        input.startAt,
        input.endAt,
        input.linkedEntityType,
        input.linkedEntityId,
        input.version,
      ],
    );
  }

  async replaceAudiences(
    client: PoolClient,
    taskId: string,
    audiences: readonly {
      type: "user" | "branch" | "allBranches";
      targetId?: string;
    }[],
  ): Promise<void> {
    await client.query("delete from app.task_audiences where task_id = $1", [
      taskId,
    ]);
    for (const audience of audiences) {
      await client.query(
        `
          insert into app.task_audiences (task_id, audience_type, target_id)
          values ($1, $2, $3)
        `,
        [taskId, audience.type, audience.targetId ?? null],
      );
    }
  }

  async replaceReminders(
    client: PoolClient,
    taskId: string,
    reminders: readonly {
      dueAt: string;
      channel: "in_app" | "push" | "email";
    }[],
  ): Promise<void> {
    await client.query(
      `
        update app.shared_task_reminders
        set status = 'cancelled', updated_at = now()
        where task_id = $1 and status in ('pending', 'claimed')
      `,
      [taskId],
    );
    for (const reminder of reminders) {
      await client.query(
        `
          insert into app.shared_task_reminders (
            task_id, due_at, channel, dedupe_key, next_attempt_at
          )
          values (
            $1::uuid, $2::timestamptz, $3::text,
            ($1::uuid)::text || ':' || ($2::timestamptz)::text || ':' || $3::text,
            $2::timestamptz
          )
          on conflict (dedupe_key) do update
          set status = case
                when app.shared_task_reminders.status = 'delivered'
                  then 'delivered'
                else 'pending'
              end,
              next_attempt_at = excluded.next_attempt_at,
              updated_at = now()
        `,
        [taskId, reminder.dueAt, reminder.channel],
      );
    }
  }

  listResolved(
    actorUserId: string,
    actorRole: string,
    input: { state?: "open" | "closed"; limit: number; taskId?: string },
  ) {
    return this.database.query<ResolvedSharedTaskRow>(
      `
        select task.*, matched.id as matched_audience_id,
          matched.audience_type as matched_audience_type,
          matched.target_id as matched_target_id,
          matched.membership_version,
          close.id as close_id, close.closed_at, close.closed_by,
          close.request_id as close_request_id
        from app.shared_tasks task
        join lateral (
          select audience.*,
            case
              when audience.audience_type = 'user'
                then 'user:' || $1::text
              when audience.audience_type = 'allBranches'
                then 'role:' || $2::text
              else coalesce(membership.membership_version, 'root:' || $2::text)
            end as membership_version
          from app.task_audiences audience
          left join lateral (
            select membership_version
            from (
              select 'teacher:' || tb.id::text || ':' ||
                greatest(tb.created_at, coalesce(tb.updated_at, tb.created_at))::text
                as membership_version
              from app.user_crm_links link
              join app.teachers teacher
                on link.entity_type::text = 'teacher'
               and teacher.id = link.entity_id
               and teacher.deleted_at is null
              join app.teacher_branches tb
                on tb.teacher_id = teacher.id
               and tb.branch_id = audience.target_id
               and tb.active_from <= now()
               and (tb.active_until is null or tb.active_until > now())
              where link.user_id = $1::uuid and link.deleted_at is null
              union all
              select 'staff:' || assignment.id::text || ':' ||
                assignment.created_at::text
              from app.user_crm_links link
              join app.staff_members staff
                on link.entity_type::text = 'staff'
               and staff.id = link.entity_id
               and staff.deleted_at is null
              join app.staff_branch_assignments assignment
                on assignment.staff_member_id = staff.id
               and assignment.branch_id = audience.target_id
               and assignment.deleted_at is null
              where link.user_id = $1::uuid and link.deleted_at is null
            ) current_membership
            limit 1
          ) membership on audience.audience_type = 'branch'
          where audience.task_id = task.id
            and (
              (audience.audience_type = 'user' and audience.target_id = $1::uuid)
              or (
                audience.audience_type = 'allBranches'
                and $2 = any($3::text[])
              )
              or (
                audience.audience_type = 'branch'
                and (
                  membership.membership_version is not null
                  or $2 = any($4::text[])
                )
              )
            )
          order by
            case audience.audience_type
              when 'user' then 1 when 'branch' then 2 else 3
            end,
            audience.id
          limit 1
        ) matched on true
        left join app.task_closes close on close.task_id = task.id
        where task.deleted_at is null
          and ($5::text is null or task.state = $5)
          and ($7::uuid is null or task.id = $7)
        order by task.start_at, task.id
        limit $6
      `,
      [
        actorUserId,
        actorRole,
        ["teacher", "admin", "manager", "director", "system_admin"],
        ["director", "system_admin"],
        input.state ?? null,
        input.limit,
        input.taskId ?? null,
      ],
    );
  }

  resolved(
    actorUserId: string,
    actorRole: string,
    taskId: string,
  ): Promise<{ rows: ResolvedSharedTaskRow[] }> {
    return this.listResolved(actorUserId, actorRole, {
      limit: 1,
      taskId,
    });
  }

  close(client: PoolClient, taskId: string, actorUserId: string, requestId: string) {
    return client.query<TaskCloseRow>(
      `
        with inserted as (
          insert into app.task_closes (task_id, closed_by, request_id)
          values ($1, $2, $3)
          on conflict (task_id) do nothing
          returning *
        )
        select * from inserted
        union all
        select * from app.task_closes
        where task_id = $1 and not exists (select 1 from inserted)
        limit 1
      `,
      [taskId, actorUserId, requestId],
    );
  }

  recordResolution(
    client: PoolClient,
    row: ResolvedSharedTaskRow,
    action: "list" | "close",
    actorUserId: string,
    requestId?: string,
  ) {
    return client.query(
      `
        insert into app.task_audience_resolution_audits (
          task_id, action, actor_user_id, matched_audience_id,
          matched_selector, membership_version, membership_at, request_id
        )
        values ($1, $2, $3, $4, $5::jsonb, $6, now(), $7)
      `,
      [
        row.id,
        action,
        actorUserId,
        row.matched_audience_id,
        JSON.stringify({
          type: row.matched_audience_type,
          targetId: row.matched_target_id,
        }),
        row.membership_version,
        requestId ?? null,
      ],
    );
  }

  recordListResolutions(
    rows: readonly ResolvedSharedTaskRow[],
    actorUserId: string,
  ): Promise<void> {
    if (rows.length === 0) return Promise.resolve();
    return this.database.transaction(async (client) => {
      for (const row of rows) {
        await this.recordResolution(client, row, "list", actorUserId);
      }
    });
  }

  counters(actorUserId: string, actorRole: string) {
    return this.listResolved(actorUserId, actorRole, {
      limit: 2_147_483_647,
    }).then(
      (result) => {
        const now = Date.now();
        return {
          open: result.rows.filter((row) => row.state === "open").length,
          overdue: result.rows.filter(
            (row) =>
              row.state === "open" &&
              row.start_at !== null &&
              new Date(row.start_at).getTime() < now,
          ).length,
        };
      },
    );
  }

  claimDueReminders(
    workerId: string,
    input: { limit: number; leaseSeconds: number; maxAttempts: number },
  ): Promise<SharedTaskReminderRow[]> {
    return this.database.transaction(async (client) => {
      await client.query(
        `
          update app.shared_task_reminders reminder
          set status = 'poison', claimed_by = null, claimed_at = null,
              updated_at = now()
          from app.shared_tasks task
          where task.id = reminder.task_id
            and task.state = 'open'
            and task.deleted_at is null
            and reminder.attempts >= $1
            and (
              (
                reminder.status = 'pending'
                and coalesce(reminder.next_attempt_at, reminder.due_at) <= now()
              )
              or (
                reminder.status = 'claimed'
                and reminder.claimed_at <
                  now() - make_interval(secs => $2::int)
              )
            )
        `,
        [input.maxAttempts, input.leaseSeconds],
      );
      const result = await client.query<SharedTaskReminderRow>(
        `
          with due as (
            select reminder.id
            from app.shared_task_reminders reminder
            join app.shared_tasks task
              on task.id = reminder.task_id
             and task.state = 'open'
             and task.deleted_at is null
            where (
                reminder.status = 'pending'
                and coalesce(reminder.next_attempt_at, reminder.due_at) <= now()
              )
              or (
                reminder.status = 'claimed'
                and reminder.claimed_at <
                  now() - make_interval(secs => $2::int)
              )
            order by coalesce(reminder.next_attempt_at, reminder.due_at), reminder.id
            for update of reminder skip locked
            limit $1
          )
          update app.shared_task_reminders reminder
          set status = case
                when reminder.attempts >= $3 then 'poison'
                else 'claimed'
              end,
              attempts = reminder.attempts + 1,
              claimed_at = now(),
              claimed_by = $4,
              updated_at = now()
          from due
          where reminder.id = due.id
            and reminder.attempts < $3
          returning reminder.*
        `,
        [input.limit, input.leaseSeconds, input.maxAttempts, workerId],
      );
      return result.rows;
    });
  }

  reminderRecipients(taskId: string): Promise<{ rows: { user_id: string }[] }> {
    return this.database.query<{ user_id: string }>(
      `
        select distinct recipient.user_id
        from app.task_audiences audience
        cross join lateral (
          select actor.id as user_id
          from app.users actor
          where audience.audience_type = 'user'
            and actor.id = audience.target_id
            and actor.deleted_at is null
            and actor.role::text = any($2::text[])
          union all
          select link.user_id
          from app.staff_branch_assignments assignment
          join app.staff_members staff
            on staff.id = assignment.staff_member_id
           and staff.deleted_at is null
          join app.user_crm_links link
            on link.entity_type::text = 'staff'
           and link.entity_id = staff.id
           and link.deleted_at is null
          join app.users actor
            on actor.id = link.user_id and actor.deleted_at is null
          where audience.audience_type = 'branch'
            and assignment.branch_id = audience.target_id
            and assignment.deleted_at is null
          union all
          select link.user_id
          from app.teacher_branches assignment
          join app.teachers teacher
            on teacher.id = assignment.teacher_id
           and teacher.deleted_at is null
          join app.user_crm_links link
            on link.entity_type::text = 'teacher'
           and link.entity_id = teacher.id
           and link.deleted_at is null
          join app.users actor
            on actor.id = link.user_id and actor.deleted_at is null
          where audience.audience_type = 'branch'
            and assignment.branch_id = audience.target_id
            and assignment.active_from <= now()
            and (assignment.active_until is null or assignment.active_until > now())
          union all
          select actor.id
          from app.users actor
          where audience.audience_type = 'allBranches'
            and actor.deleted_at is null
            and actor.role::text = any($2::text[])
        ) recipient
        where audience.task_id = $1
          and recipient.user_id is not null
      `,
      [
        taskId,
        ["teacher", "admin", "manager", "director", "system_admin"],
      ],
    );
  }

  markReminderDelivered(reminderId: string, workerId: string) {
    return this.database.query(
      `
        update app.shared_task_reminders
        set status = 'delivered', delivered_at = now(), claimed_by = null,
            claimed_at = null, last_error = null, updated_at = now()
        where id = $1 and status = 'claimed' and claimed_by = $2
      `,
      [reminderId, workerId],
    );
  }

  markReminderFailed(
    reminder: SharedTaskReminderRow,
    workerId: string,
    errorName: string,
    input: { maxAttempts: number; baseSeconds: number; capSeconds: number },
  ) {
    const attempts = Number(reminder.attempts);
    const poison = attempts >= input.maxAttempts;
    const delay = Math.min(
      input.capSeconds,
      input.baseSeconds * 2 ** Math.max(0, attempts - 1),
    );
    return this.database.query(
      `
        update app.shared_task_reminders
        set status = $3,
            next_attempt_at = case
              when $3 = 'poison' then next_attempt_at
              else now() + make_interval(secs => $4::int)
            end,
            claimed_by = null, claimed_at = null, last_error = $5,
            updated_at = now()
        where id = $1 and status = 'claimed' and claimed_by = $2
      `,
      [
        reminder.id,
        workerId,
        poison ? "poison" : "pending",
        delay,
        errorName.slice(0, 240),
      ],
    );
  }

  cancelPendingReminders(client: PoolClient, taskId: string) {
    return client.query(
      `
        update app.shared_task_reminders
        set status = 'cancelled', claimed_by = null, claimed_at = null,
            updated_at = now()
        where task_id = $1 and status in ('pending', 'claimed')
      `,
      [taskId],
    );
  }

  reminderMetrics() {
    return this.database.query<{
      pending: number;
      poison: number;
      oldest_due_at: Date | string | null;
    }>(
      `
        select
          count(*) filter (where status = 'pending')::int as pending,
          count(*) filter (where status = 'poison')::int as poison,
          min(coalesce(next_attempt_at, due_at))
            filter (where status = 'pending') as oldest_due_at
        from app.shared_task_reminders
      `,
    );
  }

  async entityExists(type: string, id: string): Promise<boolean> {
    const tables: Readonly<Record<string, string>> = {
      lead: "leads",
      student: "students",
      teacher: "teachers",
      lesson: "lessons",
      group: "groups",
      staff: "staff_members",
    };
    const table = tables[type];
    if (!table) return false;
    const result = await this.database.query(
      `select 1 from app.${table} where id = $1 and deleted_at is null`,
      [id],
    );
    return result.rowCount === 1;
  }

  async audienceTargetExists(
    type: "user" | "branch" | "allBranches",
    targetId?: string,
  ): Promise<boolean> {
    if (type === "allBranches") return targetId === undefined;
    const table = type === "user" ? "users" : "branches";
    const result = await this.database.query(
      `select 1 from app.${table} where id = $1 and deleted_at is null`,
      [targetId],
    );
    return result.rowCount === 1;
  }
}
