import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { branchIdExpr } from "../crm/branch-scope";
import {
  CLIENT_STATUS_FILTER_VERSION,
  ClientStatusFilterQuery,
  ClientStatusType,
} from "./dto/client-status-filter.query";

interface ClientStatusRow {
  client_type: ClientStatusType;
  client_id: string;
  display_name: string;
  status_key: string;
  status_label: string;
  branch_id: string | null;
  created_at: string;
  total_count?: string;
  count?: string;
}

export interface ClientStatusFilterSpec {
  version: typeof CLIENT_STATUS_FILTER_VERSION;
  clientType?: ClientStatusType;
  status?: string;
  branchId?: string;
  from?: string;
  to?: string;
  q?: string;
}

export interface ReportingEntityLink {
  entityType: string;
  entityId: string;
  optionalFocus?: {
    filter: ClientStatusFilterSpec;
  };
}

@Injectable()
export class ClientStatusReadService {
  constructor(private readonly database: DatabaseService) {}

  async summary(actor: ActorContext, query: ClientStatusFilterQuery) {
    const filter = this.normalizeFilter(actor, query);
    const { sql, params } = this.filteredClientsQuery(actor, filter);
    const result = await this.database.query<ClientStatusRow>(
      `
        with filtered as (${sql})
        select
          client_type,
          null::uuid as client_id,
          ''::text as display_name,
          status_key,
          status_label,
          null::text as branch_id,
          min(created_at)::text as created_at,
          count(*)::text as count
        from filtered
        group by client_type, status_key, status_label
        order by client_type, status_label, status_key
      `,
      params,
    );
    return {
      filter,
      total: result.rows.reduce((sum, row) => sum + Number(row.count), 0),
      items: result.rows.map((row) => {
        const itemFilter: ClientStatusFilterSpec = {
          ...filter,
          clientType: row.client_type,
          status: row.status_key,
        };
        return {
          clientType: row.client_type,
          status: row.status_key,
          label: row.status_label,
          count: Number(row.count),
          drilldown: {
            entityType: "client_status_list",
            entityId: `${row.client_type}:${row.status_key}`,
            optionalFocus: { filter: itemFilter },
          } satisfies ReportingEntityLink,
        };
      }),
    };
  }

  async list(actor: ActorContext, query: ClientStatusFilterQuery) {
    const filter = this.normalizeFilter(actor, query);
    const { sql, params } = this.filteredClientsQuery(actor, filter);
    const limit = Math.min(query.limit ?? 50, 200);
    const offset = Math.max(query.offset ?? 0, 0);
    const result = await this.database.query<ClientStatusRow>(
      `
        with filtered as (${sql})
        select
          filtered.*,
          count(*) over ()::text as total_count
        from filtered
        order by created_at desc, client_type, client_id
        limit $${params.length + 1}
        offset $${params.length + 2}
      `,
      [...params, limit, offset],
    );
    return {
      filter,
      total: Number(result.rows[0]?.total_count ?? 0),
      limit,
      offset,
      items: result.rows.map((row) => ({
        type: row.client_type,
        id: row.client_id,
        displayName: row.display_name,
        status: row.status_key,
        statusLabel: row.status_label,
        branchId: row.branch_id,
        createdAt: row.created_at,
        entityLink: {
          entityType: row.client_type,
          entityId: row.client_id,
        } satisfies ReportingEntityLink,
      })),
    };
  }

  private normalizeFilter(
    actor: ActorContext,
    query: ClientStatusFilterQuery,
  ): ClientStatusFilterSpec {
    if (
      actor.role !== "manager" &&
      actor.role !== "director" &&
      actor.role !== "system_admin"
    ) {
      throw new ForbiddenException({
        code: "REPORT_STATUS_SCOPE_DENIED",
        message: "Client status report is not available for this actor.",
      });
    }
    const from = query.from ? new Date(query.from) : null;
    const to = query.to ? new Date(query.to) : null;
    if (
      (from && Number.isNaN(from.getTime())) ||
      (to && Number.isNaN(to.getTime())) ||
      (from && to && from >= to)
    ) {
      throw new BadRequestException({
        code: "INVALID_REPORT_FILTER",
        message: "Report date range is invalid.",
      });
    }
    const status = query.status?.trim();
    const q = query.q?.trim();
    return {
      version: CLIENT_STATUS_FILTER_VERSION,
      ...(query.clientType ? { clientType: query.clientType } : {}),
      ...(status ? { status } : {}),
      ...(query.branchId ? { branchId: query.branchId } : {}),
      ...(from ? { from: from.toISOString() } : {}),
      ...(to ? { to: to.toISOString() } : {}),
      ...(q ? { q } : {}),
    };
  }

