// server/src/migration/xlsx-reader.spec.ts
//
// Тесты собирают zip прямо здесь, из байтов, — поэтому проверяется весь путь
// «файл → строки», а не кусок посередине. Формы ячеек и шапки взяты из
// настоящих выгрузок заказчика (17.07), а не выдуманы: выдуманные фикстуры уже
// один раз описали формат, которого в файле нет.

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildXlsx, buildZip } from "./xlsx-fixture";
import {
  columnIndex,
  decodeXmlText,
  parseSharedStrings,
  parseSheetCells,
  readXlsxRows,
  readZipEntries,
  sheetToObjects,
  xmlText,
  type SheetCell,
} from "./xlsx-reader";

const all = () => true;

describe("readZipEntries", () => {
  it("читает и stored, и deflate", () => {
    const zip = buildZip([
      { name: "a.txt", data: Buffer.from("простой", "utf8") },
      { name: "b.txt", data: Buffer.from("сжатый".repeat(50), "utf8"), deflate: true },
    ]);
    const entries = readZipEntries(zip, all);
    expect(entries.get("a.txt")?.toString("utf8")).toBe("простой");
    expect(entries.get("b.txt")?.toString("utf8")).toBe("сжатый".repeat(50));
  });

  it("читает только запрошенное: sheet1.xml у «Коммуникаций» — 36 МБ, распаковывать лишнее незачем", () => {
    const zip = buildZip([
      { name: "xl/sharedStrings.xml", data: Buffer.from("<sst/>", "utf8") },
      { name: "xl/theme/theme1.xml", data: Buffer.from("<theme/>", "utf8") },
    ]);
    const entries = readZipEntries(zip, (name) => name === "xl/sharedStrings.xml");
    expect([...entries.keys()]).toEqual(["xl/sharedStrings.xml"]);
  });

  it("находит EOCD, когда за ним есть комментарий архива", () => {
    const zip = buildZip([{ name: "a.txt", data: Buffer.from("x", "utf8") }]);
    const withComment = Buffer.concat([zip, Buffer.from("хвост-комментарий", "utf8")]);
    withComment.writeUInt16LE(Buffer.from("хвост-комментарий", "utf8").length, zip.length - 2);
    expect(readZipEntries(withComment, all).get("a.txt")?.toString()).toBe("x");
  });

  it("не zip — внятная ошибка, а не пустой результат", () => {
    expect(() => readZipEntries(Buffer.from("это не архив"), all)).toThrow(
      /не нашёл End of Central Directory/,
    );
  });

  it("падает на zip64, а не читает половину архива", () => {
    const zip = buildZip([{ name: "a.txt", data: Buffer.from("x", "utf8") }]);
    zip.writeUInt16LE(0xffff, zip.length - 12); // entries_total = маркер zip64
    expect(() => readZipEntries(zip, all)).toThrow(/zip64/);
  });

  it("падает на битой контрольной сумме: длина ловит обрыв, но не порчу байта", () => {
    const zip = buildZip([{ name: "a.txt", data: Buffer.from("привет", "utf8") }]);
    const central = zip.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
    zip.writeUInt32LE(12345, central + 16);
    expect(() => readZipEntries(zip, all)).toThrow(/контрольная сумма не сошлась/);
  });

  it("падает, если распаковалось не столько байт, сколько обещал каталог", () => {
    const zip = buildZip([{ name: "a.txt", data: Buffer.from("привет", "utf8") }]);
    // Портим ожидаемый размер в центральном каталоге.
    const central = zip.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
    zip.writeUInt32LE(999, central + 24);
    expect(() => readZipEntries(zip, all)).toThrow(/вместо 999/);
  });
});

describe("xmlText", () => {
  // Excel пишет файл в CRLF: в «Коммуникациях» 45 691 литеральный CR-байт и ни
  // одной ссылки &#13;. XML 1.0 §2.11 обязывает привести их к \n — иначе \r
  // приезжает внутрь 12 212 ячеек.
  it("приводит литеральные CRLF к \\n", () => {
    expect(xmlText(Buffer.from("<t>первая\r\nвторая</t>", "utf8"))).toBe(
      "<t>первая\nвторая</t>",
    );
  });

  it("приводит и одиночный CR", () => {
    expect(xmlText(Buffer.from("a\rb", "utf8"))).toBe("a\nb");
  });

  it("ссылку &#13; НЕ трогает: спека нормализует только литеральные символы", () => {
    // Порядок важен: нормализация — до decodeXmlText, иначе осознанно
    // записанный автором CR схлопнулся бы вместе с вёрсткой файла.
    expect(decodeXmlText(xmlText(Buffer.from("a&#13;b", "utf8")))).toBe("a\rb");
  });
});

