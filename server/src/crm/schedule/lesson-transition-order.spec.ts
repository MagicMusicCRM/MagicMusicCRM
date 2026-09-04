import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import type {
  LessonFinancialDecision,
  LessonSettlementPort,
  LessonSettlementResult,
} from "../commerce/lesson-settlement.port";
import type { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import type { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import type { CrmPolicy } from "../crm.policy";
import type { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonTransitionCommandService } from "./lesson-transition-command.service";
import { LessonTransitionCommitService } from "./lesson-transition-commit.service";
import { LessonBulkTransitionService } from "./lesson-bulk-transition.service";
import { LessonTransitionFinancialService } from "./lesson-transition-financial.service";
import { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import { LessonTransitionPreviewService } from "./lesson-transition-preview.service";
import * as transitionRules from "./lesson-transition.rules";
import {
  bulkTransitionPreviewId,
  bulkTransitionFingerprint,
  normalizeBulkTransitionItems,
  transitionAdvisoryKeys,
} from "./lesson-transition.rules";
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
  excludedParticipantIds: [],
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
    compensationSource: "automatic",
    configurationRevisionId: null,
  },
};
settlementResult.clientFact = settlementResult.clientFacts[0]!;

describe("Lesson transition runtime ordering", () => {
  it("zeroes a whole group cancellation but preserves its teacher decision for one absence", async () => {
    const firstStudentId = source.studentId!;
    const secondStudentId = "00000000-0000-4000-8000-000000000006";
    const groupSource: TransitionSource = {
      ...source,
      studentId: null,
      groupId: "00000000-0000-4000-8000-000000000007",
      snapshot: null,
      groupSnapshot: {
        completionType: "regular",
        teacherCompensationType: "fixed",
        teacherCompensationValue: 1_500,
        trial: false,
        validationState: "valid",
      },
      participants: [firstStudentId, secondStudentId].map((studentId) => ({
        studentId,
        chargeType: "subscription" as const,
        chargeValue: 1,
        subscriptionId: null,
      })),
    };
    const settlement = {
      loadPlan: jest.fn(async () => ({
        decision: {
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "150000",
          teacherCreditedDurationMinutes: 60,
          teacherCompensationSource: "manual" as const,
        },
      })),
      resolvePlannedPlan: jest.fn(async (_client, input) => ({
        decision: input.preservedTeacherDecision
          ? { ...input.decision, ...input.preservedTeacherDecision }
          : {
              ...input.decision,
              clientDecisions: input.decision.clientDecisions?.map(
                (decision: NonNullable<LessonFinancialDecision["clientDecisions"]>[number]) => ({
                  ...decision,
                  chargeDurationMinutes: 0,
                }),
              ),
              teacherCompensationRuleKey: "none",
              teacherCreditedDurationMinutes: 0,
              teacherCompensationSource: "automatic" as const,
            },
        settlementRevisionId: "current-settlement-revision",
        compensationRevisionId: "current-compensation-revision",
      })),
    } as unknown as LessonSettlementPort;
    const preparation = new LessonTransitionPreparationService(
      {} as never,
      {
        canManageTeacherCompensation: jest.fn(() => false),
        teacherCompensationMutationAuthorization: jest.fn((actor) => ({
          actor,
          capabilityKey: "schedule.lesson.write",
        })),
      } as never,
      {} as never,
      {} as never,
      settlement,
      {} as never,
      {} as never,
      {} as never,
    );

    const prepared = await preparation.resolvedEffectiveTransitionDto(
      {} as PoolClient,
      { userId: "actor", role: "manager" },
      groupSource,
      "cancel",
      {
        operation: "cancel",
        expectedVersion: 1,
        reasonText: "Отмена всей группы",
        financialDecision: {
          settlementTypeKey: "unpaid_miss",
          teacherCompensationRuleKey: "standard",
          clientDecisions: [firstStudentId, secondStudentId].map(
            (clientId) => ({ clientId, chargeType: "none" as const }),
          ),
        },
      },
    );

    expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
      expect.anything(),
      expect.not.objectContaining({
        preservedTeacherDecision: expect.anything(),
      }),
    );
    expect(prepared.financialDecision).toMatchObject({
      settlementTypeKey: "unpaid_miss",
      clientDecisions: [
        { clientId: firstStudentId, chargeDurationMinutes: 0 },
        { clientId: secondStudentId, chargeDurationMinutes: 0 },
      ],
      teacherCompensationRuleKey: "none",
      teacherCreditedDurationMinutes: 0,
      teacherCompensationSource: "automatic",
    });

    const participantAbsence = await preparation.resolvedEffectiveTransitionDto(
      {} as PoolClient,
      { userId: "actor", role: "manager" },
      groupSource,
      "settle",
      {
        operation: "settle",
        expectedVersion: 1,
        reasonText: "Частичный пропуск одного участника",
        financialDecision: {
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "none",
          clientDecisions: [
            {
              clientId: firstStudentId,
              settlementTypeKey: "partially_paid_miss",
              chargeType: "subscription",
              chargeDurationMinutes: 30,
            },
            {
              clientId: secondStudentId,
              chargeType: "subscription",
              chargeDurationMinutes: 60,
            },
          ],
        },
      },
    );

    expect(settlement.resolvePlannedPlan).toHaveBeenLastCalledWith(
      expect.anything(),
      expect.objectContaining({
        preservedTeacherDecision: expect.objectContaining({
          teacherCompensationRuleKey: "fixed",
          teacherCreditedDurationMinutes: 60,
          teacherCompensationSource: "manual",
        }),
      }),
    );
    expect(participantAbsence.financialDecision).toMatchObject({
      clientDecisions: [
        {
          clientId: firstStudentId,
          settlementTypeKey: "partially_paid_miss",
          chargeDurationMinutes: 30,
        },
        {
          clientId: secondStudentId,
          chargeDurationMinutes: 60,
        },
      ],
      teacherCompensationRuleKey: "fixed",
      teacherCreditedDurationMinutes: 60,
      teacherCompensationSource: "manual",
    });
  });

  it("prepares a server-owned zero source and editable partial successor", async () => {
    const settlement = {
      loadPlan: jest.fn(async () => null),
      resolvePlannedPlan: jest.fn(async (_client, input) => ({
        decision: {
          ...input.decision,
          teacherCompensationSource: "automatic",
        },
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      })),
    } as unknown as LessonSettlementPort;
    const preparation = new LessonTransitionPreparationService(
      {} as never,
      {
        canManageTeacherCompensation: jest.fn(() => true),
        assertCanSupplyTeacherCompensation: jest.fn(),
        teacherCompensationMutationAuthorization: jest.fn(() => ({})),
      } as never,
      { update: jest.fn(() => successor) } as never,
      {} as never,
      settlement,
      {} as never,
      {} as never,
      { loadEffectiveTeacherRate: jest.fn(async () => 700) } as never,
    );
    const successorFinancialDecision = {
      settlementTypeKey: "partial_lesson",
      clientDecisions: [{
        clientId: source.studentId!,
        chargeDurationMinutes: 30,
      }],
      teacherCompensationRuleKey: "standard",
      teacherCreditedDurationMinutes: 45,
    };

    const prepared = await preparation.resolvedEffectiveTransitionDto(
      {} as PoolClient,
      { userId: "actor", role: "manager" },
      source,
      "reschedule",
      {
        operation: "reschedule",
        expectedVersion: 1,
        reasonText: "Перенос",
        successor: {} as never,
        sourceFinancialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        successorFinancialDecision,
      },
    ) as unknown as {
      sourceFinancialDecision: Record<string, unknown>;
      successorFinancialDecision: typeof successorFinancialDecision;
    };

    expect(prepared.sourceFinancialDecision).toMatchObject({
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      clientDecisions: [{
        clientId: source.studentId,
        chargeType: "none",
        chargeDurationMinutes: 0,
      }],
    });
    expect(prepared.successorFinancialDecision).toEqual({
      ...successorFinancialDecision,
      teacherRateSnapshot: { type: "hourly", value: "700" },
      teacherCompensationSource: "automatic",
    });
  });

  it("gates a direct reschedule preview before source preparation", async () => {
    const events: string[] = [];
    const client = {
      query: jest.fn(async (_query: string, params?: unknown[]) => {
        if (params?.[0] === "commerce:multi-lesson-settlement") {
          events.push("settlement-gate");
        }
        return { rows: [] };
      }),
    } as unknown as PoolClient;
    const database = {
      transaction: jest.fn(async (work: (target: PoolClient) => unknown) =>
        work(client)),
    } as unknown as DatabaseService;
    const preparation = {
      calculatePreview: jest.fn(async () => {
        events.push("source-preparation");
        return {
          operation: "reschedule",
          source: { id: source.id, version: 1, state: "scheduled" },
          successor: null,
          financialDecision: {},
          violations: [],
          canConfirm: false,
          confirmRequired: true,
        };
      }),
    } as unknown as LessonTransitionPreparationService;
    const previews = new LessonTransitionPreviewService(
      database,
      { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy,
      preparation,
      {} as SubscriptionPreviewTokenService,
    );

    await previews.previewReschedule(
      { userId: "actor", role: "manager" },
      source.id,
      {
        expectedVersion: 1,
        reasonText: "reason",
        financialDecision: {},
        successor: {},
      } as never,
    );

    expect(events).toEqual(["settlement-gate", "source-preparation"]);
  });

  it("preserves commit and post-commit publication order", async () => {
    const events: string[] = [];
    let committedRef: CommittedTransition | undefined;
    const sourceFinancialDecision = {
      settlementTypeKey: "free_lesson",
      clientDecisions: [{
        clientId: source.studentId!,
        chargeType: "none" as const,
        chargeDurationMinutes: 0,
      }],
      teacherCompensationRuleKey: "none",
      teacherCreditedDurationMinutes: 0,
      teacherCompensationSource: "automatic" as const,
    };
    const successorFinancialDecision = {
      settlementTypeKey: "partially_paid_lesson",
      clientDecisions: [{
        clientId: source.studentId!,
        chargeDurationMinutes: 30,
      }],
      teacherCompensationRuleKey: "standard",
      teacherCreditedDurationMinutes: 45,
      teacherCompensationSource: "automatic" as const,
    };
    let advisoryRecorded = false;
    const client = {
      query: jest.fn(async (query: string, params?: unknown[]) => {
        const normalized = query.trim().replace(/\s+/g, " ").toLowerCase();
        if (
          normalized.includes("pg_advisory_xact_lock") &&
          params?.[0] === "commerce:multi-lesson-settlement"
        ) {
          events.push("settlement-gate");
        } else if (
          normalized.includes("pg_advisory_xact_lock") &&
          !advisoryRecorded
        ) {
          advisoryRecorded = true;
          events.push("advisory-locks");
        }
        if (normalized.includes("jsonb_to_recordset")) {
          events.push("active-client-recheck");
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
      resolvedEffectiveTransitionDto: jest.fn(
        async (
          _client: PoolClient,
          _actor: unknown,
          _lessonId: string,
          _operation: string,
          dto: unknown,
        ) => {
          events.push("catalog-resolution");
          return {
            ...(dto as Record<string, unknown>),
            sourceFinancialDecision,
            successorFinancialDecision,
            sourceConfigurationRevisionIds: {
              settlementRevisionId: "source-settlement-revision",
              compensationRevisionId: "source-compensation-revision",
            },
            successorConfigurationRevisionIds: {
              settlementRevisionId: "successor-settlement-revision",
              compensationRevisionId: "successor-compensation-revision",
            },
          };
        },
      ),
      successorDraft: jest.fn(() => successor),
      validateSuccessor: jest.fn(async () => {
        events.push("constraint-validation");
        return { valid: true, violations: [] };
      }),
    } as unknown as LessonTransitionPreparationService;
    const financial = {
      commitRescheduleFinancials: jest.fn(async () => {
        events.push("source-settlement");
        events.push("successor-allocation");
        return {
          sourceSettlement: settlementResult,
          successorPlanId: "successor-plan-id",
          transferredReservationId: null,
        };
      }),
    } as unknown as LessonTransitionFinancialService;
    const settlement = {
      settle: jest.fn(async () => settlementResult),
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
        beforeVersionAdvance?: (client: PoolClient) => Promise<void>;
        mutate: (
          transactionClient: PoolClient,
          nextVersion: number,
        ) => Promise<CommittedTransition>;
      };
      const platform = {
        executeVersionedMutation: jest.fn(async (input: MutationInput) => {
          await input.beforeVersionAdvance?.(client);
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
          successorFinancialDecision,
          successor: {} as never,
          previewToken: "signed-preview",
          confirm: true,
        },
        { idempotencyKey: "runtime-order-key", requestId: "request-id" },
      );
      expect(result.replayed).toBe(false);
      expect(result.successor?.state).toBe("scheduled");
      expect(result.sourceFinancialDecision).toEqual(sourceFinancialDecision);
      expect(result.successorFinancialDecision).toEqual(successorFinancialDecision);
      expect(result.financialDecision).toEqual(successorFinancialDecision);
      expect(financial.commitRescheduleFinancials).toHaveBeenCalledWith(
        client,
        source,
        expect.any(String),
        expect.objectContaining({
          actor: { userId: "actor", role: "manager" },
          reasonText: "reason",
          sourceFinancialDecision,
          successorFinancialDecision,
          sourceConfigurationRevisionIds: {
            settlementRevisionId: "source-settlement-revision",
            compensationRevisionId: "source-compensation-revision",
          },
          successorConfigurationRevisionIds: {
            settlementRevisionId: "successor-settlement-revision",
            compensationRevisionId: "successor-compensation-revision",
          },
          coverage: {},
          correctionId: expect.any(String),
        }),
      );
      expect(committedRef?.transitionFingerprint).toBe("fingerprint");
      expect(JSON.stringify(committedRef)).not.toContain(
        "transitionFingerprint",
      );
      expect(JSON.stringify(committedRef)).not.toContain("fingerprint");
    } finally {
      fingerprint.mockRestore();
    }
    expect(events).toEqual([
      "settlement-gate",
      "source-for-update",
      "settlement-review",
      "advisory-locks",
      "active-client-recheck",
      "constraint-validation",
      "catalog-resolution",
      "coverage-lock",
      "successor-insert",
      "source-settlement",
      "successor-allocation",
      "fingerprint-check",
      "transition-append",
      "mutation-resolved",
      "publish-source",
      "publish-successor",
    ]);
  });

  it("returns both financial decisions from a bulk reschedule commit", async () => {
    const sourceFinancialDecision = {
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
    };
    const successorFinancialDecision = {
      settlementTypeKey: "lesson",
      teacherCompensationRuleKey: "standard",
    };
    const committed = {
      lessonId: source.id,
      state: "rescheduled",
      successorId: "00000000-0000-4000-8000-000000000099",
      transitionId: "transition-id",
      clientFinancialFactIds: ["client-fact"],
      teacherFinancialFactId: "teacher-fact",
      financialDecision: successorFinancialDecision,
      sourceFinancialDecision,
      successorFinancialDecision,
      transitionFingerprint: "item-fingerprint",
    } as CommittedTransition;
    const command = {
      reasonText: "Перенос",
      items: [{
        lessonId: source.id,
        operation: "reschedule" as const,
        expectedVersion: 1,
        successor: {} as never,
        successorFinancialDecision,
      }],
      previewToken: "signed-preview",
      confirm: true as const,
    };
    const previewId = bulkTransitionPreviewId(
      normalizeBulkTransitionItems(command),
    );
    const bulkFingerprint = bulkTransitionFingerprint(command, [{
      lessonId: source.id,
      operation: "reschedule",
      preview: { transitionFingerprint: "item-fingerprint" },
    }]);
    const tokens = {
      verifyLessonTransition: jest.fn(() => ({
        actorUserId: "actor",
        operation: "bulk",
        lessonId: previewId,
        expectedVersion: 1,
        transitionFingerprint: bulkFingerprint,
      })),
    } as unknown as SubscriptionPreviewTokenService;
    const platform = {
      executeVersionedMutation: jest.fn(async (input) => ({
        version: 1,
        resultRef: await input.mutate({} as PoolClient),
        replayed: false,
      })),
    } as unknown as PlatformIntegrityService;
    const commits = {
      commit: jest.fn(async () => committed),
    } as unknown as LessonTransitionCommitService;
    const service = new LessonBulkTransitionService(
      {} as DatabaseService,
      platform,
      {
        assertCanWriteCrm: jest.fn(),
        teacherCompensationMutationAuthorization: jest.fn(() => ({})),
      } as unknown as CrmPolicy,
      tokens,
      {} as LessonTransitionPreparationService,
      commits,
      {
        publishLessonSettlementPostCommit: jest.fn(),
      } as unknown as SubscriptionReservationService,
    );
    const result = await service.bulk(
      { userId: "actor", role: "manager" },
      command,
      { idempotencyKey: "bulk-result-key", requestId: "request-id" },
    );

    expect(result.items[0]).toMatchObject({
      financialDecision: successorFinancialDecision,
      sourceFinancialDecision,
      successorFinancialDecision,
    });
    expect(commits.commit).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        dto: expect.objectContaining({
          sourceFinancialDecision: expect.objectContaining({
            settlementTypeKey: "free_lesson",
          }),
          successorFinancialDecision,
        }),
      }),
    );
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
        operation: "cancel",
        expectedVersion: 1,
        reasonText: "reason",
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          teacherCompensationSource: "automatic",
        },
        configurationRevisionIds: {
          settlementRevisionId: "settlement-revision",
          compensationRevisionId: "compensation-revision",
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
