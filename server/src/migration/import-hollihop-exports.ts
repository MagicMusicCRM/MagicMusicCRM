// server/src/migration/import-hollihop-exports.ts
//
// Imports HolliHop manual exports into existing records: tasks + their history,
// student notes, lead comments.
//
// WHY FILES AND NOT THE API. Probed 2026-07-16 with the customer's key:
// GetTasks, GetComments, GetHistory — and every other method our old docs
// named — return 404. Tasks and comments are not in that API at all, so an
// export from the HolliHop UI is the only source. Full inventory:
// docs/import/hollihop_api_probe_2026-07-16.md
//
// Usage — dry run (default; reads the DB, writes nothing):
//   HOLLIHOP_EXPORTS_DIR=/path/to/exports npm run hollihop:import-exports
// Usage — apply:
//   HOLLIHOP_EXPORTS_DIR=/path/to/exports HOLLIHOP_EXPORT_IMPORT_MODE=apply \
//     npm run hollihop:import-exports
//
// Expected files in HOLLIHOP_EXPORTS_DIR (any that are absent are skipped).
// Each may be `.xlsx` — as HolliHop exports it — or `.json`; not both.
// Переименуйте выгрузку в это имя, содержимое не трогайте:
//   tasks        — Клиент, Описание, Дата выполнения, Ответственный, телефон
//   task-history — Клиент/телефон, Дата изменения, Поле, Было, Стало, Автор
//   students     — Фамилия, Имя, Описание, телефон
//   leads        — ФИО, Комментарий, Пользовательские поля, телефон

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Pool, PoolClient } from "pg";
import { normalizePhoneRu } from "../crm/phone.util";
import { deterministicUuid } from "./import-id";
import { parseStaffName } from "./staff-name";
import { readXlsxRows } from "./xlsx-reader";
import {
  historyFieldName,
  leadCommentFromRow,
  parseRuDate,
  studentNoteFromRow,
  taskFromRow,
  taskHistoryFromRow,
  taskStatusFromRow,
  taskTitle,
} from "./hollihop-export-mappers";

type ImportMode = "dry_run" | "apply";
/** Импортёру нужен только query — это и позволяет прогнать его на фейке. */
type QueryClient = Pick<PoolClient, "query">;
type JsonRow = Record<string, unknown>;

interface SectionReport {
  total: number;
  matchedById: number;
  matchedByPhone: number;
  unmatchedNoPhone: number;
  unmatchedNoRecord: number;
  written: number;
  skippedDuplicate: number;
}

const emptySection = (): SectionReport => ({
  total: 0,
  matchedById: 0,
  matchedByPhone: 0,
  unmatchedNoPhone: 0,
  unmatchedNoRecord: 0,
  written: 0,
  skippedDuplicate: 0,
});

const MODE: ImportMode =
  process.env.HOLLIHOP_EXPORT_IMPORT_MODE?.trim().toLowerCase() === "apply"
    ? "apply"
    : "dry_run";
const EXPORTS_DIR = process.env.HOLLIHOP_EXPORTS_DIR?.trim();
const CONNECTION_STRING =
  process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;

// Guardrail: this script builds SQL from a table name, so the name may only
// ever be one of these. Nothing here comes from the export files.
const ALLOWED_TABLES = ["app.tasks", "app.task_history", "app.entity_comments"];

/**
 * Раздел выгрузки: `<base>.xlsx` либо `<base>.json`.
 *
 * ⚠️ `.xlsx` — это то, что реально отдаёт HolliHop; `.json` остаётся, потому что
 * на нём стоят тесты и им же удобно скармливать правленый кусок. Раньше был
 * только JSON, а значит между файлом заказчика и базой стоял ручной шаг
 * конвертации — перед 12 744 строками его рано или поздно сделают неправильно и
 * никто не заметит.
 *
 * Если лежат оба — падаем. «Который из них свежий» — ровно тот вопрос, на
 * который никто не должен отвечать угадыванием.
 */
export function readArrayFile(dir: string, base: string, rootKey: string): JsonRow[] {
  const xlsxPath = join(dir, `${base}.xlsx`);
  const jsonPath = join(dir, `${base}.json`);
  const hasXlsx = existsSync(xlsxPath);
  const hasJson = existsSync(jsonPath);

  if (hasXlsx && hasJson) {
    throw new Error(
      `${base}: лежат и .xlsx, и .json — непонятно, который свежий. Оставьте один.`,
    );
  }
  if (hasXlsx) return readXlsxRows(xlsxPath);
  if (!hasJson) return [];

  const parsed = JSON.parse(readFileSync(jsonPath, "utf8")) as unknown;
  if (Array.isArray(parsed)) return parsed as JsonRow[];
  if (parsed && typeof parsed === "object") {
    const value = (parsed as JsonRow)[rootKey];
    if (Array.isArray(value)) return value as JsonRow[];
  }
  return [];
}

