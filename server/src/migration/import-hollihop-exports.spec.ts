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
 * Прогон импортёра целиком — на настоящих файлах выгрузки и фейковом клиенте.
 *
 * Мапперы покрыты отдельно; здесь проверяется то, что и ломалось в прошлый раз:
 * порядок матчинга (внешний id важнее телефона), честность отчёта о полноте и
 * идемпотентность повторного прогона.
 */
describe("runImport", () => {
  // Ученик и лид, «уже импортированные» из HolliHop: их id выведены из внешнего
  // id ровно так же, как это делал прежний API-импорт.
  const STUDENT_ID = deterministicUuid("hollihop-student", "1001");
  const LEAD_PHONE_ID = "lead-by-phone";
  const STUDENT_BY_PHONE_ID = "student-by-phone";

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
   * Фейковая база: знает одного ученика (по внешнему id) и один лид (по
   * телефону). Всё остальное не находится — именно это и должно попасть в
   * «unmatched».
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
      if (
        text.includes("from app.students s") &&
        text.includes("phone_normalized")
      ) {
        return values?.[0] === "+79165550000"
          ? { rows: [{ id: STUDENT_BY_PHONE_ID }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      if (text.includes("from app.leads") && text.includes("phone_normalized")) {
        return values?.[0] === "+79990000000"
          ? { rows: [{ id: LEAD_PHONE_ID }], rowCount: 1 }
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

  // ⚠️ Колонки id в выгрузке задач НЕТ вовсе — проверено на файле заказчика:
  // 0 из 527 строк. Поэтому здесь её нет и в фикстуре: задачи сопоставляются
  // телефоном, и это не фолбэк, а единственный доступный способ.
  const TASKS = {
    Tasks: [
      {
        Клиент: "Анна Иванова",
        "Моб. телефон": "+79165550000",
        Описание: "Позвонить (поставил Иванов И.И. - 12.03.2026)",
        "Дата выполнения": "18.03.2026 9:55",
        Ответственный: "[Для всех]",
      },
      {
        Клиент: "Олег Петров",
        Телефон: "89990000000",
        Описание: "Перезвонить",
        "Дата выполнения": "20.03.2026",
        Статус: "Выполнена",
      },
      {
        Клиент: "Без телефона",
        "Моб. телефон": "не указан",
        Описание: "Задача без телефона",
      },
      {
        Клиент: "Призрак",
        "Моб. телефон": "+79111111111",
        Описание: "Клиента нет в системе",
      },
    ],
  };

  it("отчитывается честно: кто нашёлся, кто нет и почему", async () => {
    writeExport("tasks.json", TASKS);
    const { client } = fakeClient();

    const run = await runImport({ client, exportsDir: dir, mode: "dry_run" });

    expect(run.reports.tasks).toEqual({
      total: 4,
      // У задач внешнего id нет — только телефон. «Анна» → ученик,
      // «Олег» → лид. Обе ветки важны: с одной только лидовой мутация в
      // ученической ветке проходила незамеченной.
      matchedById: 0,
      matchedByPhone: 2,
      unmatchedNoPhone: 1, // «не указан» не нормализуется
      unmatchedNoRecord: 1, // телефон валиден, но такого клиента нет
      written: 0, // сухой прогон
      skippedDuplicate: 0,
    });
  });

  it("ищет по внешнему id раньше телефона", async () => {
    // Проверяем на заметках ученика: у них id в выгрузке ЕСТЬ (колонка «ИД»),
    // в отличие от задач.
    writeExport("students.json", {
      Students: [
        {
          ИД: "1001",
          "ИД клиента": "9999", // ClientId — читать его нельзя, см. ниже
          Фамилия: "Иванова",
          Имя: "Анна",
          "Моб. телефон": "+79165550000",
          Описание: "Заметка",
        },
      ],
    });
    const { client, query } = fakeClient();

    await runImport({ client, exportsDir: dir, mode: "dry_run" });

    // Попадание по восстановленному из «ИД» ключу, а не по телефону: телефон
    // терял записи, и это чинилось именно так.
    const first = String(query.mock.calls[0][0]);
    expect(first).toContain("from app.students where id =");
    expect((query.mock.calls[0][1] as unknown[])[0]).toBe(STUDENT_ID);
  });

  it("не подставляет ClientId вместо Student.Id", async () => {
    // ⚠️ Первичный ключ выведен из Student.Id. У 113 из 1055 учеников
    // «ИД клиента» равен «ИД» ДРУГОГО ученика (проверено на проде: id 2512
    // как ClientId — Вероника Кочергина, как Student.Id — Мария Кивелиди).
    // Прими ClientId за Id — и заметка уедет в чужую карточку.
    writeExport("students.json", {
      Students: [
        {
          "ИД клиента": "1001", // только ClientId, «ИД» нет
          Фамилия: "Чужая",
          Имя: "Запись",
          "Моб. телефон": "не указан",
          Описание: "Не должна попасть к ученику 1001",
        },
      ],
    });
    const { client, query } = fakeClient();

    const run = await runImport({ client, exportsDir: dir, mode: "dry_run" });

    // Ключ ученика по «1001» не реконструировался — значит, и запроса не было.
    const probed = query.mock.calls.some((c) =>
      String(c[0]).includes("from app.students where id ="),
    );
    expect(probed).toBe(false);
    expect(run.reports.studentNotes.matchedById).toBe(0);
  });

  it("не пишет в базу в сухом прогоне", async () => {
    writeExport("tasks.json", TASKS);
    const { client, writes } = fakeClient();

    await runImport({ client, exportsDir: dir, mode: "dry_run" });

    expect(writes).toHaveLength(0);
  });

  it("достаёт автора из текста, когда колонка — «[Для всех]»", async () => {
    writeExport("tasks.json", TASKS);
    const { client } = fakeClient({ knowsUser: false });

    const run = await runImport({ client, exportsDir: dir, mode: "dry_run" });

    // Имя нашли в описании, пользователя по нему — нет. Это ПЕЧАТАЕТСЯ, а не
    // проглатывается в NULL: такую строку обязан увидеть человек.
    expect(run.unmatchedResponsibles).toEqual(["Иванов И.И."]);
  });

  it("проставляет исполнителя, когда такой сотрудник есть", async () => {
    writeExport("tasks.json", TASKS);
    const { client, writes } = fakeClient({ knowsUser: true });

    const run = await runImport({ client, exportsDir: dir, mode: "apply" });

    expect(run.unmatchedResponsibles).toEqual([]);
    const task = writes.find((w) => w.sql.includes("app.tasks"));
    expect(task?.values).toContain("user-1");
  });

  it("повторный прогон не задваивает: id выводится из содержимого", async () => {
    writeExport("tasks.json", TASKS);

    const first = fakeClient({ knowsUser: true });
    await runImport({ client: first.client, exportsDir: dir, mode: "apply" });
    const second = fakeClient({ knowsUser: true });
    await runImport({ client: second.client, exportsDir: dir, mode: "apply" });

    const idOf = (w: { sql: string; values: unknown[] }) => w.values[0];
    const firstIds = first.writes
      .filter((w) => w.sql.includes("app.tasks"))
      .map(idOf);
    const secondIds = second.writes
      .filter((w) => w.sql.includes("app.tasks"))
      .map(idOf);

    expect(firstIds).toEqual(secondIds);
    // Вставка идёт с on conflict do nothing, поэтому одинаковые id и означают
    // «прогнать дважды = прогнать один раз».
    expect(first.writes[0].sql).toContain("on conflict (id) do nothing");
  });

  it("пишет статус «Выполнена» вместо жёсткого open", async () => {
    writeExport("tasks.json", TASKS);
    const { client, writes } = fakeClient();

    await runImport({ client, exportsDir: dir, mode: "apply" });

    const oleg = writes.find(
      (w) => w.sql.includes("app.tasks") && w.values.includes("Перезвонить"),
    );
    expect(oleg?.values).toContain("done");
  });

  it("кладёт историю задачи с ИСХОДНОЙ датой и меткой источника", async () => {
    writeExport("tasks.json", TASKS);
    writeExport("task-history.json", {
      History: [
        {
          Клиент: "Анна Иванова",
          "Моб. телефон": "+79165550000",
          Описание: "Позвонить (поставил Иванов И.И. - 12.03.2026)",
          "Дата выполнения": "18.03.2026 9:55",
          "Дата изменения": "15.03.2026 10:00",
          Поле: "Срок",
          Было: "12.03.2026",
          Стало: "18.03.2026",
          Автор: "Иванов И.И.",
        },
      ],
    });
    const { client, writes } = fakeClient({ knowsUser: true });

    const run = await runImport({ client, exportsDir: dir, mode: "apply" });

    expect(run.reports.taskHistory.written).toBe(1);
    const history = writes.find((w) => w.sql.includes("app.task_history"));
    // Дата изменения — из выгрузки, а не «сейчас» (§2.2: «по датам и времени
    // выполнения»), поле переведено в наше имя, источник помечен.
    expect(history?.values).toContain("2026-03-15T10:00:00.000Z");
    expect(history?.values).toContain("due_at");
    expect(history?.values).toContain("hollihop");
  });

  it("не привязывает историю к задаче, которой нет в выгрузке", async () => {
    writeExport("task-history.json", {
      History: [
        {
          Клиент: "Кто-то",
          "Моб. телефон": "+79990000000",
          Описание: "Задача, которой нет в tasks.json",
          "Дата изменения": "15.03.2026 10:00",
          Поле: "Срок",
        },
      ],
    });
    const { client, writes } = fakeClient();

    const run = await runImport({ client, exportsDir: dir, mode: "apply" });

    expect(run.reports.taskHistory.unmatchedNoRecord).toBe(1);
    expect(writes).toHaveLength(0);
  });

  it("пропускает файлы, которых нет, а не падает", async () => {
    // Выгрузки возят по частям — отсутствие файла это норма.
    const { client } = fakeClient();

    const run = await runImport({ client, exportsDir: dir, mode: "dry_run" });

    expect(run.reports.tasks.total).toBe(0);
    expect(run.reports.leadComments.total).toBe(0);
  });

  it("разносит заметки ученика и комментарии лида по своим сторонам", async () => {
    writeExport("students.json", {
      Students: [
        {
          ИД: "1001", // Student.Id — кириллицей, как его пишет выгрузка
          Фамилия: "Иванова",
          Имя: "Анна",
          "Моб. телефон": "+79161234567",
          Описание: "Заметка про ученика",
        },
      ],
    });
    writeExport("leads.json", {
      Leads: [
        {
          ФИО: "Олег Петров",
          Телефон: "89990000000",
          Комментарий: "Звонил, думает",
          "Пользовательские поля": "Уровень: A1",
        },
      ],
    });
    const { client, writes } = fakeClient();

    const run = await runImport({ client, exportsDir: dir, mode: "apply" });

    expect(run.reports.studentNotes.written).toBe(1);
    expect(run.reports.leadComments.written).toBe(1);
    const kinds = writes
      .filter((w) => w.sql.includes("app.entity_comments"))
      .map((w) => w.values[1]);
    expect(kinds).toEqual(["student", "lead"]);
  });

  it("формирует отчёт, из которого видно, ПОЧЕМУ строка не легла", async () => {
    writeExport("tasks.json", TASKS);
    const { client } = fakeClient();

    const run = await runImport({ client, exportsDir: dir, mode: "dry_run" });
    const report = formatReport(run, "dry_run");

    expect(report).toContain("tasks: 4 row(s) in source");
    // У задач внешнего id нет — «by id 0» это не дефект, а свойство выгрузки.
    expect(report).toContain("matched:   2 (by id 0, by phone 2)");
    expect(report).toContain(
      "unmatched: 2 (no usable phone 1, no such record 1)",
    );
    expect(report).toContain("Dry run.");
  });
});
