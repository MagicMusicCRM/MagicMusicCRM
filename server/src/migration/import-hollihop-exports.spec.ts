import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { deterministicUuid } from "./import-id";
import { formatReport, runImport } from "./import-hollihop-exports";

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

  const TASKS = {
    Tasks: [
      {
        "ID клиента": "1001",
        Клиент: "Анна Иванова",
        "Моб. телефон": "+7 (916) 123-45-67",
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
        // Ученик без внешнего id в выгрузке — находится по телефону.
        Клиент: "Мария Сидорова",
        "Моб. телефон": "+79165550000",
        Описание: "Уточнить расписание",
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
      total: 5,
      matchedById: 1, // «Анна» — по внешнему id
      // «Олег» → лид по телефону, «Мария» → ученик по телефону. Обе ветки
      // фолбэка важны: с одной только лидовой мутация в ученической ветке
      // проходила незамеченной.
      matchedByPhone: 2,
      unmatchedNoPhone: 1, // «не указан» не нормализуется
      unmatchedNoRecord: 1, // телефон валиден, но такого клиента нет
      written: 0, // сухой прогон
      skippedDuplicate: 0,
    });
  });

  it("ищет по внешнему id раньше телефона", async () => {
    writeExport("tasks.json", TASKS);
    const { client, query } = fakeClient();

    await runImport({ client, exportsDir: dir, mode: "dry_run" });

    // Первый запрос по «Анне» — попадание по восстановленному id, а не по
    // телефону: телефон терял записи, и это чинилось именно так.
    const first = String(query.mock.calls[0][0]);
    expect(first).toContain("from app.students where id =");
    expect((query.mock.calls[0][1] as unknown[])[0]).toBe(STUDENT_ID);
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
    // проглатывается: молчание и есть причина, по которой у всех 514
    // импортированных задач assigned_to = NULL.
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
          "ID клиента": "1001",
          Клиент: "Анна Иванова",
          "Моб. телефон": "+7 (916) 123-45-67",
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
          "ID клиента": "1001",
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

    expect(report).toContain("tasks: 5 row(s) in source");
    expect(report).toContain("matched:   3 (by id 1, by phone 2)");
    expect(report).toContain(
      "unmatched: 2 (no usable phone 1, no such record 1)",
    );
    expect(report).toContain("Dry run.");
  });
});
