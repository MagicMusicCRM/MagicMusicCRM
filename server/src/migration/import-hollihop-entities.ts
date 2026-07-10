// server/src/migration/import-hollihop-entities.ts
// KVA-233: standalone importer for the HolliHop entities the main importer
// does not cover:
//   1. StudyRequests.json      -> app.lead_applications («Заявки» в карточке)
//   2. EdUnitLeads.json        -> app.lessons (пробные уроки лидов, галка «Посетил»)
//   3. Prices.json             -> app.subscription_packages (каталог абонементов)
//   4. manual-exports/communications.json -> app.entity_comments / app.lead_comments
//      (история «История и задачи»; матчинг по «ИД ученика» и имени лида)
//
// FK-safe: пишет только для уже импортированных лидов/учеников/групп.
// Idempotent: deterministicUuid + on conflict do nothing.
//
// Usage (dry run – default):
//   HOLLIHOP_DUMP_DIR=hollihop-dump node dist/migration/import-hollihop-entities.js
// Usage (apply):
//   HOLLIHOP_DUMP_DIR=hollihop-dump HOLLIHOP_ENTITIES_IMPORT_MODE=apply node dist/migration/import-hollihop-entities.js

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Pool, PoolClient } from "pg";
import { deterministicUuid } from "./v3-import-utils";
import { parseRuDate } from "./hollihop-export-mappers";
import {
  hhDateTimeToIso,
  studyRequestFromRow,
  edUnitLeadFromRow,
  priceFromRow,
  communicationFromRow,
} from "./hollihop-entities-mappers";

type ImportMode = "dry_run" | "apply";
type JsonRow = Record<string, unknown>;

const MODE: ImportMode =
  (process.env.HOLLIHOP_ENTITIES_IMPORT_MODE?.trim().toLowerCase() as ImportMode | undefined) === "apply"
    ? "apply"
    : "dry_run";
const DUMP_DIR = process.env.HOLLIHOP_DUMP_DIR?.trim() || "hollihop-dump";
const CONNECTION_STRING = process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;
const TODAY_ISO = new Date().toISOString().slice(0, 10);

const ALLOWED_TABLES = [
  "app.lead_applications",
  "app.lessons",
  "app.subscription_packages",
  "app.entity_comments",
  "app.lead_comments",
];

function readJson(name: string): JsonRow[] {
  const filePath = join(DUMP_DIR, name);
  if (!existsSync(filePath)) return [];
  const parsed = JSON.parse(readFileSync(filePath, "utf8")) as unknown;
  return Array.isArray(parsed) ? (parsed as JsonRow[]) : [];
}

async function planInsert(
  client: PoolClient,
  table: string,
  data: JsonRow,
): Promise<boolean> {
  if (!ALLOWED_TABLES.includes(table)) throw new Error(`unexpected table: ${table}`);
  if (MODE !== "apply") return false;
  const entries = Object.entries(data).filter(([, v]) => v !== undefined);
  const columns = entries.map(([k]) => k);
  const values = entries.map(([, v]) =>
    v !== null && typeof v === "object" ? JSON.stringify(v) : v,
  );
  const placeholders = values.map((_, i) => `$${i + 1}`);
  const result = await client.query(
    `insert into ${table} (${columns.join(", ")}) values (${placeholders.join(", ")})
     on conflict (id) do nothing`,
    values,
  );
  return (result.rowCount ?? 0) > 0;
}

async function loadIdSet(client: PoolClient, sql: string): Promise<Set<string>> {
  const r = await client.query<{ id: string }>(sql);
  return new Set(r.rows.map((row) => row.id));
}

