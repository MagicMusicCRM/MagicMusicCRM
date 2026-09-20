import type { PoolClient, QueryResult, QueryResultRow } from "pg";
import type {
  LessonSettlementTypeConfig,
  TeacherCompensationRuleConfig,
} from "../crm-configuration.contracts";
import { buildCrmConfigurationBaseline } from "../crm-configuration-baseline";
import type { LessonFinancialDecision } from "./lesson-settlement.port";
import {
  assertPlannedLessonSettlementDecision,
  loadLessonSettlementCatalog,
  type LessonSettlementCatalog,
} from "./lesson-settlement-catalog";

function queryResult<T extends QueryResultRow>(rows: T[]): QueryResult<T> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows,
  };
}

function catalog(): LessonSettlementCatalog {
  return {
    settlement_revision_id: "settlement-revision",
    compensation_revision_id: "compensation-revision",
    settlement_types: [
      {
        stableKey: "completed",
        label: "Проведено",
        colorToken: "success",
        hourShareBasisPoints: 10_000,
        clientDurationMode: "full",
        teacherDurationMode: "full",
        defaultTeacherCompensationRuleKey: "percent",
        allowedContexts: ["settle"],
        active: true,
        order: 0,
      } satisfies LessonSettlementTypeConfig,
    ],
    compensation_rules: [
      {
        stableKey: "percent",
        label: "Процент",
        mode: "percent",
        value: "10000",
        active: true,
        order: 0,
      } satisfies TeacherCompensationRuleConfig,
    ],
  };
}

function decision(
  overrides: Partial<LessonFinancialDecision> = {},
): LessonFinancialDecision {
  return {
    settlementTypeKey: "completed",
    teacherCompensationRuleKey: "percent",
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

describe("lesson settlement catalog", () => {
  it("keeps the retired penalty lesson unavailable for new decisions", () => {
    const snapshot = buildCrmConfigurationBaseline([]);

    expect(
      snapshot.lessonSettlementTypes.find(
        (type) => type.stableKey === "penalty_lesson",
      )?.active,
    ).toBe(false);
  });

  it("loads an exact frozen revision pair through the supplied executor", async () => {
    const calls: Array<{ text: string; values?: unknown[] }> = [];
    const expected = catalog();
    const client = {
      query: async (text: string, values?: unknown[]) => {
        calls.push({ text, values });
        return queryResult([expected]);
      },
    } as unknown as PoolClient;

    await expect(
      loadLessonSettlementCatalog(client, "ignored-branch", {
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      }),
    ).resolves.toEqual(expected);
    expect(calls).toHaveLength(1);
    expect(calls[0]!.values).toEqual([
      "settlement-revision",
      "compensation-revision",
    ]);
  });

  it("loads the protected school catalog for an effective branch decision", async () => {
    const calls: Array<{ text: string; values?: unknown[] }> = [];
    const expected = catalog();
    const client = {
      query: async (text: string, values?: unknown[]) => {
        calls.push({ text, values });
        return queryResult([expected]);
      },
    } as unknown as PoolClient;

    await expect(
      loadLessonSettlementCatalog(client, "branch-a"),
    ).resolves.toEqual(expected);
    expect(calls).toHaveLength(1);
    expect(calls[0]!.values).toBeUndefined();
    expect(calls[0]!.text).not.toContain("branch.patch");
  });

  it("accepts an active planned decision", () => {
    expect(() =>
      assertPlannedLessonSettlementDecision(
        catalog(),
        decision({ teacherCompensationValueMinor: "20000" }),
      ),
    ).not.toThrow();
  });

  it("rejects an inactive or context-incompatible settlement type", () => {
    const input = catalog();
    input.settlement_types[0]!.allowedContexts = ["cancel"];

    expect(
      errorResponse(() =>
        assertPlannedLessonSettlementDecision(input, decision()),
      ),
    ).toEqual({
      code: "SETTLEMENT_TYPE_NOT_ALLOWED",
      field: "settlementTypeKey",
    });
  });

  it("rejects a percent override above 20000 basis points", () => {
    expect(
      errorResponse(() =>
        assertPlannedLessonSettlementDecision(
          catalog(),
          decision({ teacherCompensationValueMinor: "20001" }),
        ),
      ),
    ).toEqual({
      code: "INVALID_TEACHER_PERCENT",
      field: "teacherCompensationValueMinor",
    });
  });
});
