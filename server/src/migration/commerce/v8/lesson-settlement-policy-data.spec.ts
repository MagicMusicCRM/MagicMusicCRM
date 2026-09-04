import type { LessonFinancialDecision } from "../../../crm/commerce/lesson-settlement.port";
import {
  applySettlementPolicyCandidates,
  classifySettlementPolicyCandidate,
  type SettlementPolicyCandidateInput,
  type SettlementPolicyScheduleGroupItem,
  verifyScheduleGroupSnapshot,
  withLegacyClientDecisions,
} from "./lesson-settlement-policy-data";
import {
  createSettlementPolicyReport,
  settlementDecisionHash,
  verifySettlementPolicyReport,
} from "./lesson-settlement-policy-report";

const LESSON_ID = "11111111-1111-4111-8111-111111111111";

describe("legacy reconciliation client identity", () => {
  it("adds frozen clients without replacing snapshot funding defaults", () => {
    expect(withLegacyClientDecisions({
      settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
    }, ["student-b", "student-a", "student-b"])).toEqual({
      settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
      clientDecisions: [{ clientId: "student-a" }, { clientId: "student-b" }],
    });
  });

  it("preserves explicit payer, funding and partial-minute choices", () => {
    const decision: LessonFinancialDecision = {
      settlementTypeKey: "lesson", teacherCompensationRuleKey: "standard",
      clientDecisions: [{ clientId: "student-a", payerStudentId: "payer-b",
        chargeType: "personal_account", basePriceMinor: "120000",
        chargeDurationMinutes: 30 }],
    };
    expect(withLegacyClientDecisions(decision, ["student-a"])).toBe(decision);
  });
});

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
  it("groups schedule rows by plan and rejects a fresh concurrent plan version", async () => {
    const planId = "44444444-4444-4444-8444-444444444444";
    const secondId = "55555555-5555-4555-8555-555555555555";
    const first = candidate({
      entityType: "schedule_series",
      aggregateId: planId,
      expectedVersion: 7,
    });
    const second = candidate({
      entityType: "schedule_series",
      entityId: secondId,
      aggregateId: planId,
      expectedVersion: 7,
    });
    const classified = classifySettlementPolicyCandidate(first);
    const report = createSettlementPolicyReport({
      mode: "dry-run",
      candidateRevision: "v8-settlement-policy-v1",
      candidates: [first, second].map((item) => ({
        entityType: item.entityType,
        entityId: item.entityId,
        expectedVersion: item.expectedVersion,
        currentDecisionHash: settlementDecisionHash(item.decision!),
        proposedDecision: classified.proposedDecision!,
        classification: classified.classification,
        reasonCode: classified.reasonCode,
      })),
      issues: [],
      invariants: {
        futureLessonCountBefore: 2,
        futureLessonCountAfter: 2,
        activeReservationUnitsBefore: "2",
        activeReservationUnitsAfter: "2",
        effectiveTeacherFactCountBefore: 0,
        effectiveTeacherFactCountAfter: 0,
        schedulePlanVersionChanges: [],
      },
      generatedAt: "2026-09-04T00:00:00.000Z",
    });
    const repair = jest.fn();
    const repairScheduleGroup = jest.fn(async (
      items: SettlementPolicyScheduleGroupItem[],
    ) => {
      verifyScheduleGroupSnapshot(items, {
        planId,
        planVersion: 8,
        rows: items.map(({ candidate }) => ({
          seriesId: candidate.entityId,
          decision: first.decision!,
        })),
      });
    });

    await expect(applySettlementPolicyCandidates(report, {
      candidateRevision: "v8-settlement-policy-v1",
      ensureConfiguration: jest.fn(async () => ({
        revisionId: "22222222-2222-4222-8222-222222222222",
        created: false,
      })),
      loadCandidate: jest.fn(async (_type, id) => id === secondId
        ? second
        : first),
      repair,
      repairScheduleGroup,
    })).resolves.toEqual({
      mutations: 0,
      configurationRevisionId: "22222222-2222-4222-8222-222222222222",
      issues: [
        { entityType: "schedule_series", entityId: LESSON_ID,
          code: "RECONCILIATION_STALE_CANDIDATE" },
        { entityType: "schedule_series", entityId: secondId,
          code: "RECONCILIATION_STALE_CANDIDATE" },
      ],
    });
    expect(repairScheduleGroup).toHaveBeenCalledTimes(1);
    expect(repair).not.toHaveBeenCalled();
  });

  it("treats a live manual decision as stale instead of trusting completion state", async () => {
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
      loadCandidate: jest.fn(async () => candidate({
        teacherCompensationSource: "manual",
        decision: {
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "1000",
          teacherCompensationSource: "manual",
        },
      })),
      repair,
    });

    expect(result.issues).toEqual([{
      entityType: "lesson_plan",
      entityId: LESSON_ID,
      code: "RECONCILIATION_STALE_CANDIDATE",
    }]);
    expect(repair).not.toHaveBeenCalled();
  });

  it("does not no-op a completed automatic decision with different credited minutes", async () => {
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

    const result = await applySettlementPolicyCandidates(report, {
      candidateRevision: "v8-settlement-policy-v1",
      ensureConfiguration: jest.fn(),
      loadCandidate: jest.fn(async () => candidate({
        expectedVersion: 4,
        teacherCompensationRuleKey: "standard",
        teacherCompensationSource: "automatic",
        decision: {
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "standard",
          teacherCreditedDurationMinutes: 30,
          teacherCompensationSource: "automatic",
        },
      })),
      repair: jest.fn(),
    });

    expect(result.issues).toEqual([{
      entityType: "lesson_plan",
      entityId: LESSON_ID,
      code: "RECONCILIATION_STALE_CANDIDATE",
    }]);
  });

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
