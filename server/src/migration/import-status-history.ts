/**
 * Standalone, SAFE importer for HolliHop lead status-transition history.
 *
 * Writes ONLY `app.lead_status_history` — it never touches app.leads /
 * app.lead_statuses / any other entity, so it cannot clobber the already-applied
 * 0032 funnel cleanup, phone normalization, or any local edit. (Re-running the
 * full hollihop-import would overwrite lead.status_id from HolliHop and undo
 * those — hence this focused script.)
 *
 * Mapping mirrors importLeadStatusHistory in hollihop-import.ts:
 *   LeadId   -> lead_id = deterministicUuid("hollihop-lead", LeadId), kept only
 *               if that lead actually exists in app.leads (FK-safe).
 *   AfterName-> new_status_id by case-insensitive name match to app.lead_statuses
 *               (statusById there is name-reconciled, so name match is equivalent).
 *   DateTime -> changed_at with Moscow (+03:00) offset.
 *   id       -> deterministicUuid("hollihop-lead-status-history",
 *               `${LeadId}:${AfterId}:${DateTime}`)  (idempotent upsert).
 *
 * Usage (from server/, after build):
 *   node dist/migration/import-status-history.js --dry-run
 *   node dist/migration/import-status-history.js --apply
 */
import { Client } from "pg";
import { deterministicUuid } from "./v3-import-utils";
import {
  appendMoscowOffset,
  historyEntryFromRow,
} from "./hollihop-history-mappers";

type JsonRow = Record<string, unknown>;

const BASE_URL = (
  process.env.HOLLIHOP_BASE_URL?.trim() || "https://sokol.t8s.ru/Api/V2/"
).replace(/\/?$/, "/");
const AUTH_KEY = process.env.HOLLIHOP_AUTH_KEY?.trim();
const CONNECTION_STRING =
  process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;
const TAKE = Number(process.env.HOLLIHOP_IMPORT_TAKE ?? "500");

const MODE: "dry_run" | "apply" = process.argv.includes("--apply")
  ? "apply"
  : "dry_run";

function isoUtc(withOffset: string | null | undefined): string | null {
  if (!withOffset) return null;
  const d = new Date(withOffset);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

async function fetchActions(): Promise<JsonRow[]> {
  if (!AUTH_KEY) throw new Error("HOLLIHOP_AUTH_KEY is required.");
  const all: JsonRow[] = [];
  let skip = 0;
  // Page until a short page (or empty) comes back.
  for (let guard = 0; guard < 1000; guard++) {
    const url = `${BASE_URL}GetHistoryModifyLeadStatus?authkey=${encodeURIComponent(
      AUTH_KEY,
    )}&skip=${skip}&take=${TAKE}`;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HolliHop HTTP ${res.status}`);
    const json = (await res.json()) as Record<string, unknown>;
    const rows = Array.isArray(json.Actions) ? (json.Actions as JsonRow[]) : [];
    all.push(...rows);
    if (rows.length < TAKE) break;
    skip += rows.length;
  }
  return all;
}

async function main() {
  if (!CONNECTION_STRING) {
    throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
  }
  console.log(`[status-history] mode=${MODE} base=${BASE_URL}`);
  const actions = await fetchActions();
  console.log(`[status-history] fetched ${actions.length} Actions rows`);

  const client = new Client({ connectionString: CONNECTION_STRING });
  await client.connect();
  try {
    // Existing leads: HolliHop LeadId -> app.leads.id is deterministic, so build
    // the set of existing ids + their branch_id for FK-safe inserts.
    const leadsRes = await client.query<{ id: string; branch_id: string | null }>(
      `select id, branch_id from app.leads`,
    );
    const leadIds = new Set(leadsRes.rows.map((r) => r.id));
    const branchByLead = new Map(
      leadsRes.rows.map((r) => [r.id, r.branch_id] as const),
    );
    const statusRes = await client.query<{ id: string; name: string }>(
      `select id, name from app.lead_statuses`,
    );
    const statusByName = new Map(
      statusRes.rows.map((r) => [r.name.trim().toLowerCase(), r.id] as const),
    );

    const counts = {
      total: actions.length,
      inserted: 0,
      duplicate: 0,
      skipNoLead: 0,
      skipBadRow: 0,
      skipBadDate: 0,
      statusUnresolved: 0,
    };

    for (const row of actions) {
      const entry = historyEntryFromRow(row);
      if (!entry) {
        counts.skipBadRow++;
        continue;
      }
      const leadId = deterministicUuid("hollihop-lead", entry.leadIdRaw);
      if (!leadIds.has(leadId)) {
        counts.skipNoLead++;
        continue;
      }
      const changedAt = isoUtc(appendMoscowOffset(entry.dateTimeRaw));
      if (!changedAt) {
        counts.skipBadDate++;
        continue;
      }
      const newStatusId = entry.afterName
        ? statusByName.get(entry.afterName.trim().toLowerCase()) ?? null
        : null;
      if (entry.afterName && !newStatusId) counts.statusUnresolved++;
      const externalId = `${entry.leadIdRaw}:${entry.afterIdRaw ?? ""}:${entry.dateTimeRaw}`;
      const id = deterministicUuid("hollihop-lead-status-history", externalId);

      if (MODE === "apply") {
        const ins = await client.query(
          `insert into app.lead_status_history
             (id, lead_id, old_status_id, new_status_id, old_owner_id,
              new_owner_id, changed_by, changed_at, reason_id, comment,
              branch_id, source_snapshot)
           values ($1,$2,null,$3,null,null,null,$4,null,null,$5,$6)
           on conflict (id) do nothing`,
          [
            id,
            leadId,
            newStatusId,
            changedAt,
            branchByLead.get(leadId) ?? null,
            entry.afterName,
          ],
        );
        if (ins.rowCount === 1) counts.inserted++;
        else counts.duplicate++;
      } else {
        counts.inserted++; // would-insert (dry-run can't tell new vs dup cheaply)
      }
    }

    console.log(`[status-history] ${MODE} result:`, JSON.stringify(counts, null, 2));
    if (MODE === "apply") {
      const tot = await client.query<{ c: string }>(
        `select count(*)::text as c from app.lead_status_history`,
      );
      console.log(`[status-history] app.lead_status_history total rows: ${tot.rows[0].c}`);
    }
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error("[status-history] FAILED:", e);
  process.exit(1);
});
