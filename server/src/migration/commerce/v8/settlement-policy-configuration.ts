import type { PoolClient } from "pg";
import {
  buildCrmConfigurationBaseline,
  type ClientFieldDefinitionRow,
} from "../../../crm/crm-configuration-baseline";
import type { ConfigSnapshot } from "../../../crm/crm-configuration.contracts";
import { normalizeCrmConfigurationSnapshot } from "../../../crm/crm-configuration-snapshot-normalizer";

export const SYSTEM_SETTLEMENT_POLICY_REASON =
  "v8.system-settlement-policy";
const SYSTEM_SETTLEMENT_POLICY_KEY = "v8-settlement-policy-v1";

interface ConfigurationRevision {
  id: string;
  version: number | string;
  effective_snapshot: Record<string, unknown>;
  impact: Record<string, unknown>;
  reason: string;
  created_by: string | null;
}

export async function ensureSystemSettlementPolicyRevision(
  client: PoolClient,
  actorUserId: string,
): Promise<{ revisionId: string; created: boolean }> {
  await client.query("select pg_advisory_xact_lock(hashtext($1))", [
    "crm-configuration:school",
  ]);
  const existingSystemResult = await client.query<ConfigurationRevision>(
    `select id, version, effective_snapshot, impact, reason, created_by
     from app.crm_configuration_revisions
     where branch_id is null
       and impact ->> 'systemMigration' = $1
     order by version desc limit 1`,
    [SYSTEM_SETTLEMENT_POLICY_KEY],
  );
  const existingSystem = existingSystemResult.rows[0];
  if (existingSystem) {
    if (!isSystemPolicyRevision(existingSystem)) {
      throw new Error("SYSTEM_SETTLEMENT_POLICY_REVISION_INVALID");
    }
    return { revisionId: existingSystem.id, created: false };
  }
  const currentResult = await client.query<ConfigurationRevision>(
    `select id, version, effective_snapshot, impact, reason, created_by
     from app.crm_configuration_revisions
     where branch_id is null order by version desc limit 1`,
  );
  const current = currentResult.rows[0];
  const baseline = buildCrmConfigurationBaseline(
    current ? [] : await loadClientFieldDefinitions(client),
  );
  const previous = current
    ? normalizeCrmConfigurationSnapshot(current.effective_snapshot)
    : baseline;
  const snapshot: ConfigSnapshot = {
    ...previous,
    lessonSettlementTypes: baseline.lessonSettlementTypes,
    teacherCompensationRules: baseline.teacherCompensationRules,
  };
  const nextVersion = Number(current?.version ?? 0) + 1;
  const impact = {
    valid: true,
    blockingIssues: [],
    warnings: [],
    changes: {
      fieldsCreated: 0,
      fieldsUpdated: 0,
      fieldsArchived: 0,
      settingsChanged: 0,
      settlementTypesChanged: snapshot.lessonSettlementTypes.length,
      compensationRulesChanged: snapshot.teacherCompensationRules.length,
    },
    affectedScreens: ["lesson-editor", "schedule-plan"],
    systemMigration: SYSTEM_SETTLEMENT_POLICY_KEY,
  };
  const inserted = await client.query<{ id: string }>(
    `insert into app.crm_configuration_revisions (
       branch_id, version, patch, effective_snapshot, impact, reason,
       rollback_from_version, created_by
     ) values (null, $1, $2::jsonb, $2::jsonb, $3::jsonb, $4, null, $5)
     returning id`,
    [
      nextVersion,
      JSON.stringify(snapshot),
      JSON.stringify(impact),
      SYSTEM_SETTLEMENT_POLICY_REASON,
      actorUserId,
    ],
  );
  return { revisionId: inserted.rows[0]!.id, created: true };
}

function isSystemPolicyRevision(revision: ConfigurationRevision): boolean {
  if (revision.impact?.systemMigration !== SYSTEM_SETTLEMENT_POLICY_KEY) {
    return false;
  }
  try {
    const snapshot = normalizeCrmConfigurationSnapshot(
      revision.effective_snapshot,
    );
    const penalty = snapshot.lessonSettlementTypes.find(
      (item) => item.stableKey === "penalty_lesson",
    );
    const durationModes = new Set(snapshot.lessonSettlementTypes.flatMap(
      (item) => [item.clientDurationMode, item.teacherDurationMode],
    ));
    return penalty?.active === false &&
      ["zero", "full", "manual"].every((mode) => durationModes.has(
        mode as "zero" | "full" | "manual",
      ));
  } catch {
    return false;
  }
}

async function loadClientFieldDefinitions(
  client: PoolClient,
): Promise<ClientFieldDefinitionRow[]> {
  const result = await client.query<ClientFieldDefinitionRow>(
    `select id, field_key, label, value_type, is_required,
       is_active, is_system, category_key, category_label, sort_order, width,
       placements, options, visible_on_lead, visible_on_student
     from app.client_custom_field_definitions
     where is_active = true and deleted_at is null
     order by sort_order, label`,
  );
  return result.rows;
}