describe("decodeXmlText", () => {
  it("разворачивает именованные сущности", () => {
    expect(decodeXmlText("&lt;тег&gt; &amp; &quot;кавычки&quot; &apos;")).toBe(
      `<тег> & "кавычки" '`,
    );
  });

  it("разворачивает числовые — десятичные и шестнадцатеричные", () => {
    expect(decodeXmlText("строка&#10;ещё")).toBe("строка\nещё");
    expect(decodeXmlText("&#x41;&#x42;")).toBe("AB");
  });

  it("неизвестную сущность оставляет как есть", () => {
    expect(decodeXmlText("&nbsp;")).toBe("&nbsp;");
  });
});

describe("parseSharedStrings", () => {
  it("собирает строки по порядку", () => {
    expect(parseSharedStrings("<sst><si><t>Дата</t></si><si><t>Ученик</t></si></sst>")).toEqual([
      "Дата",
      "Ученик",
    ]);
  });

  it("склеивает несколько <t> внутри одного <si> (rich text)", () => {
    expect(parseSharedStrings("<sst><si><r><t>Маг </t></r><r><t>Анри</t></r></si></sst>")).toEqual([
      "Маг Анри",
    ]);
  });

  it("бережёт xml:space=preserve: ведущий пробел — часть значения", () => {
    // 307 ячеек «Описания» реально начинаются с пробела или перевода строки.
    // Обрезать их — дело маппера (`str()` уже делает trim), а не ридера.
    expect(parseSharedStrings('<sst><si><t xml:space="preserve"> уточнить</t></si></sst>')).toEqual([
      " уточнить",
    ]);
  });

  it("пустая <si/> — это пустая строка, а не пропуск", () => {
    expect(parseSharedStrings("<sst><si><t>a</t></si><si/><si><t>b</t></si></sst>")).toEqual([
      "a",
      "",
      "b",
    ]);
  });
});

describe("parseSheetCells", () => {
  const shared = ["Дата", "Маг Анри", "инфо задача"];

  it("читает t=\"s\" через таблицу общих строк", () => {
    expect(parseSheetCells('<row><c r="A1" t="s"><v>1</v></c></row>', shared)).toEqual([
      { column: "A", row: 1, value: "Маг Анри" },
    ]);
  });

  it("пустая самозакрытая ячейка — пустое значение", () => {
    expect(parseSheetCells('<row><c r="B3"/></row>', shared)).toEqual([
      { column: "B", row: 3, value: "" },
    ]);
  });

  it("читает многобуквенные колонки", () => {
    expect(parseSheetCells('<c r="AB12" t="s"><v>0</v></c>', shared)).toEqual([
      { column: "AB", row: 12, value: "Дата" },
    ]);
  });

  it("читает inlineStr", () => {
    expect(parseSheetCells('<c r="A1" t="inlineStr"><is><t>текст</t></is></c>', shared)).toEqual([
      { column: "A", row: 1, value: "текст" },
    ]);
  });

  it("число отдаёт как есть, без интерпретации", () => {
    expect(parseSheetCells('<c r="A1"><v>2512</v></c>', shared)).toEqual([
      { column: "A", row: 1, value: "2512" },
    ]);
  });

  it("падает на битой ссылке в таблице общих строк", () => {
    expect(() => parseSheetCells('<c r="A1" t="s"><v>99</v></c>', shared)).toThrow(
      /нет общей строки #99/,
    );
  });

  it("падает на неподдерживаемом типе, а не выдумывает значение", () => {
    // Булево/ошибка/дата в выгрузках HolliHop не встречаются (0 из 64 779).
    // Появятся — лучше остановиться, чем импортировать догадку.
    expect(() => parseSheetCells('<c r="A1" t="b"><v>1</v></c>', shared)).toThrow(/t="b"/);
  });

  it("падает, если в листе есть ячейка без адреса — иначе строка тихо приедет неполной", () => {
    expect(() => parseSheetCells('<c r="A1" t="s"><v>0</v></c><c t="s"><v>1</v></c>', shared)).toThrow(
      /ячейки без адреса/,
    );
  });
});

describe("columnIndex", () => {
  it.each([
    ["A", 0],
    ["B", 1],
    ["J", 9],
    ["Z", 25],
    ["AA", 26],
    ["AB", 27],
  ])("%s → %i", (letters, index) => {
    expect(columnIndex(letters)).toBe(index);
  });
});

