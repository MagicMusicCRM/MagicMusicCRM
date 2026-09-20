import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import { loadLessonSettlementFacts } from "./lesson-settlement-facts.persistence";

function queryResult<T extends QueryResultRow>(rows: T[]): QueryResult<T> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows,
  };
}

function clientFact() {
  return {
    client_fact_id: "client-fact-a",
    client_type: "student",
    client_id: "student-a",
    charge_type: "subscription",
    client_snapshot_value: "1.00",
    subscription_id: "subscription-a",
    client_amount_minor: "0",
    units: "1.00",
    client_currency_code: "RUB",
    settlement_type_key: "completed",
    settlement_label: "Проведено",
    settlement_color_token: "success",
    hour_share_basis_points: 10_000,
    fixed_penalty_minor: "0",
    configuration_revision_id: "settlement-revision",
  };
}

function teacherFact() {
  return {
    teacher_fact_id: "teacher-fact-a",
    teacher_id: "teacher-a",
    compensation_type: "standard",
    teacher_snapshot_rate: "1000",
    rate_minor: "100000",
    duration_minutes: 60,
    teacher_amount_minor: "100000",
    teacher_currency_code: "RUB",
    compensation_rule_key: "standard",
    compensation_rule_label: "Стандарт",
    compensation_mode: "standard",
    compensation_default_value: "0",
    compensation_actual_value: "0",
    compensation_override_reason: null,
    compensation_source: "automatic",
    configuration_revision_id: "compensation-revision",
  };
}

function queuedClient(responses: QueryResult<QueryResultRow>[]): PoolClient {
  return {
    query: async () => responses.shift()!,
  } as unknown as PoolClient;
}

function errorResponse(error: unknown): unknown {
  if (error && typeof error === "object" && "getResponse" in error) {
    return (error as { getResponse(): unknown }).getResponse();
  }
  return error;
}

describe("lesson settlement facts persistence", () => {
  it("returns null when no effective fact exists", async () => {
    const client = queuedClient([queryResult([]), queryResult([])]);

    await expect(loadLessonSettlementFacts(client, "lesson-a")).resolves.toBeNull();
  });

  it("maps a complete effective client and teacher fact result", async () => {
    const client = queuedClient([
      queryResult([clientFact()]),
      queryResult([teacherFact()]),
    ]);

    await expect(
      loadLessonSettlementFacts(client, "lesson-a"),
    ).resolves.toMatchObject({
      lessonId: "lesson-a",
      clientFact: {
        id: "client-fact-a",
        clientId: "student-a",
        chargeType: "subscription",
        units: "1.00",
      },
      teacherFact: {
        id: "teacher-fact-a",
        teacherId: "teacher-a",
        amountMinor: "100000",
        compensationSource: "automatic",
      },
    });
  });

  it("preserves an explicit manual source even when the value matches the default", async () => {
    const client = queuedClient([
      queryResult([clientFact()]),
      queryResult([{ ...teacherFact(), compensation_source: "manual" }]),
    ]);

    await expect(
      loadLessonSettlementFacts(client, "lesson-a"),
    ).resolves.toMatchObject({
      teacherFact: {
        compensationActualValue: "0",
        compensationOverrideReason: null,
        compensationSource: "manual",
      },
    });
  });

  it.each([
    [null, "automatic"],
    ["Историческая ручная корректировка", "manual"],
  ] as const)(
    "uses the documented legacy source fallback for override reason %p",
    async (reason, expectedSource) => {
      const client = queuedClient([
        queryResult([clientFact()]),
        queryResult([{
          ...teacherFact(),
          compensation_source: null,
          compensation_override_reason: reason,
        }]),
      ]);

      await expect(
        loadLessonSettlementFacts(client, "lesson-a"),
      ).resolves.toMatchObject({
        teacherFact: { compensationSource: expectedSource },
      });
    },
  );

  it("fails closed when only one side of the settlement exists", async () => {
    const client = queuedClient([queryResult([clientFact()]), queryResult([])]);

    let caught: unknown;
    try {
      await loadLessonSettlementFacts(client, "lesson-a");
    } catch (error) {
      caught = error;
    }
    expect(errorResponse(caught)).toEqual({
      code: "PARTIAL_LESSON_SETTLEMENT",
      lessonId: "lesson-a",
    });
  });
});
