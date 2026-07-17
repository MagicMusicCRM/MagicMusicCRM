// server/src/migration/hollihop-export-mappers.ts
// Pure parsers for HolliHop manual exports (XLSX/CSV converted to JSON).
//
// Why files and not the API: probed 2026-07-16 with the customer's key —
// GetTasks / GetComments / GetHistory and every other method our old docs named
// return 404. Tasks and comments simply are not in that API; the only way to get
// them is an export from the HolliHop UI. See
// docs/import/hollihop_api_probe_2026-07-16.md.
//
// Everything here is a pure function on one row, so the parsing rules are
// unit-tested without needing a sample file or a database.

function str(value: unknown): string {
  return typeof value === "string"
    ? value.trim()
    : value === null || value === undefined
      ? ""
      : String(value).trim();
}

/** First non-empty value among several possible column spellings. */
function pick(row: Record<string, unknown>, ...columns: string[]): string {
  for (const column of columns) {
    const value = str(row[column]);
    if (value) return value;
  }
  return "";
}

// ── Внешние id ───────────────────────────────────────────────────────────────
//
// ⚠️ У HolliHop ДВА разных числовых id на человека, и путать их нельзя:
//   `Id`       — id учебной записи (Student.Id / Lead.Id);
//   `ClientId` — id человека-клиента, общий на всех его учебных записей.
//
// Наш первичный ключ выведен из ПЕРВОГО: `deterministicUuid("hollihop-student",
// student.Id)` (так делал прежний импорт, файл достаётся из `7f2a3fd7^`).
// Поэтому подставлять сюда ClientId нельзя ни при каких обстоятельствах.
//
// Это не теория. В выгрузке заказчика (`students.json`, 1055 строк) **у 113
// строк `ИД клиента` равен `ИД` ДРУГОГО ученика**: например, у «--- Анастасия»
// (ИД 7570) `ИД клиента` = 3871, а 3871 — это ИД Алисы Якимчук. Прими мы
// ClientId за Id, и заметки 113 человек молча уехали бы в чужие карточки.
//
// Сейчас от этого спасала только опечатка: выгрузка пишет «ИД» КИРИЛЛИЦЕЙ
// (U+0418 U+0414), а маппер искал латинское «ID» — и не находил ничего,
// откатываясь на телефон. Один баг маскировал другой: «почини» кто-нибудь
// кириллицу, не тронув приоритет, — и получил бы порчу данных.
//
// Отсюда два отдельных явных хелпера вместо одного `pick(...)` со свалкой
// написаний.

/**
 * Id **учебной записи ученика** (Student.Id) — тот, из которого выведен наш
 * первичный ключ. Кириллическая «ИД» — как её пишет выгрузка из интерфейса,
 * латинские — как отдаёт API.
 *
 * `ИД клиента`/`ClientId` здесь намеренно НЕ читается: см. заметку выше.
 */
export function studentExternalId(row: Record<string, unknown>): string {
  return pick(row, "ИД", "Id", "ID");
}

/**
 * Id лида (Lead.Id). У лида ClientId нет вовсе (проверено по дампу API), так
 * что путать не с чем; выгрузка пишет его латиницей — «ID».
 */
export function leadExternalId(row: Record<string, unknown>): string {
  return pick(row, "ID", "Id", "ИД");
}

/**
 * Parses the Russian date format the exports use. The hour may be single-digit
 * and the separator is sometimes a newline («18.03.2026\n9:55»).
 *
 * Returns a UTC instant. The export carries no timezone, so this treats the
 * wall-clock as UTC — the same convention the original import used, kept so a
 * re-import lands on the same instants as the 514 tasks already in production.
 */
export function parseRuDate(raw: unknown): string | null {
  const value = str(raw).replace(/\s+/g, " ");
  const match = value.match(
    /^(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/,
  );
  if (!match) return null;
  const [, dd, mm, yyyy, hh, mi] = match;
  const iso = `${yyyy}-${mm}-${dd}T${(hh ?? "0").padStart(2, "0")}:${mi ?? "00"}:00.000Z`;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  // Round-trip check rejects 31.02.2026 and friends, which Date happily rolls over.
  if (
    date.getUTCFullYear() !== Number(yyyy) ||
    date.getUTCMonth() + 1 !== Number(mm) ||
    date.getUTCDate() !== Number(dd)
  ) {
    return null;
  }
  if (hh !== undefined && (date.getUTCHours() !== Number(hh) || date.getUTCMinutes() !== Number(mi))) {
    return null;
  }
  return date.toISOString();
}

export function taskTitle(description: string): string {
  const first = str(description).split(/\r?\n/).find((line) => line.trim().length) ?? "";
  const trimmed = first.trim();
  if (!trimmed) return "Задача (HolliHop)";
  return trimmed.length > 120 ? trimmed.slice(0, 120) : trimmed;
}

/** Drops placeholders like «[Для всех]» that name nobody. */
export function cleanResponsible(raw: unknown): string | null {
  const value = str(raw);
  if (!value || /^\[.*\]$/.test(value)) return null;
  return value;
}

/**
 * Pulls the author out of the description when the «Ответственный» column does
 * not name one.
 *
 * This is the fix for the known defect: all 514 previously imported tasks have
 * assigned_to = NULL, because the column holds «[Для всех]» while the real name
 * sits inside the text as «(поставил Иванов И.И. - 12.03.2026)».
 */
export function responsibleFromDescription(description: unknown): string | null {
  const value = str(description);
  // `поставил(а)?` rather than an alternation: `поставил|поставила` would match
  // the shorter branch first and leave the «а» glued to the name.
  const match = value.match(
    /\(\s*(?:поставил(?:а)?|автор)\s*:?\s*([^)\-–—]+?)\s*(?:[-–—]\s*[\d.]+\s*)?\)/i,
  );
  const name = match?.[1]?.trim();
  return name ? name : null;
}