  private filteredClientsQuery(
    actor: ActorContext,
    filter: ClientStatusFilterSpec,
  ): { sql: string; params: unknown[] } {
    const params: unknown[] = [
      actor.userId,
      actor.role,
      filter.clientType ?? null,
      filter.status ?? null,
      filter.branchId ?? null,
      filter.from ?? null,
      filter.to ?? null,
      filter.q ?? null,
    ];
    const leadBranch = branchIdExpr("lead");
    const studentBranch = branchIdExpr("student");
    const actorBranchScope = (branchExpression: string) => `
      (
        $2::text in ('director', 'system_admin')
        or (
          $2::text = 'manager'
          and ${branchExpression} is not null
          and exists (
            select 1
            from app.staff_members scoped_staff
            join app.profiles scoped_profile
              on scoped_profile.id = scoped_staff.profile_id
             and scoped_profile.deleted_at is null
            join app.staff_branch_assignments scoped_assignment
              on scoped_assignment.staff_member_id = scoped_staff.id
             and scoped_assignment.deleted_at is null
            where scoped_staff.deleted_at is null
              and scoped_profile.user_id = $1
              and scoped_assignment.branch_id::text = ${branchExpression}
          )
        )
      )
    `;
    return {
      params,
      sql: `
        select
          'lead'::text as client_type,
          lead.id as client_id,
          coalesce(
            nullif(btrim(concat_ws(' ', lead.first_name, lead.last_name)), ''),
            'Без имени'
          ) as display_name,
          coalesce(lead_status.stage_key, 'new') as status_key,
          coalesce(lead_status.name, 'Новые') as status_label,
          ${leadBranch} as branch_id,
          lead.created_at
        from app.leads lead
        left join app.lead_statuses lead_status
          on lead_status.id = lead.status_id
        where lead.deleted_at is null
          and ($3::text is null or $3 = 'lead')
          and (
            $4::text is null
            or coalesce(lead_status.stage_key, 'new') = $4
          )
          and ($5::uuid is null or ${leadBranch} = $5::text)
          and ($6::timestamptz is null or lead.created_at >= $6)
          and ($7::timestamptz is null or lead.created_at < $7)
          and (
            $8::text is null
            or btrim(concat_ws(' ', lead.first_name, lead.last_name))
              ilike '%' || $8 || '%'
          )
          and ${actorBranchScope(leadBranch)}
        union all
        select
          'student'::text as client_type,
          student.id as client_id,
          coalesce(
            nullif(
              btrim(concat_ws(' ', student_profile.first_name, student_profile.last_name)),
              ''
            ),
            'Без имени'
          ) as display_name,
          coalesce(nullif(student.status, ''), 'unknown') as status_key,
          coalesce(nullif(student.status, ''), 'Без статуса') as status_label,
          ${studentBranch} as branch_id,
          student.created_at
        from app.students student
        left join app.profiles student_profile
          on student_profile.id = student.profile_id
         and student_profile.deleted_at is null
        where student.deleted_at is null
          and ($3::text is null or $3 = 'student')
          and (
            $4::text is null
            or coalesce(nullif(student.status, ''), 'unknown') = $4
          )
          and ($5::uuid is null or ${studentBranch} = $5::text)
          and ($6::timestamptz is null or student.created_at >= $6)
          and ($7::timestamptz is null or student.created_at < $7)
          and (
            $8::text is null
            or btrim(
              concat_ws(' ', student_profile.first_name, student_profile.last_name)
            ) ilike '%' || $8 || '%'
          )
          and ${actorBranchScope(studentBranch)}
      `,
    };
  }
}
