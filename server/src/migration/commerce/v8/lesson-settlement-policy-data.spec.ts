import type { LessonFinancialDecision } from "../../../crm/commerce/lesson-settlement.port";
import {
  applySettlementPolicyCandidates,
  classifySettlementPolicyCandidate,
  type SettlementPolicyCandidateInput,
} from "./lesson-settlement-policy-data";
import {
  createSettlementPolicyReport,
  settlementDecisionHash,
  verifySettlementPolicyReport,
} from "./lesson-settlement-policy-report";

const LESSON_ID = "11111111-1111-4111-8111-111111111111";

function candidate(
  override: Partial<SettlementPolicyCandidateInput> = {},
): SettlementPolicyCandidateInput {
  return {
    entityType: "lesson_plan",
    entityId: LESSON_ID,
    expectedVersion: 3,
    lifecycleState: "scheduled",
    durationMinutes: 60,
    settlementTypeKey: "lesson",
    settlementTypeActive: true,
    clientDurationMode: "full",
    teacherDurationMode: "full",
    defaultTeacherCompensationRuleKey: "standard",
    teacherCompensationRuleKey: "none",
    teacherCompensationSource: null,
    manualReason: null,
    decision: {
      settlementTypeKey: "lesson",
      teacherCompensationRuleKey: "none",
    },
    ...override,
  };
}

describe("settlement policy reconciliation classification", () => {
  it("classifies only a provable automatic full-rate omission as repairable", () => {
    expect(classifySettlementPolicyCandidate(candidate())).toEqual({
      classification: "repairable_automatic",
      reasonCode: "AUTOMATIC_FULL_RATE_OMITTED",
      proposedDecision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        teacherCreditedDurationMinutes: 60,
        teacherCompensationSource: "automatic",
      },
    });
  });

  it("keeps free-text pricing details out of the proposed report decision", () => {
    const result = classifySettlementPolicyCandidate(candidate({
      decision: {
        settlementTypeKey: "lesson",
        clientDecisions: [{
          clientId: "33333333-3333-4333-8333-333333333333",
          discount: { type: "percent", percent: 10, reason: "Личная заметка" },
        }],
        teacherCompensationRuleKey: "none",
      },
    }));

    expect(JSON.stringify(result.proposedDecision)).not.toContain("Личная заметка");
    expect(result.proposedDecision?.clientDecisions).toBeUndefined();
  });

  it.each([
    { lifecycleState: "successfully_completed", expected: "historical_terminal" },
    { lifecycleState: "cancelled", expected: "historical_terminal" },
    { teacherCompensationSource: "manual", expected: "explicit_manual" },
    { manualReason: "Договорённость", expected: "explicit_manual" },
  ] as const)("does not repair $expected records", (override) => {
    expect(classifySettlementPolicyCandidate(candidate(override)).classification)
      .toBe(override.expected);
  });

  it("repairs a full-rate schedule row whose automatic source is missing", () => {
    expect(classifySettlementPolicyCandidate(candidate({
      entityType: "schedule_series",
      teacherCompensationRuleKey: "standard",
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
      },
    })).classification).toBe("repairable_automatic");
  });

  it("keeps an automatic decision clean even when its audit reason is stored", () => {
    expect(classifySettlementPolicyCandidate(candidate({
      teacherCompensationRuleKey: "standard",
      teacherCompensationSource: "automatic",
      manualReason: "Автоматическое восстановление политики расчёта",
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        teacherCompensationSource: "automatic",
      },
    })).classification).toBe("clean");
  });

  it("keeps a zero-duration none decision clean", () => {
    expect(classifySettlementPolicyCandidate(candidate({
      settlementTypeKey: "unpaid_miss",
      clientDurationMode: "zero",
      teacherDurationMode: "zero",
      defaultTeacherCompensationRuleKey: "none",
      decision: {
        settlementTypeKey: "unpaid_miss",
        teacherCompensationRuleKey: "none",
      },
    })).classification).toBe("clean");
  });

  it("does not infer partial values", () => {
    expect(classifySettlementPolicyCandidate(candidate({
      settlementTypeKey: "partially_paid_lesson",
      clientDurationMode: "manual",
      teacherDurationMode: "manual",
      defaultTeacherCompensationRuleKey: "percent",
    })).classification).toBe("ambiguous");
  });

  it("rejects the inactive penalty type", () => {
    expect(classifySettlementPolicyCandidate(candidate({
      settlementTypeKey: "penalty_lesson",
      settlementTypeActive: false,
    })).classification).toBe("invalid");
  });

  it("rejects malformed legacy JSON", () => {
    expect(classifySettlementPolicyCandidate(candidate({
      decision: null,
    })).classification).toBe("invalid");
  });

  it("rejects an unknown legacy compensation source", () => {
    expect(classifySettlementPolicyCandidate(candidate({
      decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "none",
        teacherCompensationSource: "inferred" as "automatic",
      },
    })).classification).toBe("invalid");
  });
});

