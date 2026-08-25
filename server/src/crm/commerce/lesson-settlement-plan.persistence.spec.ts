import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import {
  loadLessonSettlementPlan,
  replaceLessonSettlementPlan,
} from "./lesson-settlement-plan.persistence";

function queryResult<T extends QueryResultRow>(rows: T[]): QueryResult<T> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows,
  };
}

describe("lesson settlement plan persistence", () => {
  it("loads and maps a plan with the requested row lock", async () => {
    const calls: Array<{ text: string; values?: unknown[] }> = [];
    const client = {
      query: async (text: string, values?: unknown[]) => {
        calls.push({ text, values });
        return queryResult([
          {
            lesson_id: "lesson-a",
            decision: {
              settlementTypeKey: "completed",
              teacherCompensationRuleKey: "standard",
            },
            settlement_revision_id: "settlement-revision",
            compensation_revision_id: "compensation-revision",
            version: "4",
            state: "planned",
            reason_text: "Проверка",
          },
        ]);
      },
    } as unknown as PoolClient;

    await expect(
      loadLessonSettlementPlan(client, "lesson-a", true),
    ).resolves.toEqual({
      lessonId: "lesson-a",
      decision: {
        settlementTypeKey: "completed",
        teacherCompensationRuleKey: "standard",
      },
      settlementRevisionId: "settlement-revision",
      compensationRevisionId: "compensation-revision",
      version: 4,
      state: "planned",
      reasonText: "Проверка",
    });
    expect(calls[0]!.text).toContain("for update");
    expect(calls[0]!.values).toEqual(["lesson-a"]);
  });

  it("updates the expected version and appends its immutable revision", async () => {
    const calls: Array<{ text: string; values?: unknown[] }> = [];
    const responses = [queryResult([{ version: "5" }]), queryResult([])];
    const client = {
      query: async (text: string, values?: unknown[]) => {
        calls.push({ text, values });
        return responses.shift()!;
      },
    } as unknown as PoolClient;

    await expect(
      replaceLessonSettlementPlan(client, {
        lessonId: "lesson-a",
        expectedVersion: 4,
        selectedBy: "actor-a",
        reasonText: "Исправление",
        decision: {
          settlementTypeKey: "completed",
          teacherCompensationRuleKey: "standard",
        },
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      }),
    ).resolves.toBe(5);
    expect(calls).toHaveLength(2);
    expect(calls[0]!.values?.slice(0, 2)).toEqual(["lesson-a", 4]);
    expect(calls[1]!.text).toContain("lesson_settlement_plan_revisions");
    expect(calls[1]!.values?.slice(0, 2)).toEqual(["lesson-a", 5]);
  });
});
