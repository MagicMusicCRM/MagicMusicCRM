import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { moscowTodayStartMs } from "./task-due-state";
import {
  ResolvedSharedTaskRow,
  SharedTaskMigrationEvidenceRow,
  SharedTaskReminderRow,
  SharedTaskRow,
  TaskAudienceRow,
  TaskCloseRow,
} from "./shared-task.types";

const taskRecipientRoles = ["admin", "manager", "director"] as const;

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
      priority: "low" | "medium" | "high";
      version: number;
      createdBy: string;
    },
  ) {
    return client.query<SharedTaskRow>(
      `
        insert into app.shared_tasks (
          id, title, body, all_day, start_at, end_at,
          linked_entity_type, linked_entity_id, priority, version, created_by
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
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
        input.priority,
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
      priority: "low" | "medium" | "high";
      version: number;
    },
  ) {
    return client.query<SharedTaskRow>(
      `
        update app.shared_tasks
        set title = $2, body = $3, all_day = $4, start_at = $5,
            end_at = $6, linked_entity_type = $7, linked_entity_id = $8,
            priority = $9, version = $10, updated_at = now()
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
        input.priority,
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
    input: {
      state?: "open" | "closed";
      limit: number;
      taskId?: string;
      linkedEntityType?: string;
      linkedEntityId?: string;
      q?: string;
      priority?: "low" | "medium" | "high";
      scope?: "mine" | "branch" | "school" | "all";
      from?: string;
      to?: string;
    },
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
          select visibility.scope_kind
          from app.shared_task_visibility visibility
          where visibility.task_id = task.id
            and visibility.user_id = $1::uuid
            and (
              $14::text is null
              or $14 = 'all'
              or visibility.scope_kind = $14
            )
          order by case visibility.scope_kind
            when 'mine' then 1 when 'branch' then 2
            when 'school' then 3 else 4
          end
          limit 1
        ) visible on true
        join lateral (
          select audience.*,
            case
              when visible.scope_kind <> 'mine'
                then 'scope:' || visible.scope_kind
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
              or visible.scope_kind <> 'mine'
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
          and (
            $7::uuid is null
            or task.id = $7
            or exists (
              select 1
              from app.shared_task_legacy_links legacy
              where legacy.legacy_task_id = $7
                and legacy.shared_task_id = task.id
            )
          )
          and ($8::text is null or task.linked_entity_type = $8)
          and ($9::uuid is null or task.linked_entity_id = $9)
          and (
            $10::text is null
            or lower(task.title || ' ' || coalesce(task.body, ''))
              like '%' || lower($10) || '%'
          )
          and ($11::text is null or task.priority = $11)
          and ($12::timestamptz is null or task.start_at >= $12)
          and ($13::timestamptz is null or task.start_at < $13)
        order by task.start_at, task.id
        limit $6
      `,
      [
        actorUserId,
        actorRole,
        taskRecipientRoles,
        ["director", "system_admin"],
        input.state ?? null,
        input.limit,
        input.taskId ?? null,
        input.linkedEntityType ?? null,
        input.linkedEntityId ?? null,
        input.q ?? null,
        input.priority ?? null,
        input.from ?? null,
        input.to ?? null,
        input.scope ?? null,
      ],
    );
  }

  history(taskId: string) {
    return this.database.query<{
      id: string;
      action: string;
      actor_user_id: string | null;
      actor_first_name: string | null;
      actor_last_name: string | null;
      before_ref: Record<string, unknown> | null;
      after_ref: Record<string, unknown> | null;
      created_at: Date | string;
    }>(
      `
        select audit.id, audit.action, audit.actor_user_id,
          profile.first_name as actor_first_name,
          profile.last_name as actor_last_name,
          audit.before_ref, audit.after_ref, audit.created_at
        from app.audit_events audit
        left join app.profiles profile
          on profile.user_id = audit.actor_user_id
         and profile.deleted_at is null
        where audit.entity_type = 'shared_task'
          and audit.entity_id = $1::text
        order by audit.created_at desc, audit.id desc
        limit 100
      `,
      [taskId],
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

  close(
    client: PoolClient,
    taskId: string,
    actorUserId: string,
    requestId: string,
  ) {
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
    const resolutions = rows.map((row) => ({
      task_id: row.id,
      matched_audience_id: row.matched_audience_id,
      matched_selector: {
        type: row.matched_audience_type,
        targetId: row.matched_target_id,
      },
      membership_version: row.membership_version,
    }));
    return this.database
      .query(
        `
          insert into app.task_audience_resolution_audits (
            task_id, action, actor_user_id, matched_audience_id,
            matched_selector, membership_version, membership_at, request_id
          )
          select resolution.task_id, 'list', $2::uuid,
            resolution.matched_audience_id, resolution.matched_selector,
            resolution.membership_version, now(), null
          from jsonb_to_recordset($1::jsonb) as resolution(
            task_id uuid,
            matched_audience_id uuid,
            matched_selector jsonb,
            membership_version text
          )
        `,
        [JSON.stringify(resolutions), actorUserId],
      )
      .then(() => undefined);
  }

  counters(
    actorUserId: string,
    _actorRole: string,
    filters: {
      q?: string;
      priority?: "low" | "medium" | "high";
      scope?: "mine" | "branch" | "school" | "all";
      from?: string;
      to?: string;
    } = {},
  ) {
    const nowMs = Date.now();
    return this.database
      .query<{ open: number | string; overdue: number | string }>(
        `
          select
            count(*) filter (where task.state = 'open')::int as open,
            count(*) filter (
              where task.state = 'open'
                and task.start_at < case
                  when task.all_day then $7::timestamptz
                  else $8::timestamptz
                end
            )::int as overdue
          from app.shared_tasks task
          where task.deleted_at is null
            and exists (
              select 1
              from app.shared_task_visibility visibility
              where visibility.task_id = task.id
                and visibility.user_id = $1::uuid
                and (
                  $6::text is null
                  or $6 = 'all'
                  or visibility.scope_kind = $6
                )
            )
            and (
              $2::text is null
              or lower(task.title || ' ' || coalesce(task.body, ''))
                like '%' || lower($2) || '%'
            )
            and ($3::text is null or task.priority = $3)
            and ($4::timestamptz is null or task.start_at >= $4)
            and ($5::timestamptz is null or task.start_at < $5)
        `,
        [
          actorUserId,
          filters.q ?? null,
          filters.priority ?? null,
          filters.from ?? null,
          filters.to ?? null,
          filters.scope ?? null,
          new Date(moscowTodayStartMs(nowMs)).toISOString(),
          new Date(nowMs).toISOString(),
        ],
      )
      .then((result) => ({
        open: Number(result.rows[0]?.open ?? 0),
        overdue: Number(result.rows[0]?.overdue ?? 0),
      }));
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
            on actor.id = link.user_id
           and actor.deleted_at is null
           and actor.role::text = any($2::text[])
          where audience.audience_type = 'branch'
            and assignment.branch_id = audience.target_id
            and assignment.deleted_at is null
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
      [taskId, taskRecipientRoles],
    );
  }

  previewAudienceRecipients(
    audiences: readonly {
      type: "user" | "branch" | "allBranches";
      targetId?: string;
    }[],
  ) {
    return this.database.query<{
      selector_index: number;
      selector_type: "user" | "branch" | "allBranches";
      target_id: string | null;
      selector_label: string | null;
      user_id: string | null;
      first_name: string | null;
      last_name: string | null;
      email: string | null;
      role: string | null;
    }>(
      `
        with selectors as (
          select (entry.ordinality - 1)::int as selector_index,
            entry.value->>'type' as selector_type,
            nullif(entry.value->>'targetId', '')::uuid as target_id
          from jsonb_array_elements($1::jsonb)
            with ordinality as entry(value, ordinality)
        ), matches as (
          select selector.selector_index, actor.id as user_id
          from selectors selector
          join app.users actor
            on selector.selector_type = 'user'
           and actor.id = selector.target_id
           and actor.deleted_at is null
           and actor.role::text = any($2::text[])
          union all
          select selector.selector_index, link.user_id
          from selectors selector
          join app.staff_branch_assignments assignment
            on selector.selector_type = 'branch'
           and assignment.branch_id = selector.target_id
           and assignment.deleted_at is null
          join app.staff_members staff
            on staff.id = assignment.staff_member_id
           and staff.deleted_at is null
          join app.user_crm_links link
            on link.entity_type::text = 'staff'
           and link.entity_id = staff.id
           and link.deleted_at is null
          join app.users actor
            on actor.id = link.user_id
           and actor.deleted_at is null
           and actor.role::text = any($2::text[])
          union all
          select selector.selector_index, actor.id
          from selectors selector
          join app.users actor
            on selector.selector_type = 'allBranches'
           and actor.deleted_at is null
           and actor.role::text = any($2::text[])
        ), unique_matches as (
          select distinct selector_index, user_id from matches
        )
        select selector.selector_index, selector.selector_type,
          selector.target_id,
          case
            when selector.selector_type = 'allBranches' then 'Вся школа'
            when selector.selector_type = 'branch' then branch.name
            else coalesce(
              nullif(trim(concat_ws(' ', target_profile.first_name,
                target_profile.last_name)), ''), target_user.email
            )
          end as selector_label,
          matched.user_id, recipient_profile.first_name,
          recipient_profile.last_name, recipient.email,
          recipient.role::text as role
        from selectors selector
        left join unique_matches matched
          on matched.selector_index = selector.selector_index
        left join app.users recipient on recipient.id = matched.user_id
        left join app.profiles recipient_profile
          on recipient_profile.user_id = recipient.id
         and recipient_profile.deleted_at is null
        left join app.branches branch
          on selector.selector_type = 'branch'
         and branch.id = selector.target_id
        left join app.users target_user
          on selector.selector_type = 'user'
         and target_user.id = selector.target_id
        left join app.profiles target_profile
          on target_profile.user_id = target_user.id
         and target_profile.deleted_at is null
        order by selector.selector_index, matched.user_id nulls last
      `,
      [JSON.stringify(audiences), taskRecipientRoles],
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
    const result =
      type === "user"
        ? await this.database.query(
            `select 1 from app.users
             where id = $1 and deleted_at is null
               and role::text = any($2::text[])`,
            [targetId, taskRecipientRoles],
          )
        : await this.database.query(
            "select 1 from app.branches where id = $1 and deleted_at is null",
            [targetId],
          );
    return result.rowCount === 1;
  }
}