describe("signed settlement policy reports", () => {
  it("detects report tampering and never serializes source objects", () => {
    const classified = classifySettlementPolicyCandidate(candidate());
    const decision = candidate().decision as LessonFinancialDecision;
    const report = createSettlementPolicyReport({
      mode: "dry-run",
      candidateRevision: "v8-settlement-policy-v1",
      candidates: [{
        entityType: "lesson_plan",
        entityId: LESSON_ID,
        expectedVersion: 3,
        currentDecisionHash: settlementDecisionHash(decision),
        proposedDecision: classified.proposedDecision!,
        classification: classified.classification,
        reasonCode: classified.reasonCode,
      }],
      issues: [],
      invariants: {
        futureLessonCountBefore: 1,
        futureLessonCountAfter: 1,
        activeReservationUnitsBefore: "1",
        activeReservationUnitsAfter: "1",
        effectiveTeacherFactCountBefore: 0,
        effectiveTeacherFactCountAfter: 0,
        schedulePlanVersionChanges: [],
      },
      generatedAt: "2026-09-04T00:00:00.000Z",
    });

    expect(verifySettlementPolicyReport(report)).toBe(true);
    expect(JSON.stringify(report)).not.toMatch(/Мария|@|token|note/i);
    expect(verifySettlementPolicyReport({
      ...report,
      candidateRevision: "tampered",
    })).toBe(false);
  });
});

describe("settlement policy apply guard", () => {
  it("reports a changed record as stale and does not overwrite it", async () => {
    const original = candidate();
    const classified = classifySettlementPolicyCandidate(original);
    const report = createSettlementPolicyReport({
      mode: "dry-run",
      candidateRevision: "v8-settlement-policy-v1",
      candidates: [{
        entityType: original.entityType,
        entityId: original.entityId,
        expectedVersion: original.expectedVersion,
        currentDecisionHash: settlementDecisionHash(original.decision!),
        proposedDecision: classified.proposedDecision!,
        classification: classified.classification,
        reasonCode: classified.reasonCode,
      }],
      issues: [],
      invariants: {
        futureLessonCountBefore: 1,
        futureLessonCountAfter: 1,
        activeReservationUnitsBefore: "1",
        activeReservationUnitsAfter: "1",
        effectiveTeacherFactCountBefore: 0,
        effectiveTeacherFactCountAfter: 0,
        schedulePlanVersionChanges: [],
      },
      generatedAt: "2026-09-04T00:00:00.000Z",
    });
    const repair = jest.fn();
    const result = await applySettlementPolicyCandidates(report, {
      candidateRevision: "v8-settlement-policy-v1",
      ensureConfiguration: jest.fn(),
      loadCandidate: jest.fn(async () => candidate({ expectedVersion: 4 })),
      repair,
    });

    expect(result).toEqual({
      mutations: 0,
      configurationRevisionId: null,
      issues: [{
        entityType: "lesson_plan",
        entityId: LESSON_ID,
        code: "RECONCILIATION_STALE_CANDIDATE",
      }],
    });
    expect(repair).not.toHaveBeenCalled();
  });

  it("uses a deterministic idempotency key and a second apply is a no-op", async () => {
    const original = candidate();
    const classified = classifySettlementPolicyCandidate(original);
    const currentDecisionHash = settlementDecisionHash(original.decision!);
    const report = createSettlementPolicyReport({
      mode: "dry-run",
      candidateRevision: "v8-settlement-policy-v1",
      candidates: [{
        entityType: original.entityType,
        entityId: original.entityId,
        expectedVersion: original.expectedVersion,
        currentDecisionHash,
        proposedDecision: classified.proposedDecision!,
        classification: classified.classification,
        reasonCode: classified.reasonCode,
      }],
      issues: [],
      invariants: {
        futureLessonCountBefore: 1,
        futureLessonCountAfter: 1,
        activeReservationUnitsBefore: "1",
        activeReservationUnitsAfter: "1",
        effectiveTeacherFactCountBefore: 0,
        effectiveTeacherFactCountAfter: 0,
        schedulePlanVersionChanges: [],
      },
      generatedAt: "2026-09-04T00:00:00.000Z",
    });
    let live = original;
    const repair = jest.fn(async (_candidate, command) => {
      live = candidate({
        expectedVersion: 4,
        teacherCompensationRuleKey: "standard",
        teacherCompensationSource: "automatic",
        decision: command.proposedDecision,
      });
    });
    const dependencies = {
      candidateRevision: "v8-settlement-policy-v1",
      ensureConfiguration: jest.fn(async () => ({
        revisionId: "22222222-2222-4222-8222-222222222222",
        created: true,
      })),
      loadCandidate: jest.fn(async () => live),
      repair,
    };

    const first = await applySettlementPolicyCandidates(report, dependencies);
    const second = await applySettlementPolicyCandidates(report, dependencies);

    expect(first.mutations).toBe(1);
    expect(repair).toHaveBeenCalledWith(original, expect.objectContaining({
      idempotencyKey:
        `v8:settlement-policy:lesson_plan:${LESSON_ID}:${currentDecisionHash}`,
    }));
    expect(second.mutations).toBe(0);
  });
});