async function upsert(
  mode: ImportMode,
  client: QueryClient,
  table: string,
  data: JsonRow,
): Promise<boolean> {
  if (!ALLOWED_TABLES.includes(table)) {
    throw new Error(`unexpected table: ${table}`);
  }
  if (mode !== "apply") return false;
  const entries = Object.entries(data).filter(([, v]) => v !== undefined);
  const columns = entries.map(([k]) => k);
  const values = entries.map(([, v]) =>
    v !== null && typeof v === "object" && !(v instanceof Date)
      ? JSON.stringify(v)
      : v,
  );
  const placeholders = values.map((_, i) => `$${i + 1}`);
  const result = await client.query(
    `insert into ${table} (${columns.join(", ")})
     values (${placeholders.join(", ")})
     on conflict (id) do nothing`,
    values,
  );
  return (result.rowCount ?? 0) > 0;
}

/**
 * Resolves an export row onto an existing student/lead.
 *
 * Prefers the HolliHop id when the export carries one — the old import matched
 * on phone alone, which silently dropped every row whose phone did not
 * normalise or did not match, and that is the known cause of its incomplete
 * coverage. Phone stays as the fallback, since older exports have no id column.
 */
class Matcher {
  private readonly studentByExternal = new Map<string, string | null>();
  private readonly leadByExternal = new Map<string, string | null>();
  private readonly studentByPhone = new Map<string, string | null>();
  private readonly leadByPhone = new Map<string, string | null>();
  private readonly userByName = new Map<string, string | null>();

  constructor(private readonly client: QueryClient) {}

  private async cached(
    cache: Map<string, string | null>,
    key: string,
    load: () => Promise<string | null>,
  ): Promise<string | null> {
    if (cache.has(key)) return cache.get(key) ?? null;
    const value = await load();
    cache.set(key, value);
    return value;
  }

  /**
   * The external id needs no lookup column: the original API import derived the
   * PRIMARY KEY from it — `deterministicUuid("hollihop-student", externalId)`
   * (recovered from the retired hollihop-import.ts). Reconstructing that id and
   * probing for the row is an exact match, and it is why this beats the phone.
   */
  async studentByExternalId(externalId: string): Promise<string | null> {
    return this.cached(this.studentByExternal, externalId, async () => {
      const candidate = deterministicUuid("hollihop-student", externalId);
      const r = await this.client.query<{ id: string }>(
        `select id from app.students where id = $1 and deleted_at is null limit 1`,
        [candidate],
      );
      return r.rows[0]?.id ?? null;
    });
  }

  async leadByExternalId(externalId: string): Promise<string | null> {
    return this.cached(this.leadByExternal, externalId, async () => {
      const candidate = deterministicUuid("hollihop-lead", externalId);
      const r = await this.client.query<{ id: string }>(
        `select id from app.leads where id = $1 and deleted_at is null limit 1`,
        [candidate],
      );
      return r.rows[0]?.id ?? null;
    });
  }

  async studentByPhoneCanonical(canonical: string): Promise<string | null> {
    return this.cached(this.studentByPhone, canonical, async () => {
      const r = await this.client.query<{ id: string }>(
        `select s.id from app.students s
         join app.profiles p on p.id = s.profile_id and p.deleted_at is null
         where p.phone_normalized = $1 and s.deleted_at is null
         limit 1`,
        [canonical],
      );
      return r.rows[0]?.id ?? null;
    });
  }

  async leadByPhoneCanonical(canonical: string): Promise<string | null> {
    return this.cached(this.leadByPhone, canonical, async () => {
      const r = await this.client.query<{ id: string }>(
        `select id from app.leads
         where phone_normalized = $1 and deleted_at is null
         limit 1`,
        [canonical],
      );
      return r.rows[0]?.id ?? null;
    });
  }

