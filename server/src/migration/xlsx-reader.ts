// server/src/migration/xlsx-reader.ts
//
// Чтение выгрузок HolliHop прямо из `.xlsx`.
//
// ЗАЧЕМ. Выгрузки приходят из интерфейса HolliHop в `.xlsx`, а импортёр читал
// JSON — то есть между файлом и базой стоял ручной шаг конвертации. Перед 12 744
// строками такой шаг рано или поздно сделают неправильно, и никто не заметит.
//
// ПОЧЕМУ БЕЗ БИБЛИОТЕКИ. `xlsx` (SheetJS) в npm застыл на 0.18.5 с
// непочиненными CVE — свежие версии живут в их собственном реестре, а это
// `.npmrc` с чужим registry для всей команды. `exceljs` тянет 9 транзитивных
// пакетов, включая `archiver` (запись — нам не нужна) и `unzipper@0.10`.
//
// А нужного нам здесь — ровно один producer и ровно одна форма ячейки.
// Проверено на обоих файлах заказчика (17.07): все 64 779 типизированных ячеек
// имеют `t="s"`, формул нет, inline-строк нет, rich-text нет, чисел и
// дат-серийников нет. `zlib.inflateRawSync` в Node уже есть.
//
// Поэтому: свой ридер на ~150 строк без единой зависимости — и сверка его
// вывода с независимым эталоном на всех 12 744 строках (см.
// `xlsx-reader.spec.ts`).
//
// ГРАНИЦЫ. Это НЕ универсальный парсер xlsx. Он читает то, что присылает
// HolliHop, и на всём остальном обязан падать с внятной ошибкой, а не молча
// возвращать полупустое. Если выгрузка однажды принесёт числа или даты —
// `parseSheetCells` бросит, и это правильное поведение: лучше остановиться, чем
// импортировать мусор.

import { readFileSync } from "node:fs";
import { crc32, inflateRawSync } from "node:zlib";

// ── ZIP ──────────────────────────────────────────────────────────────────────
//
// xlsx — это zip. Читаем только то, что нужно, и только через центральный
// каталог: у локального заголовка размеры могут быть нулями (флаг data
// descriptor), и доверять им нельзя.

const SIG_EOCD = 0x06054b50;
const SIG_CENTRAL = 0x02014b50;
const SIG_LOCAL = 0x04034b50;

/** Смещение End of Central Directory. Ищем с конца: за ним может быть комментарий. */
function findEocd(buf: Buffer): number {
  // Комментарий zip — максимум 65 535 байт, плюс сама запись EOCD (22 байта).
  const from = Math.max(0, buf.length - 0xffff - 22);
  for (let i = buf.length - 22; i >= from; i--) {
    if (buf.readUInt32LE(i) === SIG_EOCD) return i;
  }
  throw new Error("не zip: не нашёл End of Central Directory");
}

/** Распаковывает записи архива в память. Читает только `wanted`. */
export function readZipEntries(buf: Buffer, wanted: (name: string) => boolean): Map<string, Buffer> {
  const eocd = findEocd(buf);
  const entryCount = buf.readUInt16LE(eocd + 10);
  let offset = buf.readUInt32LE(eocd + 16);

  // ZIP64 помечает себя этими маркерами. Наши файлы до него не дотягивают, но
  // молча прочитать половину архива — худший из исходов.
  if (offset === 0xffffffff || entryCount === 0xffff) {
    throw new Error("zip64 не поддерживается");
  }

  const out = new Map<string, Buffer>();
  for (let i = 0; i < entryCount; i++) {
    if (buf.readUInt32LE(offset) !== SIG_CENTRAL) {
      throw new Error(`битый центральный каталог на записи ${i}`);
    }
    const method = buf.readUInt16LE(offset + 10);
    const expectedCrc = buf.readUInt32LE(offset + 16);
    const compressedSize = buf.readUInt32LE(offset + 20);
    const uncompressedSize = buf.readUInt32LE(offset + 24);
    const nameLen = buf.readUInt16LE(offset + 28);
    const extraLen = buf.readUInt16LE(offset + 30);
    const commentLen = buf.readUInt16LE(offset + 32);
    const localOffset = buf.readUInt32LE(offset + 42);
    const name = buf.toString("utf8", offset + 46, offset + 46 + nameLen);
    offset += 46 + nameLen + extraLen + commentLen;

    if (!wanted(name)) continue;

    if (buf.readUInt32LE(localOffset) !== SIG_LOCAL) {
      throw new Error(`битый локальный заголовок: ${name}`);
    }
    // Длины в локальном заголовке свои — extra там обычно другой длины, чем в
    // центральном каталоге. Берём именно локальные, иначе съедем на байты.
    const localNameLen = buf.readUInt16LE(localOffset + 26);
    const localExtraLen = buf.readUInt16LE(localOffset + 28);
    const dataStart = localOffset + 30 + localNameLen + localExtraLen;
    const data = buf.subarray(dataStart, dataStart + compressedSize);

    const content =
      method === 0
        ? Buffer.from(data)
        : method === 8
          ? inflateRawSync(data)
          : (() => {
              throw new Error(`неизвестный метод сжатия ${method}: ${name}`);
            })();

    if (content.length !== uncompressedSize) {
      throw new Error(
        `${name}: распаковалось ${content.length} байт вместо ${uncompressedSize}`,
      );
    }
    // Длина ловит обрыв, но не порчу: битый байт внутри выгрузки прошёл бы
    // насквозь и приехал в базу как чьё-то имя. Контрольная сумма для того в
    // формате и лежит — так что сверяем, как это делает любой настоящий
    // разборщик zip.
    const actualCrc = crc32(content);
    if (actualCrc !== expectedCrc) {
      throw new Error(
        `${name}: контрольная сумма не сошлась (${actualCrc} вместо ${expectedCrc}) — файл побился`,
      );
    }
    out.set(name, content);
  }
  return out;
}

