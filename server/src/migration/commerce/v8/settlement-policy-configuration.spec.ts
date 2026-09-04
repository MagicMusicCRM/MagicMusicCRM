import type { PoolClient, QueryResult } from "pg";
import { buildCrmConfigurationBaseline } from "../../../crm/crm-configuration-baseline";
import {
  ensureSystemSettlementPolicyRevision,
  SYSTEM_SETTLEMENT_POLICY_REASON,
} from "./settlement-policy-configuration";

const ACTOR_ID = "11111111-1111-4111-8111-111111111111";
const REVISION_ID = "22222222-2222-4222-8222-222222222222";

function clientWithRevisionState() {
  let latest: Record<string, unknown> | null = null;
  const query = jest.fn(async (text: string, params?: unknown[]) => {
    if (text.includes("pg_advisory_xact_lock")) return { rows: [] };
    if (text.includes("from app.crm_configuration_revisions")) {
      return { rows: latest ? [latest] : [] };
    }
    if (text.includes("from app.client_custom_field_definitions")) {
      return { rows: [] };
    }
    if (text.includes("insert into app.crm_configuration_revisions")) {
      const snapshot = JSON.parse(String(params?.[1]));
      const impact = JSON.parse(String(params?.[2]));
      latest = {
        id: REVISION_ID,
        version: 1,
        effective_snapshot: snapshot,
        impact,
        reason: params?.[3],
        created_by: params?.[4],
      };
      return { rows: [{ id: REVISION_ID }] };
    }
    throw new Error(`Unexpected SQL: ${text}`);
  });
  return {
    client: { query } as unknown as PoolClient,
    query,
    latest: () => latest,
  };
}

describe("ensureSystemSettlementPolicyRevision", () => {
  it("reuses a valid system revision below a later ordinary revision", async () => {
    const snapshot = buildCrmConfigurationBaseline([]);
    const system = {
      id: REVISION_ID,
      version: 1,
      effective_snapshot: snapshot,
      impact: { systemMigration: "v8-settlement-policy-v1" },
      reason: SYSTEM_SETTLEMENT_POLICY_REASON,
      created_by: ACTOR_ID,
    };
    const latest = {
      ...system,
      id: "33333333-3333-4333-8333-333333333333",
      version: 2,
      impact: {},
      reason: "ordinary.configuration.change",
    };
    const query = jest.fn(async (text: string) => {
      if (text.includes("pg_advisory_xact_lock")) return { rows: [] };
      if (text.includes("impact ->> 'systemMigration'")) {
        return { rows: [system] };
      }
      if (text.includes("from app.crm_configuration_revisions")) {
        return { rows: [latest] };
      }
      throw new Error(`Unexpected SQL: ${text}`);
    });

    await expect(ensureSystemSettlementPolicyRevision(
      { query } as unknown as PoolClient,
      ACTOR_ID,
    )).resolves.toEqual({ revisionId: REVISION_ID, created: false });
    expect(query.mock.calls.some(([sql]) =>
      String(sql).includes("insert into app.crm_configuration_revisions"),
    )).toBe(false);
  });

  it("publishes one system-owned complete policy and is idempotent", async () => {
    const fixture = clientWithRevisionState();

    const first = await ensureSystemSettlementPolicyRevision(
      fixture.client,
      ACTOR_ID,
    );
    const second = await ensureSystemSettlementPolicyRevision(
      fixture.client,
      ACTOR_ID,
    );

    expect(first).toEqual({ revisionId: REVISION_ID, created: true });
    expect(second).toEqual({ revisionId: REVISION_ID, created: false });
    expect(fixture.query.mock.calls.filter(([sql]) =>
      String(sql).includes("insert into app.crm_configuration_revisions"),
    )).toHaveLength(1);
    const stored = fixture.latest()!;
    expect(stored.reason).toBe(SYSTEM_SETTLEMENT_POLICY_REASON);
    expect(stored.created_by).toBe(ACTOR_ID);
    const snapshot = stored.effective_snapshot as ReturnType<
      typeof buildCrmConfigurationBaseline
    >;
    expect(snapshot.lessonSettlementTypes.find((item) =>
      item.stableKey === "penalty_lesson",
    )?.active).toBe(false);
    expect(new Set(snapshot.lessonSettlementTypes.flatMap((item) => [
      item.clientDurationMode,
      item.teacherDurationMode,
    ]))).toEqual(new Set(["zero", "full", "manual"]));
  });
});
