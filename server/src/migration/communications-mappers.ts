// server/src/migration/communications-mappers.ts
//
// Разбор выгрузки «Коммуникации» HolliHop.
//
// ✔ Пояснение заказчика 17.07: «в файле коммуникации лежат на самом деле все
// задачи, которые были и есть за всё время; в файле задачи — актуальные
// висящие». Проверено на файлах: 12 744 реальных строки, из них 12 269 задач
// (12 162 закрытых, 531 открытая) и 475 обычных коммуникаций; «Задачи» — 544,
// и ни одна не закрыта.
//
// ГЛАВНОЕ. В API HolliHop истории задач нет (GetHistory → 404, проверено
// боевым ключом 16.07). Но она никуда не девалась — она **зашита в текст**:
//
//   надо записать на пробный, переписка в тг
//   (поставил Богатырёва М. В. - 15.06)                      ← автор + дата
//   Статус "Закрыта" (установил Мазалова А. Ю.) - 16.06 19:42 ← событие
//
// Отсюда весь этот файл: вытащить из текста то, чему место в полях.
//
// Всё здесь — чистые функции над одной строкой, поэтому правила проверяются
// юнит-тестами без файла и без базы.

function str(value: unknown): string {
  return typeof value === "string"
    ? value.trim()
    : value === null || value === undefined
      ? ""
      : String(value).trim();
}

/**
 * «(поставил X - 21.06)» или «(поставил X - 09.07.25)».
 *
 * Обе формы реальны: без года — 7 208 строк, с двузначным годом — 5 062.
 * `поставил(а)?` — не альтернация: `поставил|поставила` совпало бы с короткой
 * веткой и приклеило «а» к имени.
 */
const RE_CREATOR =
  /\(\s*поставил(?:а)?\s+([^)\-–—]+?)\s*[-–—]\s*(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?\s*\)/i;

/**
 * То же самое, но для вырезания из тела — глобально.
 *
 * ⚠️ Нужен отдельный regex с `g`: в двух строках выгрузки HolliHop склеил
 * НЕСКОЛЬКО задач в одну ячейку (задачу закрыли, потом дописали новую), и там
 * по два «(поставил …)». `replace` без `g` убирал только первое, и второе
 * оставалось в теле — ровно тот мусор, ради вычистки которого этот файл и
 * написан.
 *
 * Автором считаем ПЕРВОГО: он поставил задачу раньше. Разбивать такую ячейку
 * на две задачи не станем — это 2 строки из 12 744, и склейка сделана
 * человеком в HolliHop, а не нами.
 */
const RE_CREATOR_ALL = new RegExp(RE_CREATOR.source, "gi");

/**
 * «Статус "Закрыта" (установил Y) - 21.06 14:14» или «Статус "Закрыта" -
 * 06.09.25 16:04».
 *
 * Автор необязателен: у 316 строк из 12 162 его нет. Пропусти это — и 316
 * событий потерялись бы целиком, а не просто остались без автора.
 */
const RE_STATUS =
  /Статус\s+"([^"]+)"\s*(?:\(\s*установил(?:а)?\s+([^)]+?)\s*\))?\s*[-–—]\s*(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?(?:\s+(\d{1,2}):(\d{2}))?/gi;

export interface StatusEvent {
  /** Значение статуса как его написал HolliHop («Закрыта»). */
  status: string;
  /** Кто перевёл. `null` — в строке автора нет (316 случаев). */
  actor: string | null;
  day: number;
  month: number;
  /** Явный год из строки, если он там был. */
  year: number | null;
  hour: number | null;
  minute: number | null;
}

export interface ParsedTaskDescription {
  /** Текст задачи без служебных строк — то, что человек написал. */
  body: string;
  /** Кто поставил задачу. `null` — в тексте не сказано. */
  createdBy: string | null;
  createdDay: number | null;
  createdMonth: number | null;
  /** Явный год постановки, если он был в строке. */
  createdYear: number | null;
  /** События смены статуса, в порядке появления. */
  statusEvents: StatusEvent[];
}