// ── XML ──────────────────────────────────────────────────────────────────────

/**
 * Байты записи → текст XML, с нормализацией переводов строк.
 *
 * XML 1.0 §2.11 требует: разборщик ОБЯЗАН привести литеральные `\r\n` и
 * одиночные `\r` к `\n`. Excel пишет файл в CRLF (в «Коммуникациях» 45 691
 * литеральный CR), поэтому без этого шага каждая многострочная ячейка приезжает
 * с `\r` внутри — 12 212 ячеек из 12 745 непустых.
 *
 * ⚠️ Порядок обязателен: сначала нормализация сырого текста, потом
 * `decodeXmlText`. Спека нормализует только литеральные символы; ссылка `&#13;`
 * — это осознанно записанный автором CR, и он обязан выжить. Схлопни мы её
 * заодно — потеряли бы то единственное, что здесь отличимо от вёрстки файла.
 */
export function xmlText(buf: Buffer): string {
  return buf.toString("utf8").replace(/\r\n?/g, "\n");
}

const ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
};

/** Разворачивает XML-сущности. Числовые — тоже: HolliHop пишет переносы как `&#10;`. */
export function decodeXmlText(value: string): string {
  return value.replace(/&(#x?[0-9a-fA-F]+|[a-z]+);/g, (whole, code: string) => {
    if (code.startsWith("#x") || code.startsWith("#X")) {
      return String.fromCodePoint(parseInt(code.slice(2), 16));
    }
    if (code.startsWith("#")) {
      return String.fromCodePoint(parseInt(code.slice(1), 10));
    }
    // Неизвестную сущность оставляем как есть: выдумывать здесь нечего.
    return ENTITIES[code] ?? whole;
  });
}

const RE_SI = /<si>([\s\S]*?)<\/si>|<si\/>/g;
const RE_T = /<t(?:\s[^>]*)?>([\s\S]*?)<\/t>|<t\s*\/>/g;

/**
 * Таблица общих строк. В xlsx текст ячейки хранится не в ячейке, а здесь —
 * ячейка несёт только индекс.
 *
 * Внутри `<si>` может быть несколько `<t>` (rich text, разбитый на куски с
 * разным оформлением) — их надо склеить. В наших файлах таких нет (0 из 25 990),
 * но склейка бесплатна, а потеря куска текста — нет.
 */
export function parseSharedStrings(xml: string): string[] {
  const out: string[] = [];
  for (const si of xml.matchAll(RE_SI)) {
    const inner = si[1] ?? "";
    let text = "";
    for (const t of inner.matchAll(RE_T)) text += decodeXmlText(t[1] ?? "");
    out.push(text);
  }
  return out;
}

/**
 * Ячейка: `<c r="B7" t="s"><v>123</v></c>` либо пустая `<c r="C7"/>`.
 *
 * Разбираем по адресу `r` каждой ячейки, а не по границам `<row>`: адрес несёт
 * и колонку, и номер строки, так что строки собираются сами и на разреженном
 * листе (у HolliHop 1 274 610 ячеек на 127 461 строку — то есть пустых полно).
 */
const RE_CELL = /<c\s+r="([A-Z]+)(\d+)"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
const RE_V = /<v>([\s\S]*?)<\/v>/;
const RE_ANY_CELL = /<c[\s/>]/g;

export interface SheetCell {
  column: string;
  row: number;
  value: string;
}

