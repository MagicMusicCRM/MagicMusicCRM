// Pull the COMPLETE HolliHop dataset via the Open API to JSON files, so we can
// inspect/filter the full source of truth before loading it into the system.
// Non-destructive: reads only (Get* methods exclusively). Covers every read
// method documented in API 2.0 (https://hollipedia.t8s.ru/books/api/page/api-20).
// Failures per endpoint are recorded in hollihop-dump/_errors.json (KVA-231).
// Run from repo root:
//   node --env-file=server/.env server/scripts/dump-hollihop.mjs
import { mkdirSync, writeFileSync, readFileSync } from "node:fs";

const BASE = (process.env.HOLLIHOP_BASE_URL?.trim() || "https://sokol.t8s.ru/Api/V2/").replace(/\/+$/, "");
const KEY = process.env.HOLLIHOP_AUTH_KEY?.trim();
const TAKE = Number(process.env.HOLLIHOP_IMPORT_TAKE ?? "500");
const OUT = "hollihop-dump";
if (!KEY) { console.error("HOLLIHOP_AUTH_KEY missing"); process.exit(1); }
mkdirSync(OUT, { recursive: true });

const errors = [];

async function call(method, params = {}) {
  const url = new URL(method, BASE + "/");
  url.searchParams.set("authkey", KEY);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
  for (let attempt = 0; ; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(120000) });
      const text = await res.text();
      if (!res.ok) {
        const err = new Error(`HTTP ${res.status}`);
        err.status = res.status;
        err.body = text.slice(0, 500);
        // 4xx = метода нет / нет прав / неверные параметры — ретраи бессмысленны
        if (res.status >= 400 && res.status < 500) throw Object.assign(err, { final: true });
        throw err;
      }
      return JSON.parse(text);
    } catch (e) {
      if (e.final || attempt >= 3) throw e;
      await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
    }
  }
}

// Ответы API оборачивают массив в корневой ключ (Students, Leads, ...). Для
// новых методов ключ заранее не известен — берём ожидаемый, иначе первый
// массив в ответе.
function pickArray(data, expectedKey) {
  if (Array.isArray(data)) return { key: expectedKey, items: data };
  if (Array.isArray(data?.[expectedKey])) return { key: expectedKey, items: data[expectedKey] };
  for (const [k, v] of Object.entries(data ?? {})) {
    if (Array.isArray(v)) return { key: k, items: v };
  }
  return { key: expectedKey, items: null };
}

function recordError(method, e) {
  errors.push({ method, error: e.message, status: e.status ?? null, body: e.body ?? null });
  console.log(`  ${method}: ERROR ${e.message}`);
}

async function root(method, rootKey, params = {}) {
  const data = await call(method, params);
  const { key, items } = pickArray(data, rootKey);
  if (items === null) {
    // Ответ без массива (объект/пусто) — сохраняем как есть, чтобы не потерять.
    return { rows: [data], note: "non-array response" };
  }
  return { rows: items, note: key !== rootKey ? `root key: ${key}` : undefined };
}

async function paged(method, rootKey, params = {}) {
  const all = [];
  let prevFirst;
  for (let skip = 0; ; skip += TAKE) {
    const data = await call(method, { ...params, skip, take: TAKE });
    const { items } = pickArray(data, rootKey);
    if (items === null) {
      if (skip === 0) return { rows: [data], note: "non-array response" };
      break;
    }
    // Защита от зацикливания, если сервер игнорирует skip
    const first = items.length ? JSON.stringify(items[0]).slice(0, 200) : null;
    if (first !== null && first === prevFirst) break;
    prevFirst = first;
    all.push(...items);
    if (items.length < TAKE) break;
    await new Promise((r) => setTimeout(r, 120));
  }
  return { rows: all };
}

const DATE_FROM = process.env.HOLLIHOP_EDUNIT_FROM ?? "2023-01-01";
const DATE_TO = process.env.HOLLIHOP_EDUNIT_TO ?? "2028-01-01";

// Справочники и малые сущности — одним запросом.
const ROOT_JOBS = [
  ["GetLocations", "Locations"],
  ["GetOffices", "Offices"],
  ["GetLeadStatuses", "Statuses"],
  ["GetClientStatuses", "ClientStatuses"],
  ["GetEmployeeStatuses", "EmployeeStatuses"],
  ["GetTeachers", "Teachers"],
  ["GetDisciplines", "Disciplines"],
  ["GetLevels", "Levels"],
  ["GetLearningTypes", "LearningTypes"],
  ["GetPrices", "Prices"],
  ["GetDiscounts", "Discounts"],
  ["GetSurcharges", "Surcharges"],
  ["GetOfflineTestTypes", "OfflineTestTypes"],
  ["GetEdMaterials", "EdMaterials"],
];

// Потенциально большие коллекции — с пагинацией skip/take.
const PAGED_JOBS = [
  ["GetStudents", "Students"],
  ["GetLeads", "Leads"],
  ["GetCompanies", "Companies"],
  ["GetEdUnitStudents", "EdUnitStudents"],
  ["GetEdUnitLeads", "EdUnitLeads"],
  ["GetPayments", "Payments"],
  ["GetStudyRequests", "StudyRequests"],
  ["GetHistoryModifyLeadStatus", "Actions"],
  ["GetLessonPlans", "LessonPlans"],
  ["GetEntranceTests", "EntranceTests"],
  ["GetPersonalTestResults", "PersonalTestResults"],
  ["GetEdUnitTestResults", "EdUnitTestResults"],
  ["GetOnlineTestResults", "OnlineTestResults"],
  ["GetEdUnitStudentReports", "EdUnitStudentReports"],
  ["GetSupplies", "Supplies"],
];
// GetTasks/GetComments/GetStudentLogs/GetLeadLogs/GetStaff удалены: таких
// методов в API 2.0 нет — задачи/комментарии приходят ручным Excel-экспортом
// из UI (import-hollihop-exports.ts).

