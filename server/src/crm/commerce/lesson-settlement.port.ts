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
  /** Server-owned rate frozen when the assigned teacher is corrected. Never accepted by the command DTO. */
  teacherRateSnapshot?: { type: "hourly"; value: string };
  settlementTypeKey: string;
  clientDecisions?: Array<{
    clientId: string;
    settlementTypeKey?: string;
    subscriptionId?: string;
    payerStudentId?: string;
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
  payerStudentId?: string;
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
  preparePlan(
    client: PoolClient,
    branchId: string,
    decision: LessonFinancialDecision,
  ): Promise<PreparedLessonSettlementPlan>;
  assignPlan(
    client: PoolClient,
    input: {
      lessonId: string;
      branchId: string;
      decision: LessonFinancialDecision;
      selectedBy: string;
      reasonText?: string;
    },
  ): Promise<PreparedLessonSettlementPlan>;
  clonePlan(
    client: PoolClient,
    input: {
      sourceLessonId: string;
      targetLessonId: string;
      selectedBy: string;
      reasonText?: string;
      fallback?: {
        branchId: string;
        decision: LessonFinancialDecision;
      };
    },
  ): Promise<PreparedLessonSettlementPlan>;
  loadPlan(
    client: PoolClient,
    lessonId: string,
    lock?: boolean,
  ): Promise<StoredLessonSettlementPlan | null>;
  markPlanState(
    client: PoolClient,
    lessonId: string,
    state: "settled" | "review_required" | "cancelled",
    failureCode?: string,
  ): Promise<void>;
  plannedSubscriptionAllocations(
    client: PoolClient,
    lessonId: string,
    plan: PreparedLessonSettlementPlan,
  ): Promise<PlannedSubscriptionAllocation[]>;
}

export const LESSON_SETTLEMENT_PORT = Symbol("LESSON_SETTLEMENT_PORT");
