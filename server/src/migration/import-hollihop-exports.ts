// server/src/migration/import-hollihop-exports.ts
//
// Заливает ручные выгрузки HolliHop на уже импортированные записи: задачи с их
// историей, заметки учеников, комментарии лидов.
//
// ЗАДАЧАМИ ВЛАДЕЮТ «КОММУНИКАЦИИ», и только они. Файл «Задачи» здесь НЕ
// читается — он избыточен и вреден:
//   • 532 его строки из 544 уже есть в «Коммуникациях» (сверено 17.07);
//   • оставшиеся 12 — вообще без клиента («забрать озон», «лиза уезжает»), их
//     не к кому привязать;
//   • зато при заливке обоих файлов висящие задачи легли ДВАЖДЫ: 685 групп
//     дублей, 1 281 лишняя строка. Ровно эта болезнь и есть на проде (1 878
//     дублей) — просто здесь её поймал чек-лист (§6.3) до заливки.
// Пояснение заказчика совпало с данными: «в файле коммуникации лежат все задачи
// за всё время, в файле задачи — актуальные висящие».
//
// Истории задач отдельным файлом тоже нет: она внутри «Коммуникаций», в тексте.
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
//   communications — Дата, Ученик, Способ, Направление, Описание, ИД ученика
//   students       — Фамилия, Имя, Описание, телефон
//   leads          — ФИО, Комментарий, Пользовательские поля, телефон
//
// Ещё нужен HOLLIHOP_EXPORT_DATE=YYYY-MM-DD — день снятия выгрузки. Это якорь
// для дат без года у открытых задач; «сегодня» по умолчанию сделало бы результат
// зависящим от дня запуска.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Pool, PoolClient } from "pg";
import { normalizePhoneRu } from "../crm/phone.util";
import { deterministicUuid } from "./import-id";
import {
  communicationFromRow,
  communicationTaskKey,
  parseRowDate,
  resolveYear,
  taskStatusFromEvents,
  taskTitleFromBody,
  toInstant,
} from "./communications-mappers";
import { parseStaffName } from "./staff-name";
import { readXlsxRows } from "./xlsx-reader";
import {
  leadCommentFromRow,
  parseRuDate,
  studentNoteFromRow,
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
  private readonly leadByName = new Map<string, string | null>();
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

  /**
   * Лид по ФИО из колонки «Ученик».
   *
   * Нужен, потому что у лидов «ИД ученика» в «Коммуникациях» пуст — они же ещё
   * не ученики. Имя остаётся единственной зацепкой: на выгрузке так находится
   * 2 996 строк из 12 744.
   *
   * ⚠️ Связываем ТОЛЬКО при единственном совпадении (limit 2 + проверка). У 160
   * строк имя даёт несколько лидов — это дубли лида в HolliHop. Возьми мы
   * первого попавшегося, задача уехала бы в карточку постороннего, и выглядело
   * бы это как точное попадание. Такие строки честнее показать в отчёте.
   */
  async leadByFullName(name: string): Promise<string | null> {
    const key = name.toLowerCase().trim();
    if (!key) return null;
    return this.cached(this.leadByName, key, async () => {
      const exact = await this.client.query<{ id: string }>(
        `select id from app.leads
         where deleted_at is null
           and lower(btrim(concat_ws(' ', last_name, first_name))) = $1
         limit 2`,
        [key],
      );
      if (exact.rows.length === 1) return exact.rows[0].id;
      if (exact.rows.length > 1) return null; // однофамильцы — пусть решает человек

      // Второй проход: имя лида — префикс имени из выгрузки.
      //
      // «Коммуникации» пишут человека с отчеством («Худякова Дана Сергеевна»), а
      // лид заведён без него («Худякова Дана»). Точное сравнение такое не ловит,
      // и это 442 строки.
      //
      // Правило именно про префикс, а не про «первые два слова»: порядок слов в
      // данных не один. Встречается и «Оксана Игоревна Грушина» — имя-отчество-
      // фамилия, причём и сам лид заведён с перепутанными полями. Префикс
      // работает в обоих случаях, потому что опирается на то, что записано, а не
      // на догадку о том, где здесь фамилия.
      //
      // Пробел в конце обязателен: без него «Иванов Иванна» совпала бы с лидом
      // «Иванов Иван». Единственность — как и всюду здесь: несколько
      // лидов-префиксов → не связываем.
      const prefix = await this.client.query<{ id: string }>(
        `select id from app.leads
         where deleted_at is null
           and length(btrim(concat_ws(' ', last_name, first_name))) > 0
           and starts_with($1, lower(btrim(concat_ws(' ', last_name, first_name))) || ' ')
         limit 2`,
        [key],
      );
      return prefix.rows.length === 1 ? prefix.rows[0].id : null;
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

export interface ImportRun {
  reports: Record<string, SectionReport>;
  unmatchedResponsibles: string[];
  /** Строки «Коммуникаций», которые не удалось привязать, — с причиной. */
  unmatchedCommunications: { name: string; reason: string }[];
}

/**
 * Раздел «Коммуникации» — все задачи школы за всё время плюс их история.
 *
 * Разбор строки — в communications-mappers.ts; здесь только привязка к людям и
 * запись. Почему именно этот файл, а не «Задачи»: в «Задачах» 544 строки и ни
 * одной закрытой, а в «Коммуникациях» — 12 692 задачи, из них 12 161 закрытая,
 * и у каждой в тексте автор, дата постановки и события закрытия.
 *
 * Год восстанавливается по якорю (`resolveYear`): у закрытой задачи якорь — её
 * закрытие, у открытой — дата выгрузки. Без этого «21.06» без года лёг бы
 * произвольным годом.
 */
async function importCommunications(options: {
  client: QueryClient;
  mode: ImportMode;
  rows: JsonRow[];
  matcher: Matcher;
  report: SectionReport;
  /** Дата выгрузки — якорь для дат открытых задач. */
  exportDate: { day: number; month: number; year: number };
  unmatchedResponsibles: Set<string>;
  unmatched: { name: string; reason: string }[];
}): Promise<void> {
  const { client, mode, rows, matcher, report, exportDate, unmatchedResponsibles, unmatched } =
    options;

  for (const row of rows) {
    const comm = communicationFromRow(row);
    if (!comm) continue;
    report.total++;

    // Ученик по id, иначе лид по имени: у лида «ИД ученика» пуст, он же ещё не
    // ученик. Гадать по числу нельзя — id учеников и лидов пересекаются.
    let resolved: Resolved | null = null;
    if (comm.studentExternalId) {
      const studentId = await matcher.studentByExternalId(comm.studentExternalId);
      if (studentId) {
        resolved = { entityType: "student", entityId: studentId, by: "id" };
        report.matchedById++;
      }
    }
    if (!resolved && comm.clientName) {
      const leadId = await matcher.leadByFullName(comm.clientName);
      if (leadId) {
        resolved = { entityType: "lead", entityId: leadId, by: "id" };
        report.matchedById++;
      }
    }
    if (!resolved) {
      report.unmatchedNoRecord++;
      unmatched.push({
        name: comm.clientName || "(без имени)",
        reason: comm.studentExternalId
          ? `ученика с ИД ${comm.studentExternalId} нет в базе`
          : "имя не найдено среди лидов либо даёт несколько",
      });
      continue;
    }

    const { parsed } = comm;
    const rowDate = parseRowDate(comm.rowDateRaw);

    if (!comm.isTask) {
      // Не задача — обычная коммуникация. Их 52 из 12 744.
      const written = await upsert(mode, client, "app.entity_comments", {
        id: deterministicUuid(
          "hollihop-communication",
          `${resolved.entityId}:${comm.rowDateRaw}:${parsed.body}`,
        ),
        entity_type: resolved.entityType,
        entity_id: resolved.entityId,
        author_id: null,
        body: parsed.body,
        kind: "admin_comment",
        created_at: rowDate?.iso ?? undefined,
      });
      if (written) report.written++;
      else if (mode === "apply") report.skippedDuplicate++;
      continue;
    }

    const events = parsed.statusEvents;
    const status = taskStatusFromEvents(events);
    const last = events[events.length - 1];

    // Якорь для дат без года: закрытие задачи, иначе дата выгрузки. У закрытой
    // задачи «поставил» строго раньше закрытия — проверено на всех 6 688.
    const anchor =
      last && last.year !== null
        ? { day: last.day, month: last.month, year: last.year }
        : last && rowDate
          ? { day: last.day, month: last.month, year: rowDate.year }
          : exportDate;

    const createdIso =
      parsed.createdDay !== null && parsed.createdMonth !== null
        ? toInstant(
            parsed.createdDay,
            parsed.createdMonth,
            resolveYear(
              { day: parsed.createdDay, month: parsed.createdMonth, year: parsed.createdYear },
              anchor,
            ),
          )
        : null;

    const createdBy = await matcher.userIdByName(parsed.createdBy);
    if (parsed.createdBy && !createdBy) unmatchedResponsibles.add(parsed.createdBy);

    const key = communicationTaskKey(comm.studentExternalId || comm.clientName, parsed);
    const taskId = deterministicUuid("hollihop-comm-task", key);

    const written = await upsert(mode, client, "app.tasks", {
      id: taskId,
      entity_type: resolved.entityType,
      entity_id: resolved.entityId,
      title: taskTitleFromBody(parsed.body),
      description: parsed.body || null,
      status,
      // Дата строки: у открытой задачи это срок, у закрытой — момент закрытия.
      // Сроком он остаётся только у открытой; у закрытой ставить его в due_at
      // значило бы выдать день закрытия за назначенный срок.
      due_at: status === "done" || status === "cancelled" ? null : (rowDate?.iso ?? null),
      assigned_to: createdBy,
      created_by: createdBy,
      created_at: createdIso ?? undefined,
    });
    if (written) report.written++;
    else if (mode === "apply") report.skippedDuplicate++;

    // История: по событию на каждую смену статуса, с ИСХОДНОЙ датой и актором.
    for (const [index, event] of events.entries()) {
      const year = resolveYear({ day: event.day, month: event.month, year: event.year }, anchor);
      const changedAt = toInstant(
        event.day,
        event.month,
        year,
        event.hour ?? 0,
        event.minute ?? 0,
      );
      if (!changedAt) continue;
      const changedBy = await matcher.userIdByName(event.actor);
      if (event.actor && !changedBy) unmatchedResponsibles.add(event.actor);
      await upsert(mode, client, "app.task_history", {
        id: deterministicUuid("hollihop-comm-task-history", `${key}:${index}:${event.status}`),
        task_id: taskId,
        field: "status",
        old_value: null,
        new_value: taskStatusFromEvents([event]),
        changed_by: changedBy,
        changed_at: changedAt,
        source: "hollihop",
      });
    }
  }
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
  /**
   * День, когда сняли выгрузку. Якорь для дат без года у ОТКРЫТЫХ задач: у
   * закрытой год берётся от её закрытия, а у открытой другого ориентира нет.
   * Обязателен намеренно — «сегодня» по умолчанию сделало бы результат импорта
   * зависящим от дня запуска, то есть невоспроизводимым.
   */
  exportDate: { day: number; month: number; year: number };
}): Promise<ImportRun> {
  const { client, exportsDir, mode } = options;

  const studentRows = readArrayFile(exportsDir, "students", "Students");
  const leadRows = readArrayFile(exportsDir, "leads", "Leads");
  const communicationRows = readArrayFile(exportsDir, "communications", "Communications");

  const reports: Record<string, SectionReport> = {
    communications: emptySection(),
    studentNotes: emptySection(),
    leadComments: emptySection(),
  };
  const unmatchedResponsibles = new Set<string>();
  const unmatchedCommunications: { name: string; reason: string }[] = [];

  {
    const MODE = mode;
    const matcher = new Matcher(client);
    // Транзакцией и соединением владеет main(): здесь только импорт.

    // ---- Communications ----------------------------------------------------
    // Идёт первым: здесь настоящие задачи школы за всё время (12 692, из них
    // 12 161 закрытая). Файл «Задачи» ниже несёт лишь актуальные висящие.
    await importCommunications({
      client,
      mode: MODE,
      rows: communicationRows,
      matcher,
      report: reports.communications,
      exportDate: options.exportDate,
      unmatchedResponsibles,
      unmatched: unmatchedCommunications,
    });

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
    unmatchedCommunications,
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
  if (run.unmatchedCommunications.length > 0) {
    // Сгруппировано по причине: 12 744 строки поимённо никто читать не станет,
    // а «сколько и почему не легло» — обязано быть видно.
    const byReason = new Map<string, number>();
    for (const item of run.unmatchedCommunications) {
      byReason.set(item.reason, (byReason.get(item.reason) ?? 0) + 1);
    }
    lines.push(
      `\n⚠️  ${run.unmatchedCommunications.length} строк(и) «Коммуникаций» не привязаны к клиенту:`,
    );
    for (const [reason, count] of [...byReason].sort((a, b) => b[1] - a[1])) {
      lines.push(`     ${count} — ${reason}`);
    }
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

/**
 * День снятия выгрузки — якорь для дат без года у открытых задач.
 *
 * Требуется явно, а не «берём сегодня»: иначе тот же файл, залитый в другой
 * день, дал бы другие годы, и повторный прогон перестал бы быть повторным.
 */
function parseExportDate(raw: string | undefined): {
  day: number;
  month: number;
  year: number;
} {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec((raw ?? "").trim());
  if (!m) {
    throw new Error(
      "HOLLIHOP_EXPORT_DATE is required in YYYY-MM-DD (день, когда сняли выгрузку).",
    );
  }
  return { year: Number(m[1]), month: Number(m[2]), day: Number(m[3]) };
}

async function main(): Promise<void> {
  if (!EXPORTS_DIR) throw new Error("HOLLIHOP_EXPORTS_DIR is required.");
  const EXPORT_DATE = parseExportDate(process.env.HOLLIHOP_EXPORT_DATE);
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
    const run = await runImport({
      client,
      exportsDir: EXPORTS_DIR,
      mode: MODE,
      exportDate: EXPORT_DATE,
    });
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