  /**
   * Пользователь по имени из выгрузки.
   *
   * Два прохода, и второй — не украшение. Выгрузка пишет сотрудника как
   * «Мазалова А. Ю.», а в базе он «Александра Мазалова»: по полному имени такое
   * не совпадает НИКОГДА. Ровно поэтому у задач пуст `created_by` — люди в базе
   * есть (12 менеджеров), а связать текст с ними было нечем.
   */
  async userIdByName(name: string | null): Promise<string | null> {
    if (!name) return null;
    const key = name.toLowerCase().trim();
    return this.cached(this.userByName, key, async () => {
      const exact = await this.client.query<{ id: string }>(
        `select u.id from app.users u
         join app.profiles p on p.user_id = u.id and p.deleted_at is null
         where u.deleted_at is null
           and (lower(concat_ws(' ', p.last_name, p.first_name)) = $1
                or lower(concat_ws(' ', p.first_name, p.last_name)) = $1
                or lower(u.full_name) = $1)
         limit 1`,
        [key],
      );
      if (exact.rows[0]) return exact.rows[0].id;

      const parsed = parseStaffName(name);
      if (!parsed) return null;

      // ⚠️ limit 2, а не 1, и связываем только при ЕДИНСТВЕННОМ совпадении.
      // Фамилия + первый инициал — не ключ: две однофамилицы с одной буквой
      // (в выгрузке есть «Назарова Н. Н.» и «Назарова(П) Н. Н.») склеились бы
      // молча, и чужие задачи уехали бы человеку в карточку с видом точного
      // попадания. Неоднозначное имя лучше показать в отчёте.
      const byInitials = await this.client.query<{ id: string }>(
        `select u.id from app.users u
         join app.profiles p on p.user_id = u.id and p.deleted_at is null
         where u.deleted_at is null
           and lower(btrim(p.last_name)) = $1
           and lower(left(btrim(p.first_name), 1)) = $2
         limit 2`,
        [parsed.lastName.toLowerCase(), parsed.initials[0].toLowerCase()],
      );
      return byInitials.rows.length === 1 ? byInitials.rows[0].id : null;
    });
  }
}

interface Resolved {
  entityType: "student" | "lead";
  entityId: string;
  by: "id" | "phone";
}

/**
 * Кого искать по внешнему id.
 *
 * ⚠️ Тип обязателен, и это не педантизм. Пространства id у учеников и лидов в
 * HolliHop **пересекаются**: в выгрузке заказчика 58 чисел существуют и как
 * `Student.Id`, и как `Lead.Id`. Прежний код пробовал один и тот же id сначала
 * в ученическом namespace, потом в лидовом, — и для этих 58 комментарий лида
 * уехал бы в карточку постороннего ученика, причём с видом точного совпадения
 * «by id».
 *
 * Файл знает, чей это id: `students.json` → student, `leads.json` → lead.
 * Угадывать здесь нечего, поэтому и не угадываем.
 */
type ExternalIdKind = "student" | "lead";

async function resolveEntity(
  matcher: Matcher,
  external: { id: string; kind: ExternalIdKind } | null,
  phoneRaw: string,
  report: SectionReport,
): Promise<Resolved | null> {
  if (external?.id) {
    const found =
      external.kind === "student"
        ? await matcher.studentByExternalId(external.id)
        : await matcher.leadByExternalId(external.id);
    if (found) {
      report.matchedById++;
      return { entityType: external.kind, entityId: found, by: "id" };
    }
  }
  const { canonical } = normalizePhoneRu(phoneRaw);
  if (!canonical) {
    report.unmatchedNoPhone++;
    return null;
  }
  const studentId = await matcher.studentByPhoneCanonical(canonical);
  if (studentId) {
    report.matchedByPhone++;
    return { entityType: "student", entityId: studentId, by: "phone" };
  }
  const leadId = await matcher.leadByPhoneCanonical(canonical);
  if (leadId) {
    report.matchedByPhone++;
    return { entityType: "lead", entityId: leadId, by: "phone" };
  }
  report.unmatchedNoRecord++;
  return null;
}

/** Key that identifies an export task row across re-exports. */
function taskKeyFor(externalId: string, canonical: string | null, task: { dueRaw: string; description: string }): string {
  // Canonical phone (not raw) so a re-export with different formatting yields
  // the same id and the re-run stays a no-op.
  const subject = externalId || canonical || "";
  return `export:task:${subject}:${task.dueRaw}:${task.description}`;
}

export interface ImportRun {
  reports: Record<string, SectionReport>;
  unmatchedResponsibles: string[];
}

/**
 * The import itself, over an already-connected client.
 *
 * Split out of main() so it can be driven end-to-end in tests against a fake
 * client: the matching order, the report counts and the idempotent ids are the
 * parts worth proving, and none of them need a real database to check.
 */