const summary = {};
function save(name, { rows, note }) {
  writeFileSync(`${OUT}/${name}.json`, JSON.stringify(rows));
  summary[name] = rows.length;
  console.log(`  ${name}: ${rows.length}${note ? ` (${note})` : ""}`);
}

console.log("== root entities ==");
for (const [m, k] of ROOT_JOBS) {
  try { save(k, await root(m, k)); } catch (e) { recordError(m, e); }
}

// EdUnits with full schedule (ScheduleItems carry ClassroomId/Teacher/time).
// dateFrom=2023-01-01: данные школы начинаются с 2023-03, прежний 2024-01-01
// отрезал год фактических занятий (KVA-231).
console.log(`== edunits (schedule, ${DATE_FROM}..${DATE_TO}, queryDays) ==`);
try {
  save("EdUnits", await root("GetEdUnits", "EdUnits", {
    dateFrom: DATE_FROM,
    dateTo: DATE_TO,
    queryDays: "true",
  }));
} catch (e) { recordError("GetEdUnits", e); }

console.log("== paged entities ==");
for (const [m, k] of PAGED_JOBS) {
  try { save(k, await paged(m, k)); } catch (e) { recordError(m, e); }
}

// ---- методы с обязательными параметрами (расшифровка ошибок в KVA-231) ----
console.log("== special entities ==");

// GetBalances: «Требуется поле BalanceDate» — снимок остатков на дату дампа.
try {
  const today = new Date().toISOString().slice(0, 10);
  const res = await paged("GetBalances", "Balances", { balanceDate: today });
  res.note = `balanceDate=${today}`;
  save("Balances", res);
} catch (e) { recordError("GetBalances", e); }

// GetAnnouncements: «Обязательное поле targets».
{
  const all = [];
  for (const target of ["Employees", "Students", "Companies"]) {
    try {
      const { rows } = await root("GetAnnouncements", "Announcements", { targets: target });
      for (const r of rows) all.push({ Target: target, ...r });
    } catch (e) { recordError(`GetAnnouncements(targets=${target})`, e); }
  }
  save("Announcements", { rows: all, note: "targets: Employees/Students/Companies" });
}

// GetEmployees: HTTP 500 из-за отсутствующей папки фото на сервере HolliHop —
// пробуем попросить ответ без фото.
try {
  save("Employees", await paged("GetEmployees", "Employees", { queryPhoto: "false" }));
} catch (e) { recordError("GetEmployees(queryPhoto=false)", e); }

// GetIncomesAndOutgoes / GetClientFiles: clientId обязателен — обходим всех
// клиентов из свежего Students.json батчами по 5 (≈12 req/s < лимита 600/30с).
const students = JSON.parse(readFileSync(`${OUT}/Students.json`, "utf-8"));
const clientIds = [...new Set(students.map((s) => s.ClientId).filter((x) => Number.isInteger(x)))];
// Массивы бывают вложены (GetIncomesAndOutgoes: Study.Items/OtherPayments.Items)
const hasData = (obj) => Object.values(obj ?? {}).some((v) =>
  Array.isArray(v) ? v.length > 0 : v && typeof v === "object" && hasData(v));
async function perClient(method, fileName) {
  const collected = [];
  let done = 0, errCount = 0;
  const BATCH = 5;
  for (let i = 0; i < clientIds.length; i += BATCH) {
    const batch = clientIds.slice(i, i + BATCH);
    const results = await Promise.all(batch.map(async (cid) => {
      try {
        const data = await call(method, { clientId: cid });
        return hasData(data) ? { ClientId: cid, ...data } : null;
      } catch (e) {
        if (++errCount <= 3) recordError(`${method}(clientId=${cid})`, e);
        return null;
      }
    }));
    collected.push(...results.filter(Boolean));
    done += batch.length;
    if (done % 250 < BATCH) console.log(`  ${method}: ${done}/${clientIds.length}...`);
    await new Promise((r) => setTimeout(r, 150));
  }
  if (errCount > 3) console.log(`  ${method}: ещё ${errCount - 3} ошибок не записано`);
  save(fileName, { rows: collected, note: `per-client scan, ${clientIds.length} clients, errors: ${errCount}` });
}
await perClient("GetIncomesAndOutgoes", "IncomesAndOutgoes");
await perClient("GetClientFiles", "ClientFiles");

writeFileSync(`${OUT}/_summary.json`, JSON.stringify(summary, null, 2));
writeFileSync(`${OUT}/_errors.json`, JSON.stringify(errors, null, 2));
console.log("== done ==");
console.log(JSON.stringify(summary, null, 2));
if (errors.length) {
  console.log(`ERRORS (${errors.length}) -> ${OUT}/_errors.json`);
  for (const e of errors) console.log(`  ${e.method}: ${e.error}`);
}