export interface ExportTask {
  /** HolliHop id when the export carries one; matching prefers it over phone. */
  externalId: string;
  phoneRaw: string;
  clientName: string;
  description: string;
  dueRaw: string;
  responsible: string | null;
  /** Original completion moment, when the export records one. */
  completedRaw: string;
  status: string;
}

export function taskFromRow(row: Record<string, unknown>): ExportTask | null {
  const description = pick(row, "Описание");
  const clientName = pick(row, "Клиент");
  if (!description && !clientName) return null;
  return {
    // Выгрузка задач id не содержит вовсе (проверено на файле заказчика: 0 из
    // 527 строк) — у неё есть только «Клиент» и телефон. Читаем `ИД`/`Id` на
    // случай, если он появится, но НЕ `ID клиента`: подставить ClientId в
    // ученический namespace значит попасть в чужую карточку (см. заметку
    // выше). Пока колонки нет, задачи сопоставляются телефоном, и это не
    // фолбэк, а единственный доступный способ.
    externalId: studentExternalId(row),
    phoneRaw: pick(row, "Моб. телефон", "Телефон"),
    clientName,
    description,
    dueRaw: pick(row, "Дата выполнения"),
    // Column first; fall back to the name buried in the text.
    responsible:
      cleanResponsible(pick(row, "Ответственный")) ??
      responsibleFromDescription(description),
    completedRaw: pick(row, "Дата завершения", "Выполнено"),
    status: pick(row, "Статус"),
  };
}

/**
 * Maps an export status to ours. Unknown/absent → 'open', which is what the
 * original import assumed for every row.
 */
export function taskStatusFromRow(status: string, completedAt: string | null): string {
  const value = status.toLowerCase();
  if (/выполнен|заверш|сделан/.test(value)) return "done";
  if (/отмен/.test(value)) return "cancelled";
  if (/в работе|в процессе/.test(value)) return "in_progress";
  // A completion date with no status still means it is done.
  return completedAt ? "done" : "open";
}

export interface ExportNote {
  externalId: string;
  phoneRaw: string;
  name: string;
  note: string;
  createdRaw: string;
}

export function studentNoteFromRow(row: Record<string, unknown>): ExportNote | null {
  const note = pick(row, "Описание", "Комментарий", "Примечание");
  if (!note) return null;
  return {
    externalId: studentExternalId(row),
    phoneRaw: pick(row, "Моб. телефон", "Телефон"),
    name: [pick(row, "Фамилия"), pick(row, "Имя")].filter(Boolean).join(" "),
    note,
    // «Дата обращения» здесь НЕ читается, хотя она в выгрузке единственная
    // дата: это день, когда клиент впервые обратился, а не когда написали
    // заметку. Поставить её датой заметки значило бы выдумать факт. Заметка
    // на карточке ученика — поле, а не событие, и своей даты у неё нет.
    createdRaw: pick(row, "Дата создания"),
  };
}

export function leadCommentFromRow(row: Record<string, unknown>): ExportNote | null {
  const comment = pick(row, "Комментарий");
  if (!comment) return null;
  const extra = pick(row, "Пользовательские поля");
  return {
    externalId: leadExternalId(row),
    phoneRaw: pick(row, "Моб. телефон", "Телефон"),
    name: pick(row, "ФИО"),
    note: extra ? `${comment}\n${extra}` : comment,
    createdRaw: pick(row, "Дата создания"),
  };
}

export interface ExportTaskHistory {
  field: string;
  oldValue: string | null;
  newValue: string | null;
  author: string | null;
  changedRaw: string;
}

/**
 * A task-history row, if the export has one. Feeds app.task_history with the
 * ORIGINAL date (spec §2.2: «по датам и времени выполнения») rather than the
 * import date.
 *
 * Returns null when the row carries no usable timestamp: an undated history
 * entry would sort to the epoch and read as though it happened in 1970.
 */
export function taskHistoryFromRow(
  row: Record<string, unknown>,
): ExportTaskHistory | null {
  const changedRaw = pick(row, "Дата изменения", "Дата", "Когда");
  if (!parseRuDate(changedRaw)) return null;
  const field = pick(row, "Поле", "Что изменено");
  if (!field) return null;
  return {
    field,
    oldValue: pick(row, "Было", "Старое значение") || null,
    newValue: pick(row, "Стало", "Новое значение") || null,
    author: cleanResponsible(pick(row, "Автор", "Кто", "Пользователь")),
    changedRaw,
  };
}

/** Maps an export's Russian field label onto our task_history field names. */
export function historyFieldName(label: string): string {
  const value = label.toLowerCase();
  if (/срок|дата выполнен/.test(value)) return "due_at";
  if (/статус/.test(value)) return "status";
  if (/ответствен|исполнител/.test(value)) return "assigned_to";
  if (/описан/.test(value)) return "description";
  if (/назван|заголов/.test(value)) return "title";
  return label;
}