export async function runImport(options: {
  client: QueryClient;
  exportsDir: string;
  mode: ImportMode;
}): Promise<ImportRun> {
  const { client, exportsDir, mode } = options;

  const taskRows = readArrayFile(exportsDir, "tasks", "Tasks");
  const historyRows = readArrayFile(exportsDir, "task-history", "History");
  const studentRows = readArrayFile(exportsDir, "students", "Students");
  const leadRows = readArrayFile(exportsDir, "leads", "Leads");

  const reports: Record<string, SectionReport> = {
    tasks: emptySection(),
    taskHistory: emptySection(),
    studentNotes: emptySection(),
    leadComments: emptySection(),
  };
  const unmatchedResponsibles = new Set<string>();

  {
    const MODE = mode;
    const matcher = new Matcher(client);
    // Транзакцией и соединением владеет main(): здесь только импорт.

    // ---- Tasks -------------------------------------------------------------
    // taskId per export row, so the history pass below can attach to it.
    const taskIdByKey = new Map<string, string>();
    for (const row of taskRows) {
      const mapped = taskFromRow(row);
      if (!mapped) continue;
      const report = reports.tasks;
      report.total++;

      // Задача может висеть и на ученике, и на лиде, а id в её выгрузке нет
      // вовсе — значит, только телефон. Ставить сюда `kind` наугад нельзя:
      // ошибка в типе увела бы задачу в чужую карточку.
      const resolved = await resolveEntity(matcher, null, mapped.phoneRaw, report);
      if (!resolved) continue;

      const assignedTo = await matcher.userIdByName(mapped.responsible);
      if (mapped.responsible && !assignedTo) {
        // В отчёт, а не молча в NULL: имя в выгрузке есть, а пользователя под
        // него не нашлось — это факт, который обязан увидеть человек.
        unmatchedResponsibles.add(mapped.responsible);
      }

      const { canonical } = normalizePhoneRu(mapped.phoneRaw);
      const key = taskKeyFor(mapped.externalId, canonical, mapped);
      const id = deterministicUuid("hollihop-export-task", key);
      taskIdByKey.set(key, id);

      const completedAt = parseRuDate(mapped.completedRaw);
      const written = await upsert(MODE, client, "app.tasks", {
        id,
        entity_type: resolved.entityType,
        entity_id: resolved.entityId,
        title: taskTitle(mapped.description),
        description: mapped.description || null,
        status: taskStatusFromRow(mapped.status, completedAt),
        due_at: parseRuDate(mapped.dueRaw),
        assigned_to: assignedTo,
        created_by: null,
      });
      if (written) report.written++;
      else if (MODE === "apply") report.skippedDuplicate++;
    }

    // ---- Task history ------------------------------------------------------
    // Written with the ORIGINAL changed_at (spec §2.2 «по датам и времени
    // выполнения»), and marked source='hollihop' so a re-import can replace its
    // own rows without touching anything staff did in the app.
    for (const row of historyRows) {
      const report = reports.taskHistory;
      const mapped = taskHistoryFromRow(row);
      if (!mapped) continue;
      report.total++;

      const task = taskFromRow(row);
      if (!task) {
        report.unmatchedNoRecord++;
        continue;
      }
      const { canonical } = normalizePhoneRu(task.phoneRaw);
      const key = taskKeyFor(task.externalId, canonical, task);
      const taskId = taskIdByKey.get(key);
      if (!taskId) {
        // History for a task that is not in tasks.json — without the task row
        // there is nothing to hang it on.
        report.unmatchedNoRecord++;
        continue;
      }
      report.matchedById++;

      const changedAt = parseRuDate(mapped.changedRaw);
      const changedBy = await matcher.userIdByName(mapped.author);
      if (mapped.author && !changedBy) unmatchedResponsibles.add(mapped.author);

      const written = await upsert(MODE, client, "app.task_history", {
        id: deterministicUuid(
          "hollihop-export-task-history",
          `${key}:${mapped.changedRaw}:${mapped.field}`,
        ),
        task_id: taskId,
        field: historyFieldName(mapped.field),
        old_value: mapped.oldValue,
        new_value: mapped.newValue,
        changed_by: changedBy,
        changed_at: changedAt,
        source: "hollihop",
      });
      if (written) report.written++;
      else if (MODE === "apply") report.skippedDuplicate++;
    }

    // ---- Student notes -----------------------------------------------------
    for (const row of studentRows) {
      const report = reports.studentNotes;
      const mapped = studentNoteFromRow(row);
      if (!mapped) continue;
      report.total++;

      // Файл знает, чей это id: строка из students.json → ученик. Гадать по
      // самому числу нельзя — 58 чисел существуют и как Student.Id, и как
      // Lead.Id (см. ExternalIdKind).
      const resolved = await resolveEntity(
        matcher,
        { id: mapped.externalId, kind: "student" },
        mapped.phoneRaw,
        report,
      );
      if (!resolved || resolved.entityType !== "student") {
        if (resolved) report.unmatchedNoRecord++;
        continue;
      }

      const written = await upsert(MODE, client, "app.entity_comments", {
        id: deterministicUuid(
          "hollihop-export-student-note",
          `${resolved.entityId}:${mapped.note}`,
        ),
        entity_type: "student",
        entity_id: resolved.entityId,
        author_id: null,
        body: mapped.note,
        created_at: parseRuDate(mapped.createdRaw) ?? undefined,
      });
      if (written) report.written++;
      else if (MODE === "apply") report.skippedDuplicate++;
    }

    // ---- Lead comments -----------------------------------------------------
    for (const row of leadRows) {
      const report = reports.leadComments;
      const mapped = leadCommentFromRow(row);
      if (!mapped) continue;
      report.total++;

      // Строка из leads.json → лид. См. комментарий выше.
      const resolved = await resolveEntity(
        matcher,
        { id: mapped.externalId, kind: "lead" },
        mapped.phoneRaw,
        report,
      );
      if (!resolved || resolved.entityType !== "lead") {
        if (resolved) report.unmatchedNoRecord++;
        continue;
      }

      const written = await upsert(MODE, client, "app.entity_comments", {
        id: deterministicUuid(
          "hollihop-export-lead-comment",
          `${resolved.entityId}:${mapped.note}`,
        ),
        entity_type: "lead",
        entity_id: resolved.entityId,
        author_id: null,
        body: mapped.note,
        created_at: parseRuDate(mapped.createdRaw) ?? undefined,
      });
      if (written) report.written++;
      else if (MODE === "apply") report.skippedDuplicate++;
    }
  }

  return {
    reports,
    unmatchedResponsibles: [...unmatchedResponsibles].sort(),
  };
}

