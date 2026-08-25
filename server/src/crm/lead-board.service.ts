import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { branchIdExpr } from "./branch-scope";
import { typedClientTableFieldsSql } from "./clients/client-config.repository";
import { CrmPolicy } from "./crm.policy";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { assembleLeadBoard } from "./lead-board-assembler";
import { buildLeadBoardFilter } from "./lead-board-filter";
import {
  LeadBoardCountRow,
  LeadBoardRow,
  LeadStatusRow,
} from "./lead-model";
import { StudentFunnelService } from "./student-funnel.service";

@Injectable()
export class LeadBoardService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly pipelines: StudentFunnelService,
  ) {}

  async list(actor: ActorContext, query: LeadBoardQuery) {
    this.policy.assertCanWriteCrm(actor);
    const pipeline = await this.pipelines.getEffective(
      actor,
      query.branchId,
      "lead",
    );
    const limit = Math.min(query.limit ?? 25, 50);
    const sortDirection = query.sort === "oldest" ? "asc" : "desc";
    const requestedColumnId =
      query.unassigned === true ? "unassigned" : (query.statusId ?? null);
    const unassignedSortResult = await this.database.query<{ value: number }>(
      `select value::int as value from app.system_settings
        where key = 'lead_board_unassigned_sort_order'`,
    );
    const unassignedSort = unassignedSortResult.rows[0]?.value ?? null;
    const filter = buildLeadBoardFilter(query, actor.userId);
    const countFilter = buildLeadBoardFilter(
      { ...query, cursor: undefined },
      actor.userId,
    );
    const [statusResult, countResult, leadResult] = await Promise.all([
      this.listStatuses(),
      this.countLeads(countFilter.where, countFilter.params),
      this.listRows(
        filter.where,
        filter.params,
        actor.userId,
        limit,
        sortDirection,
      ),
    ]);
    return assembleLeadBoard({
      statuses: statusResult.rows,
      counts: countResult.rows,
      rows: leadResult.rows,
      stages: pipeline.stages,
      limit,
      requestedColumnId,
      unassignedSort,
    });
  }

  private listStatuses() {
    return this.database.query<LeadStatusRow>(
      `
        select id, stage_key, name, color, sort_order, created_at, requires_reason, is_terminal
        from app.lead_statuses
        order by sort_order asc, name asc, id asc
      `,
    );
  }

  private countLeads(where: string, params: unknown[]) {
    return this.database.query<LeadBoardCountRow>(
      `
        select l.status_id, count(*) as count
        from app.leads l
        left join app.lead_statuses ls on ls.id = l.status_id
        where ${where}
        group by l.status_id
      `,
      params,
    );
  }

  private listRows(
    where: string,
    params: unknown[],
    actorUserId: string,
    limit: number,
    sortDirection: "asc" | "desc",
  ) {
    return this.database.query<LeadBoardRow>(
      `
        with filtered as (
          select l.id, l.status_id, ls.stage_key as status_key,
            ls.name as status_name, ls.color as status_color,
            ls.sort_order as status_sort_order, l.first_name, l.last_name, l.phone,
            l.email, l.source, l.notes, l.assigned_to, l.blacklisted, l.blacklist_reason, l.custom_data,
            ${typedClientTableFieldsSql("lead", "l.id")} as table_custom_fields,
            assigned_profile.first_name as assigned_first_name,
            assigned_profile.last_name as assigned_last_name,
            ${branchIdExpr("l")} as branch_id,
            b.name as branch_name,
            linked_student.id as linked_student_id,
            (
              select link.user_id
              from app.user_crm_links link
              join app.users chat_user on chat_user.id = link.user_id
                and chat_user.deleted_at is null
                and chat_user.is_app_account = true
              where link.entity_type = 'lead'
                and link.entity_id = l.id
                and link.deleted_at is null
              order by link.confirmed_at desc nulls last, link.created_at desc, link.id desc
              limit 1
            ) as linked_user_id,
            (
              select count(*)
              from app.canonical_tasks task
              where task.deleted_at is null
                and task.entity_type = 'lead'
                and task.entity_id = l.id
                and task.status in ('open', 'in_progress')
                and exists (
                  select 1 from app.shared_task_visibility visibility
                  where visibility.task_id = task.id
                    and visibility.user_id = $${params.length + 1}::uuid
                )
            ) as open_tasks_count,
            (
              select count(*)
              from app.entity_comments comment
              where comment.deleted_at is null
                and comment.entity_type = 'lead'
                and comment.entity_id = l.id
            ) as comments_count,
            (
              select count(*)
              from app.lessons lesson
              where lesson.deleted_at is null
                and lesson.lead_id = l.id
                and lesson.is_trial = true
            ) as trial_lessons_count,
            l.created_by, l.created_at, l.updated_at,
            to_char(
              l.created_at at time zone 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ) as cursor_created_at,
            row_number() over (
              partition by coalesce(l.status_id::text, 'unassigned')
              order by l.created_at ${sortDirection}, l.id ${sortDirection}
            ) as rn
          from app.leads l
          left join app.lead_statuses ls on ls.id = l.status_id
          left join app.users assigned_user on assigned_user.id = l.assigned_to and assigned_user.deleted_at is null
          left join app.profiles assigned_profile on assigned_profile.user_id = assigned_user.id and assigned_profile.deleted_at is null
          left join app.branches b
            on b.id::text = ${branchIdExpr("l")}
           and b.deleted_at is null
          left join app.students linked_student
            on linked_student.lead_id = l.id
           and linked_student.deleted_at is null
          where ${where}
        )
        select *
        from filtered
        where rn <= $${params.length + 2}
        order by status_sort_order nulls last, status_name nulls last,
          created_at ${sortDirection}, id ${sortDirection}
      `,
      [...params, actorUserId, limit + 1],
    );
  }
}
