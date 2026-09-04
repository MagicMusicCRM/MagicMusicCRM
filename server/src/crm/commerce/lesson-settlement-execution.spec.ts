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
    [60, 0, 30, 0, "0.00", "0", "5000", "50000"],
    [60, 15, 60, 2_500, "0.25", "25000", "10000", "100000"],
    [60, 30, 45, 5_000, "0.50", "50000", "7500", "75000"],
    [60, 45, 0, 7_500, "0.75", "75000", "0", "0"],
    [60, 60, 60, 10_000, "1.00", "100000", "10000", "100000"],
    [90, 90, 45, 10_000, "1.50", "100000", "5000", "50000"],
  ] as const)(
    "uses the exact effective share for a %i-minute lesson with %i client minutes",
    async (
      durationMinutes,
      clientMinutes,
      teacherMinutes,
      expectedClientBasisPoints,
      expectedUnits,
      expectedPersonalAmount,
      expectedTeacherBasisPoints,
      expectedTeacherAmount,
    ) => {
    for (const funding of ["subscription", "personal_account"] as const) {
    const client = {
      query: async (sql: string) => {
        if (sql.includes("from app.lessons lesson")) {
          return queryResult([source({
            duration_minutes: durationMinutes,
            client_charge_type: funding,
            client_charge_value: funding === "subscription" ? "1" : "1000.00",
            subscription_id: funding === "subscription" ? "subscription-a" : null,
            reservation_subscription_id:
              funding === "subscription" ? "subscription-a" : null,
            reservation_state: funding === "subscription" ? "reserved" : null,
          })]);
        }
        if (sql.includes("from app.crm_configuration_revisions")) {
          return queryResult([{
            settlement_revision_id: "settlement-revision",
            compensation_revision_id: "compensation-revision",
            settlement_types: [{
              stableKey: "partially_paid_lesson",
              label: "Частично",
              active: true,
              order: 0,
              allowedContexts: ["settle"],
              hourShareBasisPoints: 2_500,
              clientDurationMode: "manual",
              teacherDurationMode: "manual",
              defaultTeacherCompensationRuleKey: "percent",
              fixedPenaltyMinor: "0",
              colorToken: "warning",
            }],
            compensation_rules: [{
              stableKey: "percent",
              label: "Процент",
              active: true,
              order: 0,
              mode: "percent",
              value: "5000",
            }],
          }]);
        }
        if (sql.includes("select snapshot.client_type, snapshot.client_id")) {
          return queryResult([{
            client_type: "student",
            client_id: "student-a",
            charge_type: funding,
            charge_value: funding === "subscription" ? "1" : "1000.00",
            subscription_id:
              funding === "subscription" ? "subscription-a" : null,
          }]);
        }
        if (sql.includes("from app.lesson_participant_exclusions")) {
          return queryResult([]);
        }
        if (sql.includes("where id = any")) {
          return queryResult([{
            id: "subscription-a",
            student_id: "student-a",
          }]);
        }
        if (sql.includes("where id = $1 for key share")) {
          return queryResult([{ student_id: "student-a" }]);
        }
        throw new Error(`Unexpected partial preview query: ${sql}`);
      },
    } as unknown as PoolClient;

    await expect(previewLessonSettlement(client, "lesson-a", {
      context: "settle",
      reasonText: "Согласована частичная оплата",
      decision: {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "percent",
        teacherCompensationValueMinor: Math.round(
          teacherMinutes * 10_000 / durationMinutes,
        ).toString(),
        teacherCreditedDurationMinutes: teacherMinutes,
        teacherCompensationSource: "manual",
        clientDecisions: [{
          clientId: "student-a",
          chargeType: funding,
          ...(funding === "personal_account"
            ? { basePriceMinor: "100000" }
            : { subscriptionId: "subscription-a" }),
          chargeDurationMinutes: clientMinutes,
        }],
      },
      configurationRevisionIds: {
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      },
    })).resolves.toMatchObject({
      clientFacts: [{
        hourShareBasisPoints: expectedClientBasisPoints,
        units: expectedUnits,
        amountMinor: funding === "personal_account"
          ? expectedPersonalAmount
          : "0",
      }],
      teacherFact: {
        compensationActualValue: expectedTeacherBasisPoints,
        amountMinor: expectedTeacherAmount,
        compensationSource: "manual",
      },
    });
    }
  });

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
        source({ lifecycle_state: "scheduled" }),
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

  it("does not replay an automatic fact as the same explicit manual decision", async () => {
    const responses = [
      queryResult([]),
      queryResult([{
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
      }]),
      queryResult([{
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
      }]),
      queryResult([]),
      queryResult([{ id: "subscription-a", student_id: "student-a" }]),
    ];
    const client = {
      query: async () => responses.shift()!,
    } as unknown as PoolClient;

    await expect(settleLesson(client, "lesson-a", {
      context: "settle",
      decision: {
        settlementTypeKey: "completed",
        teacherCompensationRuleKey: "standard",
        teacherCompensationSource: "manual",
      },
    })).rejects.toMatchObject({
      response: { code: "LESSON_ALREADY_SETTLED_WITH_DIFFERENT_DECISION" },
    });
  });

  it("rejects replay when the requested client duration changes the effective share", async () => {
    const responses = [
      queryResult([]),
      queryResult([{
        client_fact_id: "client-fact-a",
        client_type: "student",
        client_id: "student-a",
        charge_type: "none",
        client_snapshot_value: "0.00",
        subscription_id: null,
        client_amount_minor: "0",
        units: "0.00",
        client_currency_code: "RUB",
        settlement_type_key: "partially_paid_lesson",
        settlement_label: "Частично",
        settlement_color_token: "info",
        hour_share_basis_points: 2_500,
        fixed_penalty_minor: "0",
        configuration_revision_id: "settlement-revision",
      }]),
      queryResult([{
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
      }]),
      queryResult([]),
    ];
    const client = {
      query: async () => responses.shift()!,
    } as unknown as PoolClient;

    await expect(settleLesson(client, "lesson-a", {
      context: "settle",
      decision: {
        settlementTypeKey: "partially_paid_lesson",
        teacherCompensationRuleKey: "standard",
        teacherCompensationSource: "automatic",
        clientDecisions: [{
          clientId: "student-a",
          chargeType: "none",
          chargeDurationMinutes: 45,
        }],
      },
    })).rejects.toMatchObject({
      response: { code: "LESSON_ALREADY_SETTLED_WITH_DIFFERENT_DECISION" },
    });
  });
});