async function main() {
  if (!CONNECTION_STRING) throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
  if (!existsSync(DUMP_DIR)) throw new Error(`HOLLIHOP_DUMP_DIR does not exist: ${DUMP_DIR}`);

  const pool = new Pool({ connectionString: CONNECTION_STRING, max: 2 });
  const client = await pool.connect();
  try {
    if (MODE === "apply") await client.query("begin");
    try {
      const leadSet = await loadIdSet(client, "select id from app.leads where deleted_at is null");
      const studentSet = await loadIdSet(client, "select id from app.students where deleted_at is null");
      const groupSet = await loadIdSet(client, "select id from app.groups where deleted_at is null");
      const branchSet = await loadIdSet(client, "select id from app.branches where deleted_at is null");

      // ---- 1. StudyRequests -> lead_applications --------------------------
      const applications = { total: 0, matchedLead: 0, written: 0, skippedNoLead: 0, skippedLeadMissing: 0, skippedBadDate: 0 };
      for (const row of readJson("StudyRequests.json")) {
        const mapped = studyRequestFromRow(row);
        if (!mapped) continue;
        applications.total++;
        if (!mapped.leadIdRaw) { applications.skippedNoLead++; continue; }
        const leadId = deterministicUuid("hollihop-lead", mapped.leadIdRaw);
        if (!leadSet.has(leadId)) { applications.skippedLeadMissing++; continue; }
        if (!mapped.appliedAt) { applications.skippedBadDate++; continue; }
        applications.matchedLead++;
        const written = await planInsert(client, "app.lead_applications", {
          id: deterministicUuid("hollihop-study-request", mapped.idRaw),
          lead_id: leadId,
          applied_at: mapped.appliedAt,
          channel: mapped.channel,
          office: mapped.office,
          discipline: mapped.discipline,
          status: mapped.status,
          utm: mapped.utm,
        });
        if (written) applications.written++;
      }

      // ---- 2. EdUnitLeads -> lessons (пробные лидов) -----------------------
      const trials = { total: 0, matchedLead: 0, updatedExisting: 0, inserted: 0, skippedLeadMissing: 0 };
      for (const row of readJson("EdUnitLeads.json")) {
        const mapped = edUnitLeadFromRow(row);
        if (!mapped) continue;
        trials.total++;
        const leadId = deterministicUuid("hollihop-lead", mapped.leadIdRaw);
        if (!leadSet.has(leadId)) { trials.skippedLeadMissing++; continue; }
        trials.matchedLead++;
        const groupId = deterministicUuid("hollihop-edunit", mapped.edUnitIdRaw);
        const status = mapped.visited ? "completed" : mapped.date < TODAY_ISO ? "missed" : "scheduled";
        if (MODE === "apply") {
          // Основной импортер уже материализовал занятие пробного юнита —
          // тогда достаточно проставить lead_id/статус на существующей строке.
          const updated = await client.query(
            `update app.lessons
               set lead_id = $1, is_trial = true, status = $2, updated_at = now()
             where group_id = $3
               and scheduled_at >= $4::date and scheduled_at < ($4::date + interval '1 day')
               and deleted_at is null`,
            [leadId, status, groupId, mapped.date],
          );
          if ((updated.rowCount ?? 0) > 0) { trials.updatedExisting++; continue; }
          const written = await planInsert(client, "app.lessons", {
            id: deterministicUuid("hollihop-edunitlead", `${mapped.edUnitIdRaw}:${mapped.leadIdRaw}:${mapped.date}`),
            lead_id: leadId,
            group_id: groupSet.has(groupId) ? groupId : null,
            branch_id: mapped.officeIdRaw && branchSet.has(deterministicUuid("hollihop-office", mapped.officeIdRaw))
              ? deterministicUuid("hollihop-office", mapped.officeIdRaw)
              : null,
            scheduled_at: mapped.scheduledAt,
            duration_minutes: mapped.durationMinutes,
            status,
            is_trial: true,
            notes: ["Пробный урок (HolliHop)", mapped.name, mapped.discipline].filter(Boolean).join(" | "),
          });
          if (written) trials.inserted++;
        }
      }

      // ---- 3. Prices -> subscription_packages ------------------------------
      const packages = { total: 0, written: 0, skippedShape: 0 };
      const priceRows = readJson("Prices.json");
      for (let i = 0; i < priceRows.length; i++) {
        const mapped = priceFromRow(priceRows[i], i);
        if (!mapped) { packages.skippedShape++; continue; }
        packages.total++;
        const branchId = mapped.soleOfficeIdRaw
          ? deterministicUuid("hollihop-office", mapped.soleOfficeIdRaw)
          : null;
        const written = await planInsert(client, "app.subscription_packages", {
          id: deterministicUuid("hollihop-price", mapped.idRaw),
          name: mapped.name,
          branch_id: branchId && branchSet.has(branchId) ? branchId : null,
          lessons_total: mapped.hours,
          price: mapped.price,
          is_active: true,
          sort_order: mapped.sortOrder,
        });
        if (written) packages.written++;
      }

      // ---- 4. communications.json -> timeline comments ---------------------
      const comms = { total: 0, matchedStudent: 0, matchedLeadByName: 0, written: 0, skippedTaskDuplicate: 0, skippedUnmatched: 0, skippedBadDate: 0 };
      const commRows = readJson(join("manual-exports", "communications.json"));
      if (commRows.length) {
        // «ИД ученика» бывает и Id, и ClientId — готовим обе интерпретации.
        const clientToId = new Map<string, string>();
        for (const s of readJson("Students.json")) {
          const id = String(s.Id ?? "").trim();
          const clientId = String(s.ClientId ?? "").trim();
          if (id && clientId) clientToId.set(clientId, id);
        }
        const resolveStudent = (raw: string): string | null => {
          if (!raw) return null;
          const direct = deterministicUuid("hollihop-student", raw);
          if (studentSet.has(direct)) return direct;
          const viaClient = clientToId.get(raw);
          if (viaClient) {
            const mappedId = deterministicUuid("hollihop-student", viaClient);
            if (studentSet.has(mappedId)) return mappedId;
          }
          return null;
        };
        // Имя лида → uuid (только уникальные ФИО из ручного экспорта лидов).
        const nameCounts = new Map<string, number>();
        const nameToLead = new Map<string, string>();
        for (const l of readJson(join("manual-exports", "leads.json"))) {
          const name = String(l["ФИО"] ?? "").trim().toLowerCase();
          const idRaw = String(l["ID"] ?? "").trim();
          if (!name || !idRaw) continue;
          nameCounts.set(name, (nameCounts.get(name) ?? 0) + 1);
          nameToLead.set(name, deterministicUuid("hollihop-lead", idRaw));
        }
        // Задачи уже импортированы отдельно — их дубли в ленте коммуникаций пропускаем.
        const taskBodies = new Set(
          readJson(join("manual-exports", "tasks.json"))
            .map((t) => String(t["Описание"] ?? "").trim())
            .filter(Boolean),
        );

        for (const row of commRows) {
          const mapped = communicationFromRow(row);
          if (!mapped) continue;
          comms.total++;
          if (taskBodies.has(mapped.rawBody)) { comms.skippedTaskDuplicate++; continue; }
          // Дата из xlsx бывает и «11.08.2027», и ISO из datetime-ячейки.
          const createdAt = parseRuDate(mapped.dateRaw) ?? hhDateTimeToIso(mapped.dateRaw);
          if (!createdAt) { comms.skippedBadDate++; continue; }
          const studentId = resolveStudent(mapped.studentIdRaw);
          if (studentId) {
            comms.matchedStudent++;
            const written = await planInsert(client, "app.entity_comments", {
              id: deterministicUuid("hollihop-communication", `s:${studentId}:${createdAt}:${mapped.rawBody}`),
              entity_type: "student",
              entity_id: studentId,
              author_id: null,
              kind: "admin_comment",
              body: mapped.body,
              created_at: createdAt,
            });
            if (written) comms.written++;
            continue;
          }
          const nameKey = mapped.name.toLowerCase();
          const leadId = nameCounts.get(nameKey) === 1 ? nameToLead.get(nameKey) : undefined;
          if (leadId && leadSet.has(leadId)) {
            comms.matchedLeadByName++;
            const written = await planInsert(client, "app.lead_comments", {
              id: deterministicUuid("hollihop-communication", `l:${leadId}:${createdAt}:${mapped.rawBody}`),
              lead_id: leadId,
              author_id: null,
              body: mapped.body,
              created_at: createdAt,
            });
            if (written) comms.written++;
            continue;
          }
          comms.skippedUnmatched++;
        }
      }

      if (MODE === "apply") await client.query("commit");
      process.stdout.write(
        JSON.stringify({ mode: MODE, applications, trials, packages, communications: comms }, null, 2) + "\n",
      );
    } catch (err) {
      if (MODE === "apply") await client.query("rollback");
      throw err;
    }
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
