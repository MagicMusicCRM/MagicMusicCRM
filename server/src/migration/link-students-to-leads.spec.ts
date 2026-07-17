// server/src/migration/link-students-to-leads.spec.ts

import { formatLinkReport, runLink, type LinkRun } from "./link-students-to-leads";

/**
 * Фейковая база: отвечает на два запроса скрипта — «сколько ждут связи» и
 * «кандидаты», — и запоминает записи.
 */
function fakeClient(options: {
  waiting: number;
  candidates: { student_id: string; name: string; phone: string | null; lead_ids: string[] }[];
  /** Ученики, которых update не найдёт: связь появилась между чтением и записью. */
  raced?: string[];
}) {
  const writes: { studentId: string; leadId: string }[] = [];
  const client = {
    query: jest.fn(async (sql: string, values?: unknown[]) => {
      if (/count\(\*\)::int as n/.test(sql)) return { rows: [{ n: options.waiting }], rowCount: 1 };
      if (/^\s*update app\.students/.test(sql)) {
        const [studentId, leadId] = values as [string, string];
        if (options.raced?.includes(studentId)) return { rows: [], rowCount: 0 };
        writes.push({ studentId, leadId });
        return { rows: [{ id: studentId }], rowCount: 1 };
      }
      return { rows: options.candidates, rowCount: options.candidates.length };
    }),
  };
  return { client: client as never, writes };
}

const student = (
  id: string,
  name: string,
  leadIds: string[],
  phone: string | null = "+79161037743",
) => ({ student_id: id, name, phone, lead_ids: leadIds });

describe("runLink", () => {
  it("связывает ученика, под которого подошёл ровно один лид", async () => {
    const { client, writes } = fakeClient({
      waiting: 1,
      candidates: [student("s-1", "Маг Анри", ["lead-1"])],
    });

    const run = await runLink({ client, mode: "apply" });

    expect(writes).toEqual([{ studentId: "s-1", leadId: "lead-1" }]);
    expect(run).toMatchObject({ candidates: 1, unambiguous: 1, ambiguous: 0, unmatched: 0, linked: 1 });
  });

  /**
   * Главное правило файла. Под ученика подошло два лида — это дубли лида в
   * HolliHop (16 случаев из 996). Взять «первый попавшийся» значит склеить
   * историю двух разных людей, а это не чинится.
   */
  it("НЕ связывает, когда подошло несколько лидов, — и показывает их человеку", async () => {
    const { client, writes } = fakeClient({
      waiting: 1,
      candidates: [student("s-1", "Кивелиди Мария", ["lead-1", "lead-2"])],
    });

    const run = await runLink({ client, mode: "apply" });

    expect(writes).toEqual([]);
    expect(run).toMatchObject({ unambiguous: 0, ambiguous: 1, linked: 0 });
    expect(run.ambiguousList).toEqual([
      {
        studentId: "s-1",
        name: "Кивелиди Мария",
        phone: "+79161037743",
        leadIds: ["lead-1", "lead-2"],
      },
    ]);
  });

  it("считает тех, под кого не нашлось ни одного лида: молчание о них и есть прошлая беда", async () => {
    // 5 ждут связи, кандидатов только 2 → трое не сопоставились.
    const { client } = fakeClient({
      waiting: 5,
      candidates: [student("s-1", "Маг Анри", ["lead-1"]), student("s-2", "Луканюк Вероника", ["lead-2"])],
    });

    const run = await runLink({ client, mode: "apply" });

    expect(run).toMatchObject({ candidates: 5, unambiguous: 2, unmatched: 3, linked: 2 });
  });

  it("сухой прогон считает, но не пишет", async () => {
    const { client, writes } = fakeClient({
      waiting: 2,
      candidates: [student("s-1", "Маг Анри", ["lead-1"]), student("s-2", "Кивелиди Мария", ["a", "b"])],
    });

    const run = await runLink({ client, mode: "dry_run" });

    expect(writes).toEqual([]);
    expect(run).toMatchObject({ unambiguous: 1, ambiguous: 1, linked: 0 });
  });

  /**
   * `linked` считает то, что вернул update, а не намерение: если между чтением и записью
   * связь у ученика появилась, `lead_id is null` в update не сработает, и
   * отчёт обязан это показать, а не отрапортовать записанное.
   */
  it("не засчитывает связь, которую update не сделал", async () => {
    const { client } = fakeClient({
      waiting: 2,
      candidates: [student("s-1", "Маг Анри", ["lead-1"]), student("s-2", "Луканюк Вероника", ["lead-2"])],
      raced: ["s-2"],
    });

    const run = await runLink({ client, mode: "apply" });

    expect(run).toMatchObject({ unambiguous: 2, linked: 1 });
  });

  it("связывать некого — пустой отчёт без падения", async () => {
    const { client } = fakeClient({ waiting: 0, candidates: [] });
    const run = await runLink({ client, mode: "apply" });
    expect(run).toMatchObject({ candidates: 0, unambiguous: 0, ambiguous: 0, unmatched: 0, linked: 0 });
  });
});

describe("formatLinkReport", () => {
  const run: LinkRun = {
    candidates: 996,
    unambiguous: 980,
    ambiguous: 16,
    unmatched: 0,
    linked: 980,
    ambiguousList: [
      { studentId: "s-1", name: "Кивелиди Мария", phone: "+79161037743", leadIds: ["l-1", "l-2"] },
    ],
  };

  it("печатает неоднозначных поимённо: их разбирает человек", () => {
    const report = formatLinkReport(run, "apply");
    expect(report).toContain("Кивелиди Мария");
    expect(report).toContain("l-1, l-2");
    expect(report).toContain("выберите нужный лид руками");
  });

  it("сухой прогон честно говорит, что ничего не записал", () => {
    expect(formatLinkReport({ ...run, linked: 0 }, "dry_run")).toContain("ничего не записано");
  });

  it("без неоднозначных не пугает предупреждением", () => {
    const report = formatLinkReport({ ...run, ambiguous: 0, ambiguousList: [] }, "apply");
    expect(report).not.toContain("⚠️");
  });

  it("у ученика без телефона печатает это, а не пустоту", () => {
    const report = formatLinkReport(
      { ...run, ambiguousList: [{ studentId: "s", name: "Без телефона", phone: null, leadIds: ["a", "b"] }] },
      "apply",
    );
    expect(report).toContain("(без телефона)");
  });
});
