import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { deterministicUuid } from "./import-id";
import { formatReport, readArrayFile, runImport } from "./import-hollihop-exports";
import { buildXlsx } from "./xlsx-fixture";

/**
 * Выбор файла раздела. Выгрузки приходят в `.xlsx`, и до этого импортёр умел
 * только `.json` — то есть между файлом заказчика и базой стоял ручной шаг
 * конвертации.
 */
describe("readArrayFile", () => {
  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "hh-pick-"));
  });
  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("читает .xlsx как его отдаёт HolliHop", () => {
    writeFileSync(
      join(dir, "tasks.xlsx"),
      buildXlsx({
        title: "Задачи",
        headers: ["Дата выполнения", "Описание", "Клиент", "Ответственный"],
        rows: [["11.08.2027", "инфо задача", "Маг Анри", "[Для всех]"]],
      }),
    );
    expect(readArrayFile(dir, "tasks", "Tasks")).toEqual([
      {
        "Дата выполнения": "11.08.2027",
        "Описание": "инфо задача",
        "Клиент": "Маг Анри",
        "Ответственный": "[Для всех]",
      },
    ]);
  });

  it("читает .json — на нём стоят тесты и им скармливают правленый кусок", () => {
    writeFileSync(join(dir, "tasks.json"), JSON.stringify([{ "Клиент": "Маг Анри" }]), "utf8");
    expect(readArrayFile(dir, "tasks", "Tasks")).toEqual([{ "Клиент": "Маг Анри" }]);
  });

  it("разворачивает объект с корневым ключом", () => {
    writeFileSync(join(dir, "tasks.json"), JSON.stringify({ Tasks: [{ a: 1 }] }), "utf8");
    expect(readArrayFile(dir, "tasks", "Tasks")).toEqual([{ a: 1 }]);
  });

  it("нет файла — пустой раздел, а не падение", () => {
    expect(readArrayFile(dir, "tasks", "Tasks")).toEqual([]);
  });

  it("лежат оба — падает, а не угадывает, который свежее", () => {
    writeFileSync(join(dir, "tasks.json"), "[]", "utf8");
    writeFileSync(
      join(dir, "tasks.xlsx"),
      buildXlsx({ title: "Задачи", headers: ["Клиент", "Описание"], rows: [["Маг Анри", "x"]] }),
    );
    expect(() => readArrayFile(dir, "tasks", "Tasks")).toThrow(/который свежий/);
  });
});

/**
 * Прогон импортёра целиком — на настоящих строках выгрузки и фейковом клиенте.
 *
 * Мапперы покрыты отдельно; здесь проверяется то, что и ломалось: привязка к
 * человеку (ученик по id, лид по имени), честность отчёта о полноте и
 * идемпотентность повторного прогона.
 *
 * Задачи берутся ТОЛЬКО из «Коммуникаций» — файл «Задачи» не читается вовсе
 * (см. шапку импортёра: 532 его строки из 544 дублируют «Коммуникации», и
 * заливка обоих давала 1 281 лишнюю строку).
 */