/**
 * Разбирает «Описание» строки коммуникации.
 *
 * Служебные строки из `body` **вырезаются**: «(поставил …)» и «Статус "…"» —
 * это метаданные, и им место в полях, а не в тексте задачи. Прошлый импорт
 * оставил их внутри, и теперь на проде 8 579 «комментариев» выглядят так:
 * «Сайт · Исходящая: Контроль ⏎ (поставил Каралкина А. А. - 06.04.24) ⏎
 * Статус "Закрыта" - 09.04.24 12:29» — из такого нельзя ни отфильтровать, ни
 * посчитать, ни показать лентой.
 */
export function parseTaskDescription(raw: unknown): ParsedTaskDescription {
  const text = str(raw);
  const statusEvents: StatusEvent[] = [];

  RE_STATUS.lastIndex = 0;
  for (const m of text.matchAll(RE_STATUS)) {
    statusEvents.push({
      status: m[1].trim(),
      actor: m[2]?.trim() || null,
      day: Number(m[3]),
      month: Number(m[4]),
      year: m[5] ? normalizeYear(Number(m[5])) : null,
      hour: m[6] !== undefined ? Number(m[6]) : null,
      minute: m[7] !== undefined ? Number(m[7]) : null,
    });
  }

  const creator = RE_CREATOR.exec(text);

  RE_CREATOR_ALL.lastIndex = 0;
  RE_STATUS.lastIndex = 0;
  const body = text
    .replace(RE_CREATOR_ALL, "")
    .replace(RE_STATUS, "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join("\n")
    .trim();

  return {
    body,
    createdBy: creator?.[1]?.trim() || null,
    createdDay: creator ? Number(creator[2]) : null,
    createdMonth: creator ? Number(creator[3]) : null,
    createdYear: creator?.[4] ? normalizeYear(Number(creator[4])) : null,
    statusEvents,
  };
}

/** «25» → 2025, «2025» → 2025. Выгрузка пишет и так, и так. */
function normalizeYear(value: number): number {
  return value < 100 ? 2000 + value : value;
}

/**
 * Восстанавливает год у даты без года.
 *
 * Порядок: явный год → год якоря → якорь минус год, если иначе дата окажется
 * ПОЗЖЕ якоря.
 *
 * Якорь — момент, раньше которого событие точно произошло: для закрытой задачи
 * это её закрытие, для открытой — дата выгрузки. Правило проверено на данных:
 * у **всех 6 688** закрытых задач «поставил» строго раньше закрытия,
 * исключений ноль. Значит, откат на год срабатывает только там, где задачу
 * реально ставили в прошлом году, — а такое бывает (задача через новый год).
 */
export function resolveYear(
  date: { day: number; month: number; year: number | null },
  anchor: { day: number; month: number; year: number },
): number {
  if (date.year !== null) return date.year;
  const laterThanAnchor =
    date.month > anchor.month ||
    (date.month === anchor.month && date.day > anchor.day);
  return laterThanAnchor ? anchor.year - 1 : anchor.year;
}

/**
 * Собирает UTC-инстант.
 *
 * Выгрузка часового пояса не несёт, поэтому стенные часы читаются как UTC — та
 * же условность, что и в прежнем импорте (`parseRuDate`), сохранена намеренно:
 * иначе реимпорт разъедется по времени с уже залитыми строками.
 */
export function toInstant(
  day: number,
  month: number,
  year: number,
  hour = 0,
  minute = 0,
): string | null {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  const date = new Date(
    Date.UTC(year, month - 1, day, hour, minute, 0, 0),
  );
  // Date.UTC молча превращает 31.02 в 03.03 — такую дату не принимаем.
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return date.toISOString();
}

/** Дата строки: «11.08.2027» или «21.06.2026\n14:14». */
export function parseRowDate(raw: unknown): {
  day: number;
  month: number;
  year: number;
  hour: number;
  minute: number;
  iso: string;
} | null {
  const text = str(raw).replace(/\s+/g, " ");
  const m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/.exec(text);
  if (!m) return null;
  const day = Number(m[1]);
  const month = Number(m[2]);
  const year = Number(m[3]);
  const hour = m[4] !== undefined ? Number(m[4]) : 0;
  const minute = m[5] !== undefined ? Number(m[5]) : 0;
  const iso = toInstant(day, month, year, hour, minute);
  if (!iso) return null;
  return { day, month, year, hour, minute, iso };
}

/** Строка «Коммуникаций», разобранная в то, что можно положить в базу. */
export interface ExportCommunication {
  /** `Student.Id`. Пусто у лидов — у них этой колонки не заполняют. */
  studentExternalId: string;
  clientName: string;
  /** Способ («Сайт», «Звонок») — метаданные, в тело НЕ клеятся. */
  channel: string;
  /** Направление («Исходящая») — тоже метаданные. */
  direction: string;
  /** Дата строки: срок у открытой задачи, момент закрытия у закрытой. */
  rowDateRaw: string;
  description: string;
  /** True, если строка — задача (в тексте есть «поставил»). */
  isTask: boolean;
  parsed: ParsedTaskDescription;
}

export function communicationFromRow(
  row: Record<string, unknown>,
): ExportCommunication | null {
  const description = str(row["Описание"]);
  const clientName = str(row["Ученик"]);
  // Пустой хвост выгрузки: в файле 127 459 строк, реальных 12 744.
  if (!description && !clientName) return null;

  const parsed = parseTaskDescription(description);
  return {
    studentExternalId: str(row["ИД ученика"]),
    clientName,
    channel: str(row["Способ"]),
    direction: str(row["Направление"]),
    rowDateRaw: str(row["Дата"]),
    description,
    // Задача — та, у которой в тексте есть «поставил». Статус без «поставил»
    // тоже считаем задачей: 316 таких строк, и это закрытия.
    isTask: parsed.createdBy !== null || parsed.statusEvents.length > 0,
    parsed,
  };
}

/**
 * Наш статус по тексту HolliHop. Во всех 12 162 закрытиях значение одно —
 * «Закрыта», но чинить это перечисление по факту одного значения не стоит:
 * следующая выгрузка может принести другое.
 */
export function taskStatusFromEvents(events: StatusEvent[]): string {
  if (events.length === 0) return "open";
  const last = events[events.length - 1].status.toLowerCase();
  if (/закрыт|выполнен|заверш|сделан/.test(last)) return "done";
  if (/отмен/.test(last)) return "cancelled";
  if (/в работе|в процессе/.test(last)) return "in_progress";
  return "open";
}

/** Заголовок задачи — первая непустая строка тела, обрезанная до 120. */
export function taskTitleFromBody(body: string): string {
  const first = body.split(/\r?\n/).find((line) => line.trim().length) ?? "";
  const trimmed = first.trim();
  if (!trimmed) return "Задача (HolliHop)";
  return trimmed.length > 120 ? trimmed.slice(0, 120) : trimmed;
}

/**
 * Ключ задачи для идемпотентности.
 *
 * ⚠️ Статус и события в ключ НЕ входят намеренно. Задача живёт: сегодня она
 * открыта, завтра закрыта — и если статус попадёт в ключ, следующая выгрузка
 * породит ВТОРУЮ задачу вместо обновления первой. Ключ — это «какая задача»,
 * а не «в каком она состоянии».
 *
 * Тело + дата постановки + клиент: этого достаточно, чтобы отличить две задачи
 * одного человека, и это не меняется при смене статуса.
 */
export function communicationTaskKey(
  subject: string,
  parsed: ParsedTaskDescription,
): string {
  const created =
    parsed.createdDay !== null
      ? `${parsed.createdDay}.${parsed.createdMonth}.${parsed.createdYear ?? ""}`
      : "";
  return `export:comm-task:${subject}:${created}:${parsed.body}`;
}
