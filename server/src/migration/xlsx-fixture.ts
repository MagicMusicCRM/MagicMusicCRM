// server/src/migration/xlsx-fixture.ts
//
// Сборка настоящего `.xlsx` в памяти — только для тестов (исключён из сборки в
// tsconfig.build.json).
//
// Зачем не «положить готовый файл в репозиторий»: выгрузки заказчика содержат
// ФИО и телефоны живых людей, и им не место в git. А проверять чтение xlsx на
// чём-то, что не является xlsx, — значит не проверять его вовсе.

import { crc32, deflateRawSync } from "node:zlib";

/**
 * Минимальный zip — но настоящий: с честной контрольной суммой.
 *
 * ⚠️ Она здесь не для красоты. В первой версии фикстура писала CRC=0, а ридер
 * его не проверял — пара согласилась друг с другом, тесты позеленели, и только
 * сторонний разборщик (python `zipfile`) сказал «Bad CRC-32». То есть фикстура
 * порождала файл, который не открылся бы ни в Excel, ни в чём угодно, кроме
 * нашего же кода, — и проверяла ровно ничего.
 */
export function buildZip(
  files: { name: string; data: Buffer; deflate?: boolean }[],
): Buffer {
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;

  for (const file of files) {
    const nameBuf = Buffer.from(file.name, "utf8");
    const method = file.deflate ? 8 : 0;
    const payload = file.deflate ? deflateRawSync(file.data) : file.data;

    const sum = crc32(file.data);

    const local = Buffer.alloc(30 + nameBuf.length);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(method, 8);
    local.writeUInt32LE(sum, 14);
    local.writeUInt32LE(payload.length, 18);
    local.writeUInt32LE(file.data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    nameBuf.copy(local, 30);

    const central = Buffer.alloc(46 + nameBuf.length);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(method, 10);
    central.writeUInt32LE(sum, 16);
    central.writeUInt32LE(payload.length, 20);
    central.writeUInt32LE(file.data.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt32LE(offset, 42);
    nameBuf.copy(central, 46);

    locals.push(local, payload);
    centrals.push(central);
    offset += local.length + payload.length;
  }

  const cd = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(files.length, 8);
  eocd.writeUInt16LE(files.length, 10);
  eocd.writeUInt32LE(cd.length, 12);
  eocd.writeUInt32LE(offset, 16);

  return Buffer.concat([...locals, cd, eocd]);
}

const escapeXml = (value: string): string =>
  value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

/**
 * Книга той же формы, что присылает HolliHop: строка 1 — плашка с названием
 * листа, строка 2 — шапка, дальше данные; весь текст через sharedStrings; файл
 * в CRLF, как его пишет Excel.
 */
export function buildXlsx(options: {
  title: string;
  headers: string[];
  rows: string[][];
}): Buffer {
  const { title, headers, rows } = options;

  const shared: string[] = [];
  const indexOf = (text: string): number => {
    const found = shared.indexOf(text);
    if (found >= 0) return found;
    shared.push(text);
    return shared.length - 1;
  };

  const letter = (index: number): string => {
    let out = "";
    for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) {
      out = String.fromCharCode(65 + ((n - 1) % 26)) + out;
    }
    return out;
  };

  const sheetRows: string[] = [];
  const cellsFor = (values: string[], rowNumber: number): string =>
    values
      .map((value, column) =>
        value === ""
          ? `<c r="${letter(column)}${rowNumber}"/>`
          : `<c r="${letter(column)}${rowNumber}" t="s"><v>${indexOf(value)}</v></c>`,
      )
      .join("");

  sheetRows.push(`<row r="1">${cellsFor([title], 1)}</row>`);
  sheetRows.push(`<row r="2">${cellsFor(headers, 2)}</row>`);
  rows.forEach((row, i) => {
    sheetRows.push(`<row r="${i + 3}">${cellsFor(row, i + 3)}</row>`);
  });

  const sheetXml =
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n` +
    `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` +
    `<sheetData>${sheetRows.join("")}</sheetData></worksheet>`;

  const sharedXml =
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n` +
    `<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${shared.length}">` +
    shared
      .map((text) => `<si><t xml:space="preserve">${escapeXml(text)}</t></si>`)
      .join("") +
    `</sst>`;

  return buildZip([
    { name: "xl/sharedStrings.xml", data: Buffer.from(sharedXml, "utf8"), deflate: true },
    { name: "xl/worksheets/sheet1.xml", data: Buffer.from(sheetXml, "utf8"), deflate: true },
  ]);
}