describe("runImport", () => {
  // День снятия выгрузки. Якорь для дат без года у открытых задач; фиксирован,
  // потому что «сегодня» сделало бы тесты зависящими от дня прогона.
  const EXPORT_DATE = { day: 17, month: 7, year: 2026 };

  // Ученик, «уже импортированный» из API: id выведен из внешнего id ровно так
  // же, как это делал API-импорт.
  const STUDENT_ID = deterministicUuid("hollihop-student", "2512");
  const LEAD_ID = "lead-mag-anri";

  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "hh-exports-"));
  });
  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  const writeExport = (name: string, body: unknown) =>
    writeFileSync(join(dir, name), JSON.stringify(body), "utf8");

  /**
   * Фейковая база: знает одного ученика (по внешнему id) и один лид (по имени).
   * Всё остальное не находится — именно это и должно попасть в «unmatched».
   */
  const fakeClient = (options: { knowsUser?: boolean } = {}) => {
    const writes: { sql: string; values: unknown[] }[] = [];
    const query = jest.fn(async (sql: string, values?: unknown[]) => {
      const text = String(sql);
      if (text.startsWith("insert into")) {
        writes.push({ sql: text, values: values ?? [] });
        return { rows: [], rowCount: 1 };
      }
      if (text.includes("from app.students where id =")) {
        return values?.[0] === STUDENT_ID
          ? { rows: [{ id: STUDENT_ID }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      if (text.includes("from app.leads") && text.includes("concat_ws")) {
        return values?.[0] === "маг анри"
          ? { rows: [{ id: LEAD_ID }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      if (text.includes("from app.users")) {
        return options.knowsUser
          ? { rows: [{ id: "user-1" }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    });
    return { client: { query } as never, query, writes };
  };

  /**
   * Вставки в таблицу — разобранные в объект «колонка → значение».
   *
   * Именно по именам, а не по номеру в массиве: набор колонок зависит от того,
   * что импортёр решил записать (undefined он выбрасывает), так что позиция
   * поля — не свойство схемы, а случайность. Тест, привязанный к номеру, врёт
   * при первой же правке и ничего не объясняет тому, кто его читает.
   */
  const rowsOf = (table: string, writes: { sql: string; values: unknown[] }[]) =>
    writes
      .filter((w) => w.sql.includes(`insert into ${table}`))
      .map((w) => {
        const columns = /\(([^)]*)\)\s*\n?\s*values/i
          .exec(w.sql)![1]
          .split(",")
          .map((c) => c.trim());
        return Object.fromEntries(columns.map((c, i) => [c, w.values[i]])) as Record<
          string,
          unknown
        >;
      });

  const CLOSED_DESCRIPTION = [
    "уточнить, вернётся ли",
    "(поставил Богатырёва М. В. - 15.06)",
    'Статус "Закрыта" (установил Мазалова А. Ю.) - 21.06 14:14',
  ].join("\n");

  // Строки — из настоящей выгрузки (17.07), включая эталон заказчика «Маг Анри».
  const COMMUNICATIONS = {
    Communications: [
      {
        // Лид: «ИД ученика» пуст — он же ещё не ученик. Ищется по имени.
        "Дата": "11.08.2027",
        "Ученик": "Маг Анри",
        "Способ": "Сайт",
        "Направление": "Исходящая",
        "Описание":
          "инфо задача: если будут новые педагоги по вокалу, выслать визитку\n(поставил Мазалова А. Ю. - 21.06)",
        "ИД ученика": "",
      },
      {
        // Ученик по id + закрытая задача с историей.
        "Дата": "21.06.2026\n14:14",
        "Ученик": "Кивелиди Мария Владиславовна",
        "Способ": "Сайт",
        "Направление": "Исходящая",
        "Описание": CLOSED_DESCRIPTION,
        "ИД ученика": "2512",
      },
      {
        // Не задача: ни «поставил», ни статуса. Таких 52 из 12 744.
        "Дата": "01.07.2026",
        "Ученик": "Маг Анри",
        "Способ": "Звонок",
        "Направление": "Входящая",
        "Описание": "просто позвонил уточнить расписание",
        "ИД ученика": "",
      },
      {
        // Ни имени в базе, ни id — обязана попасть в отчёт, а не пропасть молча.
        "Дата": "05.07.2026",
        "Ученик": "Призрак Неизвестный",
        "Описание": "задача про несуществующего\n(поставил Мазалова А. Ю. - 01.07)",
        "ИД ученика": "",
      },
    ],
  };

  it("отчитывается честно: кто нашёлся, кто нет и почему", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client } = fakeClient();

    const run = await runImport({
      client,
      exportsDir: dir,
      mode: "dry_run",
      exportDate: EXPORT_DATE,
    });

    expect(run.reports.communications).toMatchObject({
      total: 4,
      matchedById: 3, // 2 лида по имени + 1 ученик по id
      unmatchedNoRecord: 1, // «Призрак» — ни имени, ни id
    });
    expect(run.unmatchedCommunications).toEqual([
      {
        name: "Призрак Неизвестный",
        reason: "имя не найдено среди лидов либо даёт несколько",
      },
    ]);
  });

  it("ученик ищется по внешнему id, лид — по имени", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client, writes } = fakeClient({ knowsUser: true });

    await runImport({ client, exportsDir: dir, mode: "apply", exportDate: EXPORT_DATE });

    const tasks = rowsOf("app.shared_tasks", writes);
    expect(tasks.map((t) => [t.linked_entity_type, t.linked_entity_id])).toEqual(
      expect.arrayContaining([
        ["lead", LEAD_ID],
        ["student", STUDENT_ID],
      ]),
    );
  });

  /**
   * Автор задачи — то самое поле, ради которого всё затевалось: на проде
   * created_by пуст у всех 514 задач.
   */
  it("проставляет автора задачи из текста «(поставил …)»", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client, writes } = fakeClient({ knowsUser: true });

    await runImport({ client, exportsDir: dir, mode: "apply", exportDate: EXPORT_DATE });

    const tasks = rowsOf("app.shared_tasks", writes);
    expect(tasks.length).toBeGreaterThan(0);
    for (const task of tasks) expect(task.created_by).toBe("user-1");
  });

  it("имя автора не нашлось — это ПЕЧАТАЕТСЯ, а не проглатывается в NULL", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client } = fakeClient({ knowsUser: false });

    const run = await runImport({
      client,
      exportsDir: dir,
      mode: "dry_run",
      exportDate: EXPORT_DATE,
    });

    expect(run.unmatchedResponsibles).toEqual(
      expect.arrayContaining(["Богатырёва М. В.", "Мазалова А. Ю."]),
    );
  });

  it("закрытая задача получает статус done, а не жёсткий open", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client, writes } = fakeClient({ knowsUser: true });

    await runImport({ client, exportsDir: dir, mode: "apply", exportDate: EXPORT_DATE });

    const states = rowsOf("app.shared_tasks", writes).map((t) => t.state);
    expect(states).toContain("closed");
    expect(states).toContain("open");
  });

  /**
   * История — вторая половина того, что искали: в API её нет, а в тексте есть.
   */
  it("кладёт историю закрытия с ИСХОДНОЙ датой и меткой источника", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client, writes } = fakeClient({ knowsUser: true });

    await runImport({ client, exportsDir: dir, mode: "apply", exportDate: EXPORT_DATE });

    const history = rowsOf("app.audit_events", writes);
    expect(history).toHaveLength(1);
    expect(history[0]).toMatchObject({
      action: "workflow.shared_task_legacy_status",
      created_at: "2026-06-21T14:14:00.000Z",
      actor_user_id: "user-1",
      metadata: '{"source":"hollihop"}',
      after_ref: '{"field":"status","value":"done"}',
    });
  });

  it("у закрытой задачи due_at пуст: дата строки — момент закрытия, а не срок", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client, writes } = fakeClient({ knowsUser: true });

    await runImport({ client, exportsDir: dir, mode: "apply", exportDate: EXPORT_DATE });

    const tasks = rowsOf("app.shared_tasks", writes);
    expect(tasks.find((t) => t.state === "closed")?.start_at).toBeNull();
    expect(tasks.find((t) => t.state === "open")?.start_at).toBe("2027-08-11T00:00:00.000Z");
  });

  it("не задача — ложится комментарием, а не задачей", async () => {
    writeExport("communications.json", COMMUNICATIONS);
    const { client, writes } = fakeClient({ knowsUser: true });

    await runImport({ client, exportsDir: dir, mode: "apply", exportDate: EXPORT_DATE });

    const bodies = rowsOf("app.entity_comments", writes).map((c) => c.body);
    expect(bodies).toContain("просто позвонил уточнить расписание");
  });

  /**
   * ⚠️ Ключ задачи не включает статус: сегодня открыта, завтра закрыта — и
   * следующая выгрузка породила бы ВТОРУЮ задачу вместо обновления первой.
   */
  it("повторный прогон не задваивает: id выводится из содержимого", async () => {
    writeExport("communications.json", COMMUNICATIONS);

    const first = fakeClient({ knowsUser: true });
    await runImport({
      client: first.client,
      exportsDir: dir,
      mode: "apply",
      exportDate: EXPORT_DATE,
    });
    const second = fakeClient({ knowsUser: true });
    await runImport({
      client: second.client,
      exportsDir: dir,
      mode: "apply",
      exportDate: EXPORT_DATE,
    });

    const ids = (w: { sql: string; values: unknown[] }[]) =>
      rowsOf("app.shared_tasks", w).map((t) => t.id);
    expect(ids(second.writes)).toEqual(ids(first.writes));
  });

  it("пропускает файлы, которых нет, а не падает", async () => {
    const { client } = fakeClient();
    const run = await runImport({
      client,
      exportsDir: dir,
      mode: "dry_run",
      exportDate: EXPORT_DATE,
    });
    expect(run.reports.communications.total).toBe(0);
    expect(run.reports.studentNotes.total).toBe(0);
  });

  it("заметки учеников по-прежнему ложатся", async () => {
    writeExport("students.json", {
      Students: [{ "ИД": "2512", "Фамилия": "Кивелиди", "Имя": "Мария", "Описание": "Заметка" }],
    });
    const { client, writes } = fakeClient();

    const run = await runImport({
      client,
      exportsDir: dir,
      mode: "apply",
      exportDate: EXPORT_DATE,
    });

    expect(run.reports.studentNotes).toMatchObject({ total: 1, matchedById: 1, written: 1 });
    expect(rowsOf("app.entity_comments", writes).map((c) => c.body)).toEqual(["Заметка"]);
  });
});