export function parseSheetCells(xml: string, shared: string[]): SheetCell[] {
  const cells: SheetCell[] = [];
  for (const m of xml.matchAll(RE_CELL)) {
    const [, column, rowRaw, attrs, body] = m;
    const type = /\bt="([^"]+)"/.exec(attrs ?? "")?.[1];
    let value: string;
    if (!body) {
      value = "";
    } else if (type === "s") {
      const index = Number(RE_V.exec(body)?.[1]);
      const text = shared[index];
      if (text === undefined) {
        throw new Error(`ячейка ${column}${rowRaw}: нет общей строки #${index}`);
      }
      value = text;
    } else if (type === "inlineStr") {
      let text = "";
      for (const t of body.matchAll(RE_T)) text += decodeXmlText(t[1] ?? "");
      value = text;
    } else if (type === undefined || type === "n" || type === "str") {
      // Число или формульная строка. HolliHop таких не присылает (0 из 64 779),
      // так что отдаём как есть, без интерпретации: додумывать формат числа —
      // это придумывать факт. Даты-серийники сюда же и попадут, поэтому:
      value = decodeXmlText(RE_V.exec(body)?.[1] ?? "");
    } else {
      // `b` (булево), `e` (ошибка), `d` (дата ISO) — в наших выгрузках их нет,
      // и молча превращать их в строку значит выдумывать. Лучше остановиться.
      throw new Error(`ячейка ${column}${rowRaw}: неподдерживаемый тип t="${type}"`);
    }
    cells.push({ column, row: Number(rowRaw), value });
  }

  // Страховка от тихой потери: если producer однажды напишет ячейку без `r`,
  // регулярка её пропустит, и строка приедет неполной — без единой ошибки.
  const total = (xml.match(RE_ANY_CELL) ?? []).length;
  if (total !== cells.length) {
    throw new Error(
      `разобрано ${cells.length} ячеек из ${total}: в листе есть ячейки без адреса`,
    );
  }
  return cells;
}

/** «A» → 0, «Z» → 25, «AA» → 26. */
export function columnIndex(letters: string): number {
  let index = 0;
  for (const ch of letters) index = index * 26 + (ch.charCodeAt(0) - 64);
  return index - 1;
}

/** Сколько непустых ячеек в строке. */
function filled(row: Map<number, string>): number {
  let n = 0;
  for (const value of row.values()) if (value.trim()) n++;
  return n;
}

/**
 * Ищет строку заголовков — первую, где непустых ячеек больше одной.
 *
 * ⚠️ Первая строка листа заголовками НЕ является, и это не редкий случай, а
 * формат HolliHop: в обоих файлах строка 1 — плашка с названием листа
 * («Коммуникации» / «Задачи») в единственной ячейке A1, а настоящая шапка
 * («Дата | Ученик | … | ИД ученика») стоит в строке 2.
 *
 * Прими мы строку 1 за шапку — ридер бы не упал: он бы вернул 127 460 строк с
 * единственной колонкой «Коммуникации», маппер не нашёл бы ни «Описания», ни
 * «ИД ученика», и импорт молча положил бы ноль задач, отчитавшись об успехе.
 * Поэтому правило проверяемое («больше одной непустой»), а не «строка 2».
 */
function findHeaderRow(byRow: Map<number, Map<number, string>>, lastRow: number): number {
  for (let r = 1; r <= lastRow; r++) {
    const row = byRow.get(r);
    if (row && filled(row) > 1) return r;
  }
  throw new Error("в листе нет строки заголовков: ни в одной строке нет двух непустых ячеек");
}

/**
 * Лист → строки-объекты, ключ — заголовок из шапки.
 *
 * Пустые строки не выбрасываются: у «Коммуникаций» в файле 127 461 строка, а
 * реальных 12 744 — хвост отсеет уже маппер (`communicationFromRow` возвращает
 * null), и это его дело, а не наше.
 */
export function sheetToObjects(cells: SheetCell[]): Record<string, string>[] {
  if (cells.length === 0) return [];
  const byRow = new Map<number, Map<number, string>>();
  let lastRow = 0;
  for (const cell of cells) {
    let row = byRow.get(cell.row);
    if (!row) byRow.set(cell.row, (row = new Map()));
    row.set(columnIndex(cell.column), cell.value);
    if (cell.row > lastRow) lastRow = cell.row;
  }

  const headerIndex = findHeaderRow(byRow, lastRow);
  const headers = new Map<number, string>();
  for (const [index, text] of byRow.get(headerIndex)!) {
    const name = text.trim();
    if (name) headers.set(index, name);
  }

  const out: Record<string, string>[] = [];
  for (let r = headerIndex + 1; r <= lastRow; r++) {
    const row = byRow.get(r);
    const object: Record<string, string> = {};
    for (const [index, name] of headers) object[name] = row?.get(index) ?? "";
    out.push(object);
  }
  return out;
}

/** Первый лист книги. Во всех выгрузках HolliHop лист ровно один. */
export function readXlsxRows(path: string): Record<string, string>[] {
  const buf = readFileSync(path);
  const entries = readZipEntries(
    buf,
    (name) => name === "xl/sharedStrings.xml" || /^xl\/worksheets\/sheet\d+\.xml$/.test(name),
  );

  const sheetNames = [...entries.keys()]
    .filter((name) => name.startsWith("xl/worksheets/"))
    .sort();
  if (sheetNames.length === 0) throw new Error(`${path}: в книге нет листов`);

  const sharedXml = entries.get("xl/sharedStrings.xml");
  const shared = sharedXml ? parseSharedStrings(xmlText(sharedXml)) : [];
  const cells = parseSheetCells(xmlText(entries.get(sheetNames[0])!), shared);
  return sheetToObjects(cells);
}
