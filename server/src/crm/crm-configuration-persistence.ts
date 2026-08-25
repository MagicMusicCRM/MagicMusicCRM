import { NotFoundException } from "@nestjs/common";
import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import type { DatabaseService } from "../db/database.service";
import {
  buildCrmConfigurationBaseline,
  type ClientFieldDefinitionRow,
} from "./crm-configuration-baseline";
import { applyCrmConfigurationBranchPatch } from "./crm-configuration-branch.policy";
import type {
  ConfigBranchPatch,
  ConfigSnapshot,
} from "./crm-configuration.contracts";
import { normalizeCrmConfigurationSnapshot } from "./crm-configuration-snapshot-normalizer";

export interface CrmConfigurationRevisionRow {
  id: string;
  branch_id: string | null;
  version: number | string;
  patch: ConfigSnapshot | ConfigBranchPatch;
  effective_snapshot: ConfigSnapshot;
  impact: Record<string, unknown>;
  reason: string;
  rollback_from_version: number | string | null;
  created_by: string | null;
  created_at: Date | string;
}

export type CrmConfigurationQueryable =
  | Pick<PoolClient, "query">
  | DatabaseService;

function runQuery<T extends QueryResultRow>(
  queryable: CrmConfigurationQueryable,
  text: string,
  params: unknown[] = [],
): Promise<QueryResult<T>> {
  return (
    queryable.query as (
      query: string,
      values?: unknown[],
    ) => Promise<QueryResult<T>>
  )(text, params);
}

export async function hasStoredCrmClientFieldValues(
  queryable: CrmConfigurationQueryable,
  definitionId: string,
): Promise<boolean> {
  const result = await runQuery<{ count: number | string }>(
    queryable,
    "select count(*) as count from app.client_custom_field_values where definition_id = $1",
    [definitionId],
  );
  return Number(result.rows[0]?.count ?? 0) > 0;
}

export async function assertCrmConfigurationBranch(
  queryable: CrmConfigurationQueryable,
  branchId: string,
): Promise<void> {
  const result = await runQuery<{ present: boolean }>(
    queryable,
    "select exists (select 1 from app.branches where id = $1 and deleted_at is null) as present",
    [branchId],
  );
  if (!result.rows[0]?.present) {
    throw new NotFoundException("Филиал не найден.");
  }
}

export async function resolveEffectiveCrmConfiguration(
  queryable: CrmConfigurationQueryable,
  branchId?: string,
) {
  const school = await resolveSchoolCrmConfiguration(queryable);
  if (!branchId) {
    return {
      schoolVersion: school.version,
      branchVersion: 0,
      schoolSnapshot: school.snapshot,
      snapshot: school.snapshot,
    };
  }
  await assertCrmConfigurationBranch(queryable, branchId);
  const branch = await runQuery<CrmConfigurationRevisionRow>(
    queryable,
    `select id, branch_id, version, patch, effective_snapshot, impact,
       reason, rollback_from_version, created_by, created_at
     from app.crm_configuration_revisions
     where branch_id = $1 order by version desc limit 1`,
    [branchId],
  );
  const latest = branch.rows[0];
  return {
    schoolVersion: school.version,
    branchVersion: latest ? Number(latest.version) : 0,
    schoolSnapshot: school.snapshot,
    snapshot: latest
      ? applyCrmConfigurationBranchPatch(
          school.snapshot,
          latest.patch as ConfigBranchPatch,
        )
      : school.snapshot,
  };
}

