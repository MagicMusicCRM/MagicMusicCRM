import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  ResolvedSharedTaskRow,
  SharedTaskMigrationEvidenceRow,
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
