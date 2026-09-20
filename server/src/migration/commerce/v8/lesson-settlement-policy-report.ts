import type { LessonFinancialDecision } from "../../../crm/commerce/lesson-settlement.port";
import { fingerprintPayload } from "../../../platform/platform-integrity.util";

export const SETTLEMENT_POLICY_CANDIDATE_REVISION =
  "v8-settlement-policy-v1";

export type SettlementPolicyClassification =
  | "clean"
  | "repairable_automatic"
  | "explicit_manual"
  | "historical_terminal"
  | "ambiguous"
  | "invalid";

export interface SettlementPolicyRepairCandidate {
  entityType: "lesson_plan" | "schedule_series";
  entityId: string;
  expectedVersion: number;
  currentDecisionHash: string;
  proposedDecision: LessonFinancialDecision;
  classification: SettlementPolicyClassification;
  reasonCode: string;
}

export interface SettlementPolicyReconciliationReport {
  mode: "dry-run" | "apply";
  generatedAt: string;
  candidateRevision: string;
  counts: Record<SettlementPolicyClassification, number>;
  candidates: SettlementPolicyRepairCandidate[];
  issues: Array<{ entityType: string; entityId: string; code: string }>;
  invariants: {
    futureLessonCountBefore: number;
    futureLessonCountAfter: number;
    activeReservationUnitsBefore: string;
    activeReservationUnitsAfter: string;
    effectiveTeacherFactCountBefore: number;
    effectiveTeacherFactCountAfter: number;
    schedulePlanVersionChanges: Array<{
      planId: string;
      before: number;
      after: number;
    }>;
  };
  systemSettlementPolicyRevisionId?: string | null;
  reportSha256: string;
}

type UnsignedReport = Omit<SettlementPolicyReconciliationReport, "reportSha256">;

const CLASSIFICATIONS: SettlementPolicyClassification[] = [
  "clean",
  "repairable_automatic",
  "explicit_manual",
  "historical_terminal",
  "ambiguous",
  "invalid",
];

export function settlementDecisionHash(decision: LessonFinancialDecision): string {
  return fingerprintPayload(decision);
}

export function createSettlementPolicyReport(
  input: Omit<UnsignedReport, "counts">,
): SettlementPolicyReconciliationReport {
  const counts = Object.fromEntries(
    CLASSIFICATIONS.map((classification) => [classification, 0]),
  ) as Record<SettlementPolicyClassification, number>;
  for (const candidate of input.candidates) {
    counts[candidate.classification] += 1;
  }
  const unsigned: UnsignedReport = { ...input, counts };
  return { ...unsigned, reportSha256: fingerprintPayload(unsigned) };
}

export function verifySettlementPolicyReport(
  report: SettlementPolicyReconciliationReport,
): boolean {
  const { reportSha256, ...unsigned } = report;
  return /^[a-f0-9]{64}$/.test(reportSha256) &&
    fingerprintPayload(unsigned) === reportSha256;
}