export async function resolveSchoolCrmConfiguration(
  queryable: CrmConfigurationQueryable,
) {
  const result = await runQuery<CrmConfigurationRevisionRow>(
    queryable,
    `select id, branch_id, version, patch, effective_snapshot, impact,
       reason, rollback_from_version, created_by, created_at
     from app.crm_configuration_revisions
     where branch_id is null order by version desc limit 1`,
  );
  const row = result.rows[0];
  if (row) {
    return {
      version: Number(row.version),
      snapshot: normalizeCrmConfigurationSnapshot(
        row.effective_snapshot as unknown as Record<string, unknown>,
      ),
    };
  }
  const definitions = await runQuery<ClientFieldDefinitionRow>(
    queryable,
    `select id, field_key, label, value_type, is_required,
       is_active, is_system, category_key, category_label, sort_order, width,
       placements, options, visible_on_lead, visible_on_student
     from app.client_custom_field_definitions
     where is_active = true and deleted_at is null
     order by sort_order, label`,
  );
  return {
    version: 0,
    snapshot: buildCrmConfigurationBaseline(definitions.rows),
  };
}

export async function syncCrmClientFields(
  client: PoolClient,
  snapshot: ConfigSnapshot,
): Promise<ConfigSnapshot> {
  const categoryLabels = new Map(
    snapshot.categories.map((category) => [category.key, category.label]),
  );
  for (const field of snapshot.fields) {
    field.id = await upsertCrmClientField(client, field, categoryLabels);
  }
  await deactivateMissingCrmClientFields(
    client,
    snapshot.fields.map((field) => field.key),
  );
  return snapshot;
}

async function upsertCrmClientField(
  client: PoolClient,
  field: ConfigSnapshot["fields"][number],
  categoryLabels: Map<string, string>,
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `insert into app.client_custom_field_definitions (
       field_key, label, value_type, is_required, is_active,
       is_system, options, category_key, category_label, sort_order, width,
       placements, visible_on_lead, visible_on_student
     ) values ($1, $2, $3, $4, $5, false, $6::jsonb, $7, $8, $9, $10,
       $11::jsonb, $12, $13)
     on conflict (field_key) do update set
       label = excluded.label,
       value_type = case when app.client_custom_field_definitions.is_system
         then app.client_custom_field_definitions.value_type else excluded.value_type end,
       is_required = excluded.is_required,
       is_active = case when app.client_custom_field_definitions.is_system
         then true else excluded.is_active end,
       deleted_at = case when excluded.is_active then null else coalesce(app.client_custom_field_definitions.deleted_at, now()) end,
       options = excluded.options,
       category_key = excluded.category_key,
       category_label = excluded.category_label,
       sort_order = excluded.sort_order,
       width = excluded.width,
       placements = excluded.placements,
       visible_on_lead = case
         when app.client_custom_field_definitions.is_system
           then app.client_custom_field_definitions.visible_on_lead
         else excluded.visible_on_lead end,
       visible_on_student = case
         when app.client_custom_field_definitions.is_system
           then app.client_custom_field_definitions.visible_on_student
         else excluded.visible_on_student end,
       version = app.client_custom_field_definitions.version + 1,
       updated_at = now()
     returning id`,
    [
      field.key,
      field.label,
      field.valueType,
      field.required,
      field.active,
      JSON.stringify(field.options),
      field.categoryKey,
      categoryLabels.get(field.categoryKey) ?? field.categoryKey,
      field.order,
      field.width,
      JSON.stringify(field.placements),
      field.visibility.lead,
      field.visibility.student,
    ],
  );
  return result.rows[0]!.id;
}

async function deactivateMissingCrmClientFields(
  client: PoolClient,
  activeKeys: string[],
): Promise<void> {
  await client.query(
    `update app.client_custom_field_definitions definition
     set is_active = false, deleted_at = coalesce(deleted_at, now()),
       version = version + 1, updated_at = now()
     where not definition.is_system
       and not (definition.field_key = any($1::text[]))
       and definition.is_active`,
    [activeKeys],
  );
}

export function crmConfigurationRevisionDto(
  row: CrmConfigurationRevisionRow,
) {
  return {
    id: row.id,
    branchId: row.branch_id,
    version: Number(row.version),
    reason: row.reason,
    rollbackFromVersion:
      row.rollback_from_version === null
        ? null
        : Number(row.rollback_from_version),
    createdBy: row.created_by,
    createdAt: row.created_at,
    snapshot: row.effective_snapshot,
    patch: row.patch,
    impact: row.impact,
  };
}
