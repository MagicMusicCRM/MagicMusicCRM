import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import {
  loadLessonSettlementPlan,
  plannedLessonSubscriptionAllocations,
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
  it("plans subscription units from exact client minutes", async () => {
    const client = {
      query: async (text: string) => {
        if (text.includes("from app.crm_configuration_revisions")) {
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
        if (text.includes("select duration_minutes from app.lessons")) {
          return queryResult([{ duration_minutes: 60 }]);
        }
        if (text.includes("select snapshot.client_type, snapshot.client_id")) {
          return queryResult([{
            client_type: "student",
            client_id: "student-a",
            charge_type: "subscription",
            charge_value: "1",
            subscription_id: "subscription-a",
          }]);
        }
        if (text.includes("from app.lesson_participant_exclusions")) {
          return queryResult([]);
        }
        throw new Error(`Unexpected allocation query: ${text}`);
      },
    } as unknown as PoolClient;

    await expect(plannedLessonSubscriptionAllocations(
      client,
      "lesson-a",
      {
        decision: {
          settlementTypeKey: "partially_paid_lesson",
          teacherCompensationRuleKey: "percent",
          teacherCompensationValueMinor: "7500",
          teacherCreditedDurationMinutes: 45,
          teacherCompensationSource: "manual",
          clientDecisions: [{
            clientId: "student-a",
            subscriptionId: "subscription-a",
            chargeDurationMinutes: 30,
          }],
        },
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      },
    )).resolves.toEqual([{
      clientType: "student",
      clientId: "student-a",
      subscriptionId: "subscription-a",
      units: 0.5,
    }]);

    await expect(plannedLessonSubscriptionAllocations(
      client,
      "lesson-a",
      {
        decision: {
          settlementTypeKey: "partially_paid_lesson",
          teacherCompensationRuleKey: "percent",
          teacherCompensationValueMinor: "7500",
          teacherCreditedDurationMinutes: 45,
          teacherCompensationSource: "manual",
        },
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      },
    )).rejects.toMatchObject({
      status: 422,
      response: {
        code: "CLIENT_PARTIAL_DURATION_REQUIRED",
        field: "clientDecisions.student-a.chargeDurationMinutes",
      },
    });
  });

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
          teacherCreditedDurationMinutes: 60,
          teacherCompensationSource: "automatic",
        },
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      }),
    ).resolves.toBe(5);
    expect(calls).toHaveLength(2);
    expect(calls[0]!.values?.slice(0, 2)).toEqual(["lesson-a", 4]);
    expect(JSON.parse(String(calls[0]!.values?.[2]))).toMatchObject({
      teacherCreditedDurationMinutes: 60,
      teacherCompensationSource: "automatic",
    });
    expect(calls[1]!.text).toContain("lesson_settlement_plan_revisions");
    expect(calls[1]!.values?.slice(0, 2)).toEqual(["lesson-a", 5]);
  });
});
