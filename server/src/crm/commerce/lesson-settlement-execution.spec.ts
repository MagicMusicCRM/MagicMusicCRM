import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import {
  assertLessonSettleable,
  previewLessonSettlement,
  settleLesson,
} from "./lesson-settlement-execution";
import type { LessonSettlementSource } from "./lesson-settlement-facts.persistence";

function queryResult<T extends QueryResultRow>(rows: T[]): QueryResult<T> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows,
  };
}

function source(
  overrides: Partial<LessonSettlementSource> = {},
): LessonSettlementSource {
  return {
    lesson_id: "lesson-a",
    lifecycle_state: "successfully_completed",
    branch_id: "branch-a",
    teacher_id: "teacher-a",
    group_id: null,
    client_type: "student",
    client_id: "student-a",
    client_charge_type: "subscription",
    client_charge_value: "1",
    teacher_compensation_type: "fixed",
    teacher_compensation_value: "1000",
    subscription_id: "subscription-a",
    reservation_subscription_id: "subscription-a",
    reservation_state: "reserved",
    duration_minutes: 60,
    validation_state: "valid",
    participant_count: 0,
    ...overrides,
  };
}

function errorResponse(action: () => unknown): unknown {
  try {
    action();
  } catch (error) {
    if (error && typeof error === "object" && "getResponse" in error) {
      return (error as { getResponse(): unknown }).getResponse();
    }
    throw error;
  }
  throw new Error("Expected action to fail");
}

describe("lesson settlement execution", () => {
  it.each([
    ["duplicate subscriptions", true, "DUPLICATE_SUBSCRIPTION_SELECTION"],
    ["a subscription owned by another payer", false, "SUBSCRIPTION_CAPACITY"],
  ] as const)("rejects %s in a zero-unit planned preview", async (_name, duplicate, code) => {
    const clientIds = duplicate ? ["student-a", "student-b"] : ["student-a"];
    const client = {
      query: async (sql: string) => {
        if (sql.includes("from app.lessons lesson")) {
          return queryResult([source({
            group_id: duplicate ? "group-a" : null,
            participant_count: duplicate ? 2 : 0,
          })]);
        }
        if (sql.includes("from app.crm_configuration_revisions")) {
          return queryResult([{
            settlement_revision_id: "settlement-revision",
            compensation_revision_id: "compensation-revision",
            settlement_types: [{
              stableKey: "free_lesson", label: "Бесплатно", active: true,
              order: 0, allowedContexts: ["settle"], hourShareBasisPoints: 0,
              fixedPenaltyMinor: "0", colorToken: "neutral",
            }],
            compensation_rules: [{
              stableKey: "standard", label: "Полная ставка", active: true,
              order: 0, mode: "standard", value: "0",
            }],
          }]);
        }
        if (sql.includes("select student.id from app.students student")) {
          return queryResult([{ id: "payer-owner" }]);
        }
        if (sql.includes("select snapshot.client_type, snapshot.client_id")) {
          return queryResult(clientIds.map((clientId) => ({
            client_type: "student", client_id: clientId,
            charge_type: "subscription", charge_value: "1.00",
            subscription_id: `original-${clientId}`,
          })));
        }
        if (sql.includes("from app.lesson_participant_exclusions")) {
          return queryResult([]);
        }
        if (sql.includes("from app.subscriptions")) {
          return queryResult([{
            id: "selected-subscription", student_id: "different-owner",
            is_usable: true, has_capacity: true, available_units: "12.00",
          }]);
        }
        throw new Error(`Unexpected query in zero-unit preview: ${sql}`);
      },
    } as unknown as PoolClient;
    await expect(previewLessonSettlement(client, "lesson-a", {
      context: "settle",
      decision: {
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "standard",
        clientDecisions: clientIds.map((clientId) => ({
          clientId, chargeType: "subscription", payerStudentId: "payer-owner",
          subscriptionId: "selected-subscription",
        })),
      },
      configurationRevisionIds: {
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      },
    })).rejects.toMatchObject({ response: { code } });
  });

  it("maps reschedule and cancel contexts to their terminal lifecycle state", () => {
    expect(() =>
      assertLessonSettleable(
        source({ lifecycle_state: "rescheduled" }),
        "reschedule",
      ),
    ).not.toThrow();
    expect(() =>
      assertLessonSettleable(
        source({ lifecycle_state: "cancelled" }),
        "cancel",
      ),
    ).not.toThrow();
  });

  it("fails closed when the immutable snapshot is incomplete", () => {
    expect(
      errorResponse(() =>
        assertLessonSettleable(source({ teacher_id: null }), "settle"),
      ),
    ).toEqual({
      code: "LESSON_SETTLEMENT_SNAPSHOT_INCOMPLETE",
      lessonId: "lesson-a",
    });
  });

  it("returns an existing effective settlement without loading the lesson", async () => {
    const calls: string[] = [];
    const responses = [
      queryResult([]),
      queryResult([
        {
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
        },
      ]),
      queryResult([
        {
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
          configuration_revision_id: "compensation-revision",
        },
      ]),
    ];
    const client = {
      query: async (text: string) => {
        calls.push(text);
        return responses.shift()!;
      },
    } as unknown as PoolClient;

    await expect(settleLesson(client, "lesson-a")).resolves.toMatchObject({
      lessonId: "lesson-a",
      clientFact: { id: "client-fact-a" },
      teacherFact: { id: "teacher-fact-a" },
    });
    expect(calls).toHaveLength(3);
    expect(calls.some((text) => text.includes("from app.lessons lesson"))).toBe(
      false,
    );
  });
});
