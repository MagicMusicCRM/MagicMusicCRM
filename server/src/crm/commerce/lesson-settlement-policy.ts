import type { SettlementDurationMode } from "../crm-configuration.contracts";
import type { LessonSettlementCatalog } from "./lesson-settlement-catalog";
import { invalidLessonSettlementDecision } from "./lesson-settlement-catalog";

export type { SettlementDurationMode } from "../crm-configuration.contracts";

export interface ResolvedSettlementPolicy {
  clientDurationMode: SettlementDurationMode;
  teacherDurationMode: SettlementDurationMode;
  teacherCompensationRuleKey: string;
}

export function resolveSettlementPolicy(
  catalog: LessonSettlementCatalog,
  settlementTypeKey: string,
): ResolvedSettlementPolicy {
  const type = catalog.settlement_types.find(
    (item) => item.active && item.stableKey === settlementTypeKey,
  );
  if (!type) {
    invalidLessonSettlementDecision(
      "SETTLEMENT_TYPE_NOT_ALLOWED",
      "settlementTypeKey",
    );
  }
  const legacyPolicy = resolveLegacySettlementPolicy(type.hourShareBasisPoints);
  return {
    clientDurationMode:
      type.clientDurationMode ?? legacyPolicy.clientDurationMode,
    teacherDurationMode:
      type.teacherDurationMode ?? legacyPolicy.teacherDurationMode,
    teacherCompensationRuleKey:
      type.defaultTeacherCompensationRuleKey ??
      legacyPolicy.teacherCompensationRuleKey,
  };
}

function resolveLegacySettlementPolicy(
  hourShareBasisPoints: number,
): ResolvedSettlementPolicy {
  if (hourShareBasisPoints === 0) {
    return {
      clientDurationMode: "zero",
      teacherDurationMode: "zero",
      teacherCompensationRuleKey: "none",
    };
  }
  if (hourShareBasisPoints === 10_000) {
    return {
      clientDurationMode: "full",
      teacherDurationMode: "full",
      teacherCompensationRuleKey: "standard",
    };
  }
  return {
    clientDurationMode: "manual",
    teacherDurationMode: "manual",
    teacherCompensationRuleKey: "percent",
  };
}
