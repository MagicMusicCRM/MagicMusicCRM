import { buildCrmConfigurationBaseline } from "../crm-configuration-baseline";
import type { LessonSettlementCatalog } from "./lesson-settlement-catalog";
import { resolveSettlementPolicy } from "./lesson-settlement-policy";

function catalog(): LessonSettlementCatalog {
  const snapshot = buildCrmConfigurationBaseline([]);
  return {
    settlement_revision_id: "settlement-revision",
    compensation_revision_id: "compensation-revision",
    settlement_types: snapshot.lessonSettlementTypes,
    compensation_rules: snapshot.teacherCompensationRules,
  };
}

describe("resolveSettlementPolicy", () => {
  it.each([
    [
      "paid_miss",
      {
        clientDurationMode: "full",
        teacherDurationMode: "full",
        teacherCompensationRuleKey: "standard",
      },
    ],
    [
      "partially_paid_miss",
      {
        clientDurationMode: "manual",
        teacherDurationMode: "manual",
        teacherCompensationRuleKey: "percent",
      },
    ],
    [
      "unpaid_miss",
      {
        clientDurationMode: "zero",
        teacherDurationMode: "zero",
        teacherCompensationRuleKey: "none",
      },
    ],
  ])("resolves the approved policy for %s", (settlementTypeKey, expected) => {
    expect(resolveSettlementPolicy(catalog(), settlementTypeKey)).toEqual(
      expected,
    );
  });
});
