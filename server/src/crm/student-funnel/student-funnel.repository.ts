import { Injectable, NotFoundException } from "@nestjs/common";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import { DatabaseService } from "../../db/database.service";
import { ClientPipelineType } from "../dto/student-funnel.dto";
import {
  FunnelQueryable,
  FunnelRemediationRow,
  FunnelRevisionRow,
} from "./student-funnel.types";

const runQuery = <T extends QueryResultRow>(
  queryable: FunnelQueryable,
  text: string,
  params: unknown[],
): Promise<QueryResult<T>> =>
  (
    queryable.query as (
      query: string,
      values?: unknown[],
    ) => Promise<QueryResult<T>>
  )(text, params);

@Injectable()
export class StudentFunnelRepository {
  constructor(private readonly database: DatabaseService) {}

  async listRevisions(
    branchId: string | undefined,
    clientType: ClientPipelineType,
  ) {
    return this.database.query<FunnelRevisionRow>(
      `
        select id, client_type, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where client_type = $1
          and branch_id is not distinct from $2::uuid
        order by version desc
        limit 50
      `,
      [clientType, branchId ?? null],
    );
  }

  async findRevision(
    branchId: string | undefined,
    clientType: ClientPipelineType,
    version: number,
  ) {
    const result = await this.database.query<FunnelRevisionRow>(
      `
        select id, client_type, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where client_type = $1
          and branch_id is not distinct from $2::uuid
          and version = $3
        limit 1
      `,
      [clientType, branchId ?? null, version],
    );
    return result.rows[0] ?? null;
  }

  async latestRevision(
    queryable: FunnelQueryable,
    branchId: string | null,
    clientType: ClientPipelineType,
    lock: boolean,
  ): Promise<FunnelRevisionRow | null> {
    const result = await runQuery<FunnelRevisionRow>(
      queryable,
      `
        select id, client_type, branch_id, version, patch, effective_snapshot, reason,
          rollback_from_version, created_by, created_at
        from app.student_funnel_revisions
        where client_type = $1
          and branch_id is not distinct from $2::uuid
        order by version desc
        limit 1
        ${lock ? "for update" : ""}
      `,
      [clientType, branchId],
    );
    return result.rows[0] ?? null;
  }

  async assertBranch(queryable: FunnelQueryable, branchId: string) {
    const result = await runQuery<{ present: boolean }>(
      queryable,
      "select exists (select 1 from app.branches where id = $1 and deleted_at is null) as present",
      [branchId],
    );
    if (result.rows[0]?.present !== true) {
      throw new NotFoundException("Филиал не найден.");
    }
  }

  async remediationRows(
    clientType: ClientPipelineType,
    branchId: string | undefined,
    keys: string[],
  ): Promise<FunnelRemediationRow[]> {
    if (clientType === "lead") {
      return (
        await this.database.query<FunnelRemediationRow>(
          `
            select coalesce(status.stage_key, '__empty__') as status,
              count(*) as count
            from app.leads lead
            left join app.lead_statuses status on status.id = lead.status_id
            where lead.deleted_at is null
              and ($1::uuid is null or lead.branch_id = $1)
              and not (coalesce(status.stage_key, '__empty__') = any($2::text[]))
            group by coalesce(status.stage_key, '__empty__')
            order by count(*) desc, status asc
          `,
          [branchId ?? null, keys],
        )
      ).rows;
    }
    return (
      await this.database.query<FunnelRemediationRow>(
        `
          select coalesce(nullif(btrim(status), ''), '__empty__') as status,
            count(*) as count
          from app.students
          where deleted_at is null
            and ($1::uuid is null or branch_id = $1)
            and not (coalesce(nullif(btrim(status), ''), '__empty__') = any($2::text[]))
          group by coalesce(nullif(btrim(status), ''), '__empty__')
          order by count(*) desc, status asc
        `,
        [branchId ?? null, keys],
      )
    ).rows;
  }

  async countClients(
    clientType: ClientPipelineType,
    branchId: string | undefined,
    stageKeys: string[],
  ): Promise<number> {
    if (stageKeys.length === 0) return 0;
    const result =
      clientType === "lead"
        ? await this.database.query<{ count: string | number }>(
            `
            select count(*) as count
            from app.leads lead
            join app.lead_statuses status on status.id = lead.status_id
            where lead.deleted_at is null
              and ($1::uuid is null or lead.branch_id = $1)
              and status.stage_key = any($2::text[])
          `,
            [branchId ?? null, stageKeys],
          )
        : await this.database.query<{ count: string | number }>(
            `
            select count(*) as count
            from app.students
            where deleted_at is null
              and ($1::uuid is null or branch_id = $1)
              and status = any($2::text[])
          `,
            [branchId ?? null, stageKeys],
          );
    return Number(result.rows[0]?.count ?? 0);
  }

  async leadStatusKeys(client: PoolClient, statusIds: string[]) {
    const result = await client.query<{ id: string; stage_key: string }>(
      `select id, stage_key from app.lead_statuses where id = any($1::uuid[])`,
      [statusIds],
    );
    return new Map(result.rows.map((row) => [row.id, row.stage_key]));
  }
}
