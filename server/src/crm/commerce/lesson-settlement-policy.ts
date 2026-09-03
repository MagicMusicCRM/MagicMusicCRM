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
  return {
    clientDurationMode: type.clientDurationMode,
    teacherDurationMode: type.teacherDurationMode,
    teacherCompensationRuleKey: type.defaultTeacherCompensationRuleKey,
  };
}
