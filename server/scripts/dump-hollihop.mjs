// Pull the COMPLETE HolliHop dataset via the Open API to JSON files, so we can
// inspect/filter the full source of truth before loading it into the system.
// Non-destructive: reads only. Mirrors the importer's fetch list
// (server/src/migration/hollihop-import.ts). Run from repo root:
//   node --env-file=server/.env server/scripts/dump-hollihop.mjs
import { mkdirSync, writeFileSync } from "node:fs";

const BASE = (process.env.HOLLIHOP_BASE_URL?.trim() || "https://sokol.t8s.ru/Api/V2/").replace(/\/+$/, "");
const KEY = process.env.HOLLIHOP_AUTH_KEY?.trim();
const TAKE = Number(process.env.HOLLIHOP_IMPORT_TAKE ?? "500");
const OUT = "hollihop-dump";
if (!KEY) { console.error("HOLLIHOP_AUTH_KEY missing"); process.exit(1); }
mkdirSync(OUT, { recursive: true });

async function call(method, params = {}) {
  const url = new URL(method, BASE + "/");
  url.searchParams.set("authkey", KEY);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
  for (let attempt = 0; ; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(120000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.json();
    } catch (e) {
      if (attempt >= 3) throw e;
      await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
    }
  }
}

async function root(method, rootKey, params = {}) {
  const data = await call(method, params);
  const items = Array.isArray(data[rootKey]) ? data[rootKey] : [];
  return items;
}

async function paged(method, rootKey) {
  const all = [];
  for (let skip = 0; ; skip += TAKE) {
    const data = await call(method, { skip, take: TAKE });
    const items = Array.isArray(data[rootKey]) ? data[rootKey] : [];
    all.push(...items);
    if (items.length < TAKE) break;
    await new Promise((r) => setTimeout(r, 120));
  }
  return all;
}

const ROOT_JOBS = [
  ["GetLocations", "Locations"],
  ["GetOffices", "Offices"],
  ["GetLeadStatuses", "Statuses"],
  ["GetTeachers", "Teachers"],
  ["GetDisciplines", "Disciplines"],
];
const PAGED_JOBS = [
  ["GetStudents", "Students"],
  ["GetLeads", "Leads"],
  ["GetEdUnitStudents", "EdUnitStudents"],
  ["GetPayments", "Payments"],
  ["GetEmployees", "Employees"],
  ["GetStaff", "Staff"],
  ["GetTasks", "Tasks"],
  ["GetComments", "Comments"],
  ["GetStudentLogs", "StudentLogs"],
  ["GetLeadLogs", "LeadLogs"],
  ["GetHistoryModifyLeadStatus", "Actions"],
];

const summary = {};
function save(name, rows) {
  writeFileSync(`${OUT}/${name}.json`, JSON.stringify(rows));
  summary[name] = rows.length;
  console.log(`  ${name}: ${rows.length}`);
}

console.log("== root entities ==");
for (const [m, k] of ROOT_JOBS) {
  try { save(k, await root(m, k)); } catch (e) { console.log(`  ${k}: ERROR ${e.message}`); }
}

// EdUnits with full schedule (ScheduleItems carry ClassroomId/Teacher/time).
// Pull the full available window with queryDays so we also capture actual dated
// occurrences for lesson reconstruction / de-fragmentation analysis.
console.log("== edunits (schedule, 2024-2028, queryDays) ==");
try {
  const edunits = await root("GetEdUnits", "EdUnits", {
    dateFrom: process.env.HOLLIHOP_EDUNIT_FROM ?? "2024-01-01",
    dateTo: process.env.HOLLIHOP_EDUNIT_TO ?? "2028-01-01",
    queryDays: "true",
  });
  save("EdUnits", edunits);
} catch (e) { console.log(`  EdUnits: ERROR ${e.message}`); }

console.log("== paged entities ==");
for (const [m, k] of PAGED_JOBS) {
  try { save(k, await paged(m, k)); } catch (e) { console.log(`  ${k}: ERROR ${e.message}`); }
}

writeFileSync(`${OUT}/_summary.json`, JSON.stringify(summary, null, 2));
console.log("== done ==");
console.log(JSON.stringify(summary, null, 2));
