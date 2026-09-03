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

function preMetadataFrozenCatalog(): LessonSettlementCatalog {
  const snapshot = buildCrmConfigurationBaseline([]);
  const paidMiss = snapshot.lessonSettlementTypes.find(
    (type) => type.stableKey === "paid_miss",
  )!;
  const {
    clientDurationMode: _clientDurationMode,
    teacherDurationMode: _teacherDurationMode,
    defaultTeacherCompensationRuleKey: _defaultTeacherCompensationRuleKey,
    ...legacyPaidMiss
  } = paidMiss;

  return {
    settlement_revision_id: "legacy-settlement-revision",
    compensation_revision_id: "legacy-compensation-revision",
    settlement_types: [
      legacyPaidMiss as unknown as LessonSettlementCatalog["settlement_types"][number],
    ],
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

  it("defaults an immutable pre-metadata frozen catalog", () => {
    expect(
      resolveSettlementPolicy(preMetadataFrozenCatalog(), "paid_miss"),
    ).toEqual({
      clientDurationMode: "full",
      teacherDurationMode: "full",
      teacherCompensationRuleKey: "standard",
    });
  });
});
