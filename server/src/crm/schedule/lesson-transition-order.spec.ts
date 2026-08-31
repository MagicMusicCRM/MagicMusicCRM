import type { PoolClient } from "pg";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import type {
  LessonSettlementPort,
  LessonSettlementResult,
} from "../commerce/lesson-settlement.port";
import type { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import type { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import type { CrmPolicy } from "../crm.policy";
import type { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonTransitionCommandService } from "./lesson-transition-command.service";
import { LessonTransitionCommitService } from "./lesson-transition-commit.service";
import { LessonTransitionFinancialService } from "./lesson-transition-financial.service";
import type { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import * as transitionRules from "./lesson-transition.rules";
import { transitionAdvisoryKeys } from "./lesson-transition.rules";
import type {
  CommittedTransition,
  TransitionSource,
  TransitionSuccessor,
} from "./lesson-transition.types";

const source: TransitionSource = {
  id: "00000000-0000-4000-8000-000000000001",
  version: 1,
  lifecycleState: "scheduled",
  studentId: "00000000-0000-4000-8000-000000000002",
  leadId: null,
  groupId: null,
  teacherId: "00000000-0000-4000-8000-000000000003",
  branchId: "00000000-0000-4000-8000-000000000004",
  roomId: "00000000-0000-4000-8000-000000000005",
  scheduledAt: "2026-08-27T10:00:00.000Z",
  durationMinutes: 60,
  isTrial: false,
  notes: null,
  snapshot: {
    clientType: "student",
    clientId: "00000000-0000-4000-8000-000000000002",
    completionType: "regular",
    clientChargeType: "none",
    clientChargeValue: 0,
    teacherCompensationType: "none",
    teacherCompensationValue: 0,
    subscriptionId: null,
    trial: false,
    validationState: "valid",
  },
  groupSnapshot: null,
  participants: [],
};

const successor: TransitionSuccessor = {
  kind: "individual",
  clientRef: { type: "student", id: source.studentId! },
  teacherId: source.teacherId!,
  branchId: source.branchId!,
  roomId: source.roomId!,
  scheduledAt: "2026-08-28T10:00:00.000Z",
  durationMinutes: 60,
  endAt: "2026-08-28T11:00:00.000Z",
  isTrial: false,
  notes: null,
  completionType: "regular",
  clientChargeType: "none",
  clientChargeValue: 0,
  teacherCompensationType: "none",
  teacherCompensationValue: 0,
  subscriptionId: null,
};

const settlementResult: LessonSettlementResult = {
  lessonId: source.id,
  clientFacts: [
    {
      id: "client-fact",
      clientType: "student",
      clientId: source.studentId!,
      chargeType: "none",
      snapshotValue: "0",
      subscriptionId: null,
      amountMinor: "0",
      units: "0",
      currencyCode: "RUB",
      settlementTypeKey: "free_lesson",
      settlementLabel: null,
      settlementColorToken: null,
      hourShareBasisPoints: null,
      fixedPenaltyMinor: null,
      configurationRevisionId: null,
    },
  ],
  clientFact: undefined as never,
  teacherFact: {
    id: "teacher-fact",
    teacherId: source.teacherId!,
    compensationType: "none",
    snapshotRate: "0",
    rateMinor: "0",
    durationMinutes: 60,
    amountMinor: "0",
    currencyCode: "RUB",
    compensationRuleKey: "none",
    compensationRuleLabel: null,
    compensationMode: "none",
    compensationDefaultValue: null,
    compensationActualValue: null,
    compensationOverrideReason: null,
    configurationRevisionId: null,
  },
};
settlementResult.clientFact = settlementResult.clientFacts[0]!;

describe("Lesson transition runtime ordering", () => {
  it("preserves commit and post-commit publication order", async () => {
    const events: string[] = [];
    let committedRef: CommittedTransition | undefined;
    let advisoryRecorded = false;
    const client = {
      query: jest.fn(async (query: string) => {
        const normalized = query.trim().replace(/\s+/g, " ").toLowerCase();
        if (normalized.includes("pg_advisory_xact_lock") && !advisoryRecorded) {
          advisoryRecorded = true;
          events.push("advisory-locks");
        }
        if (normalized.startsWith("insert into app.lessons")) {
          events.push("successor-insert");
        }
        if (
          normalized.startsWith("update app.lessons") &&
          normalized.includes("returning version")
        )
          return { rows: [{ version: 2 }] };
        return { rows: [] };
      }),
    } as unknown as PoolClient;
    const preparation = {
      loadSource: jest.fn(async () => {
        events.push("source-for-update");
        return source;
      }),
      assertSource: jest.fn(),
      assertSettlementReviewPlan: jest.fn(async () => {
        events.push("settlement-review");
      }),
      authorizedTransitionDto: jest.fn(
        async (
          _client: PoolClient,
          _actor: unknown,
          _lessonId: string,
          dto: unknown,
        ) => dto,
      ),
      successorDraft: jest.fn(() => successor),
      validateSuccessor: jest.fn(async () => {
        events.push("constraint-validation");
        return { valid: true, violations: [] };
      }),
    } as unknown as LessonTransitionPreparationService;
    const financial = {
      cloneAndAllocateSuccessor: jest.fn(async () => {
        events.push("successor-allocation");
      }),
    } as unknown as LessonTransitionFinancialService;
    const settlement = {
      settle: jest.fn(async () => {
        events.push("source-settlement");
        return settlementResult;
      }),
    } as unknown as LessonSettlementPort;
    const reservations = {
      lockSettlementCoverage: jest.fn(async () => {
        events.push("coverage-lock");
        return {};
      }),
      terminalize: jest.fn(async () => undefined),
      publishLessonSettlementPostCommit: jest.fn(async (lessonId: string) => {
        events.push(
          lessonId === source.id ? "publish-source" : "publish-successor",
        );
      }),
    } as unknown as SubscriptionReservationService;
    const lifecycle = {
      createSnapshot: jest.fn(async () => undefined),
      appendTransition: jest.fn(async () => {
        events.push("transition-append");
        return { rows: [{ id: "transition-id" }] };
      }),
    } as unknown as LessonLifecycleRepository;
    const fingerprint = jest
      .spyOn(transitionRules, "transitionFingerprint")
      .mockImplementation(() => {
        events.push("fingerprint-check");
        return "fingerprint";
      });
    try {
      const commits = new LessonTransitionCommitService(
        preparation,
        financial,
        settlement,
        reservations,
        lifecycle,
      );
      type MutationInput = {
        mutate: (
          transactionClient: PoolClient,
          nextVersion: number,
        ) => Promise<CommittedTransition>;
      };
      const platform = {
        executeVersionedMutation: jest.fn(async (input: MutationInput) => {
          const resultRef = await input.mutate(client, 2);
          committedRef = resultRef;
          events.push("mutation-resolved");
          return { version: 2, resultRef, replayed: false };
        }),
      } as unknown as PlatformIntegrityService;
      const policy = {
        assertCanWriteCrm: jest.fn(),
        assertCanSupplyTeacherCompensation: jest.fn(),
        canManageTeacherCompensation: jest.fn(() => false),
        teacherCompensationMutationAuthorization: jest.fn((targetActor) => ({
          actor: targetActor,
          capabilityKey: "schedule.lesson.write",
        })),
      } as unknown as CrmPolicy;
      const tokens = {
        verifyLessonTransition: jest.fn(() => ({
          kind: "lesson.transition",
          actorUserId: "actor",
          operation: "reschedule",
          lessonId: source.id,
          expectedVersion: 1,
          transitionFingerprint: "fingerprint",
        })),
      } as unknown as SubscriptionPreviewTokenService;
      const commands = new LessonTransitionCommandService(
        platform,
        policy,
        tokens,
        commits,
        reservations,
      );
      const result = await commands.reschedule(
        { userId: "actor", role: "manager" },
        source.id,
        {
          expectedVersion: 1,
          reasonText: "reason",
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "none",
          },
          successor: {} as never,
          previewToken: "signed-preview",
          confirm: true,
        },
        { idempotencyKey: "runtime-order-key", requestId: "request-id" },
      );
      expect(result.replayed).toBe(false);
      expect(result.successor?.state).toBe("scheduled");
      expect(committedRef?.transitionFingerprint).toBe("fingerprint");
      expect(JSON.stringify(committedRef)).not.toContain(
        "transitionFingerprint",
      );
      expect(JSON.stringify(committedRef)).not.toContain("fingerprint");
    } finally {
      fingerprint.mockRestore();
    }
    expect(events).toEqual([
      "source-for-update",
      "settlement-review",
      "advisory-locks",
      "constraint-validation",
      "coverage-lock",
      "successor-insert",
      "source-settlement",
      "fingerprint-check",
      "successor-allocation",
      "transition-append",
      "mutation-resolved",
      "publish-source",
      "publish-successor",
    ]);
  });

  it("sorts advisory resources and always restores preview savepoints", async () => {
    const advisoryKeys = transitionAdvisoryKeys(source, successor);
    expect(advisoryKeys).toEqual([...new Set(advisoryKeys)].sort());

    const previewClientQueries: string[] = [];
    const client = {
      query: jest.fn(async (query: string) => {
        const normalized = query.trim().replace(/\s+/g, " ").toLowerCase();
        if (
          normalized.startsWith("savepoint") ||
          normalized.startsWith("rollback to savepoint") ||
          normalized.startsWith("release savepoint")
        )
          previewClientQueries.push(normalized);
        return { rows: [] };
      }),
    } as unknown as PoolClient;
    const settlement = {
      settle: jest.fn(async () => settlementResult),
    } as unknown as LessonSettlementPort;
    const reservations = {
      terminalize: jest.fn(async () => undefined),
    } as unknown as SubscriptionReservationService;
    const financial = new LessonTransitionFinancialService(
      settlement,
      reservations,
    );
    await financial.previewFinancial(
      client,
      { userId: "actor", role: "manager" },
      source,
      source.id,
      "cancel",
      {
        expectedVersion: 1,
        reasonText: "reason",
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
      },
    );
    expect(previewClientQueries).toEqual([
      "savepoint lesson_transition_preview",
      "rollback to savepoint lesson_transition_preview",
      "release savepoint lesson_transition_preview",
    ]);
  });
});