/** Отчёт о полноте (шаг 2 из §6): без него «добились всех данных» непроверяемо. */
export function formatReport(run: ImportRun, mode: ImportMode): string {
  const lines = [`\nHolliHop export import — mode=${mode}`];
  for (const [section, r] of Object.entries(run.reports)) {
    const matched = r.matchedById + r.matchedByPhone;
    const unmatched = r.unmatchedNoPhone + r.unmatchedNoRecord;
    lines.push(
      `\n${section}: ${r.total} row(s) in source\n` +
        `  matched:   ${matched} (by id ${r.matchedById}, by phone ${r.matchedByPhone})\n` +
        `  unmatched: ${unmatched} (no usable phone ${r.unmatchedNoPhone}, no such record ${r.unmatchedNoRecord})\n` +
        `  written:   ${r.written}${mode === "apply" ? `, already present ${r.skippedDuplicate}` : " (dry run — nothing written)"}`,
    );
  }
  if (run.unmatchedResponsibles.length > 0) {
    lines.push(
      `\n⚠️  ${run.unmatchedResponsibles.length} responsible name(s) had no matching user — those tasks land with no assignee:`,
    );
    for (const name of run.unmatchedResponsibles) lines.push(`     ${name}`);
  }
  if (mode !== "apply") {
    lines.push(
      "\nDry run. Re-run with HOLLIHOP_EXPORT_IMPORT_MODE=apply to write.",
    );
  }
  return lines.join("\n");
}

async function main(): Promise<void> {
  if (!EXPORTS_DIR) throw new Error("HOLLIHOP_EXPORTS_DIR is required.");
  if (!existsSync(EXPORTS_DIR)) {
    throw new Error(`HOLLIHOP_EXPORTS_DIR does not exist: ${EXPORTS_DIR}`);
  }
  if (!CONNECTION_STRING) {
    throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
  }

  // dry_run тоже подключается: смысл сухого прогона — реальные счётчики
  // совпадений, а их можно посчитать только по живой базе (только чтение).
  const pool = new Pool({
    connectionString: CONNECTION_STRING,
    max: 2,
    connectionTimeoutMillis: 10_000,
  });
  const client = await pool.connect();
  try {
    if (MODE === "apply") await client.query("begin");
    const run = await runImport({ client, exportsDir: EXPORTS_DIR, mode: MODE });
    if (MODE === "apply") await client.query("commit");
    console.log(formatReport(run, MODE));
  } catch (error) {
    if (MODE === "apply") await client.query("rollback");
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

// Запуск только как скрипт: под require из тестов main() не стартует.
if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