describe("sheetToObjects", () => {
  const cell = (column: string, row: number, value: string): SheetCell => ({ column, row, value });

  /**
   * Главный тест файла. Строка 1 в выгрузках HolliHop — плашка с названием
   * листа в единственной ячейке A1, шапка стоит в строке 2. Прими мы строку 1
   * за шапку — ридер не упал бы: вернул бы 127 460 строк с одной колонкой
   * «Коммуникации», маппер не нашёл бы ни «Описания», ни «ИД ученика», и импорт
   * молча положил бы ноль задач, отчитавшись об успехе.
   */
  it("пропускает строку-плашку и берёт шапкой первую строку с двумя непустыми", () => {
    const rows = sheetToObjects([
      cell("A", 1, "Коммуникации"),
      cell("A", 2, "Дата"),
      cell("B", 2, "Ученик"),
      cell("J", 2, "ИД ученика"),
      cell("A", 3, "11.08.2027"),
      cell("B", 3, "Маг Анри"),
      cell("J", 3, ""),
    ]);
    expect(rows).toEqual([{ "Дата": "11.08.2027", "Ученик": "Маг Анри", "ИД ученика": "" }]);
  });

  it("колонки, которых в строке нет, — пустые, а не undefined", () => {
    const rows = sheetToObjects([
      cell("A", 1, "Дата"),
      cell("B", 1, "Ученик"),
      cell("A", 2, "11.08.2027"),
    ]);
    expect(rows).toEqual([{ "Дата": "11.08.2027", "Ученик": "" }]);
  });

  it("пустой хвост не выбрасывает: 127 459 строк в файле, 12 744 реальных — отсев за маппером", () => {
    const rows = sheetToObjects([
      cell("A", 1, "Дата"),
      cell("B", 1, "Ученик"),
      cell("A", 2, "11.08.2027"),
      cell("B", 2, "Маг Анри"),
      cell("A", 5, ""),
    ]);
    expect(rows).toHaveLength(4);
    expect(rows[3]).toEqual({ "Дата": "", "Ученик": "" });
  });

  it("падает, если шапки нет вовсе", () => {
    expect(() => sheetToObjects([cell("A", 1, "Коммуникации")])).toThrow(
      /нет строки заголовков/,
    );
  });

  it("пустой лист — пустой результат", () => {
    expect(sheetToObjects([])).toEqual([]);
  });
});

describe("readXlsxRows", () => {
  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "xlsx-"));
  });
  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  const write = (name: string, buf: Buffer): string => {
    const path = join(dir, name);
    writeFileSync(path, buf);
    return path;
  };

  /**
   * Сквозной прогон на форме настоящих «Коммуникаций»: плашка в строке 1, шапка
   * в строке 2, многострочное «Описание», пустой «ИД ученика» у лида.
   *
   * Строки — из выгрузки заказчика (17.07), включая «Маг Анри»: у него «ИД
   * ученика» действительно пуст, потому что он лид, а не ученик.
   */
  it("читает книгу целиком — от байтов до строк", () => {
    const path = write(
      "communications.xlsx",
      buildXlsx({
        title: "Коммуникации",
        headers: ["Дата", "Ученик", "Способ", "Описание", "ИД ученика"],
        rows: [
          [
            "11.08.2027",
            "Маг Анри",
            "Сайт",
            "инфо задача: если будут новые педагоги по вокалу\n(поставил Мазалова А. Ю. - 21.06)",
            "",
          ],
          ["18.01.2027", "Кивелиди Мария Владиславовна", "Сайт", "летом 26 не готова вернуться", "2512"],
        ],
      }),
    );

    expect(readXlsxRows(path)).toEqual([
      {
        "Дата": "11.08.2027",
        "Ученик": "Маг Анри",
        "Способ": "Сайт",
        "Описание":
          "инфо задача: если будут новые педагоги по вокалу\n(поставил Мазалова А. Ю. - 21.06)",
        "ИД ученика": "",
      },
      {
        "Дата": "18.01.2027",
        "Ученик": "Кивелиди Мария Владиславовна",
        "Способ": "Сайт",
        "Описание": "летом 26 не готова вернуться",
        "ИД ученика": "2512",
      },
    ]);
  });

  it("книга без листов — внятная ошибка", () => {
    const path = write(
      "empty.xlsx",
      buildZip([{ name: "xl/sharedStrings.xml", data: Buffer.from("<sst/>", "utf8") }]),
    );
    expect(() => readXlsxRows(path)).toThrow(/нет листов/);
  });
});