describe("formatReport", () => {
  const emptyRun = {
    reports: {
      communications: {
        total: 0,
        matchedById: 0,
        matchedByPhone: 0,
        unmatchedNoPhone: 0,
        unmatchedNoRecord: 0,
        written: 0,
        skippedDuplicate: 0,
      },
    },
    unmatchedResponsibles: [],
    unmatchedCommunications: [],
  };

  it("сухой прогон честно говорит, что ничего не записал", () => {
    expect(formatReport(emptyRun, "dry_run")).toContain("nothing written");
  });

  /**
   * 12 744 строки поимённо никто читать не станет — но «сколько и почему не
   * легло» обязано быть видно, иначе импорт снова окажется «успешным» молча.
   */
  it("группирует непривязанные строки по причине", () => {
    const report = formatReport(
      {
        ...emptyRun,
        unmatchedCommunications: [
          { name: "А", reason: "имя не найдено среди лидов либо даёт несколько" },
          { name: "Б", reason: "имя не найдено среди лидов либо даёт несколько" },
          { name: "В", reason: "ученика с ИД 7657 нет в базе" },
        ],
      },
      "apply",
    );
    expect(report).toContain("3 строк(и) «Коммуникаций» не привязаны");
    expect(report).toContain("2 — имя не найдено среди лидов либо даёт несколько");
    expect(report).toContain("1 — ученика с ИД 7657 нет в базе");
  });

  it("без непривязанных не пугает предупреждением", () => {
    expect(formatReport(emptyRun, "apply")).not.toContain("не привязаны");
  });
});
