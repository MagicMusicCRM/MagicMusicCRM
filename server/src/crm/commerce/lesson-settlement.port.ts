import { PoolClient } from "pg";

export type ClientChargeFactType =
  | "subscription"
  | "personal_account"
  | "none";

export type TeacherCompensationFactType =
  | "none"
  | "standard"
  | "percent"
  | "fixed"
  | "hourly";

export type LessonSettlementContext = "settle" | "reschedule" | "cancel";

export interface LessonFinancialDecision {
  settlementTypeKey: string;
  clientDecisions?: Array<{
    clientId: string;
    settlementTypeKey?: string;
    subscriptionId?: string;
  }>;
  teacherCompensationRuleKey: string;
  teacherCompensationValueMinor?: string;
}

export interface PreparedLessonSettlementPlan {
  decision: LessonFinancialDecision;
  settlementRevisionId: string;
  compensationRevisionId: string;
}

export interface PlannedSubscriptionAllocation {
  clientType: "lead" | "student";
  clientId: string;
  subscriptionId: string;
  units: number;
}

export interface StoredLessonSettlementPlan
  extends PreparedLessonSettlementPlan {
  lessonId: string;
  version: number;
  state: "planned" | "settled" | "review_required" | "cancelled";
  reasonText: string | null;
}

export interface LessonSettlementInput {
  context: LessonSettlementContext;
  decision: LessonFinancialDecision;
  reasonText?: string;
  configurationRevisionIds?: {
    settlementRevisionId: string;
    compensationRevisionId: string;
  };
  correction?: {
    id: string;
  };
}

export interface LessonSettlementResult {
  lessonId: string;
  clientFacts: Array<{
    id: string;
    clientType: "lead" | "student";
    clientId: string;
    chargeType: ClientChargeFactType;
    snapshotValue: string;
    subscriptionId: string | null;
    amountMinor: string;
    units: string;
    currencyCode: string;
    settlementTypeKey: string | null;
    settlementLabel: string | null;
    settlementColorToken: string | null;
    hourShareBasisPoints: number | null;
    fixedPenaltyMinor: string | null;
    configurationRevisionId: string | null;
  }>;
  /** First fact retained for compatibility with individual-lesson callers. */
  clientFact: LessonSettlementResult["clientFacts"][number];
  teacherFact: {
    id: string;
    teacherId: string;
    compensationType: TeacherCompensationFactType;
    snapshotRate: string;
    rateMinor: string;
    durationMinutes: number;
    amountMinor: string;
    currencyCode: string;
    compensationRuleKey: string | null;
    compensationRuleLabel: string | null;
    compensationMode: TeacherCompensationFactType | null;
    compensationDefaultValue: string | null;
    compensationActualValue: string | null;
    compensationOverrideReason: string | null;
    configurationRevisionId: string | null;
  };
}

export interface LessonSettlementPort {
  settle(
    client: PoolClient,
    lessonId: string,
    input?: LessonSettlementInput,
  ): Promise<LessonSettlementResult>;
}

export const LESSON_SETTLEMENT_PORT = Symbol("LESSON_SETTLEMENT_PORT");
