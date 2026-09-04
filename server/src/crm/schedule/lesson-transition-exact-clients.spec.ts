import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import type {
  LessonFinancialDecision,
  LessonSettlementPort,
} from "../commerce/lesson-settlement.port";
import type { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import type { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import type { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import type { LessonCommandRepository } from "./lesson-command.repository";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import type { ScheduleConstraintEngine } from "./constraint-engine.service";
import { LessonTransitionCommitService } from "./lesson-transition-commit.service";
import type { LessonTransitionFinancialService } from "./lesson-transition-financial.service";
import { LessonTransitionPreparationService } from "./lesson-transition-preparation.service";
import { LessonTransitionPreviewService } from "./lesson-transition-preview.service";
import type {
  TransitionOperation,
  FinancialTransitionPreviewDto,
  TransitionPreviewDto,
  TransitionSource,
} from "./lesson-transition.types";

const studentA = "00000000-0000-4000-8000-00000000000a";
const studentB = "00000000-0000-4000-8000-00000000000b";
const excludedStudent = "00000000-0000-4000-8000-00000000000c";
const leadA = "00000000-0000-4000-8000-00000000000d";

const individualSource = (
  clientType: "student" | "lead",
  clientId: string,
): TransitionSource => ({
  id: "00000000-0000-4000-8000-000000000001",
  version: 1,
  lifecycleState: "scheduled",
  studentId: clientType === "student" ? clientId : null,
  leadId: clientType === "lead" ? clientId : null,
  groupId: null,
  teacherId: "00000000-0000-4000-8000-000000000002",
  branchId: "00000000-0000-4000-8000-000000000003",
  roomId: "00000000-0000-4000-8000-000000000004",
  scheduledAt: "2026-09-04T09:00:00.000Z",
  durationMinutes: 60,
  isTrial: false,
  notes: null,
  snapshot: {
    clientType,
    clientId,
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
});

const groupSource = (): TransitionSource => ({
  ...individualSource("student", studentA),
  studentId: null,
  groupId: "00000000-0000-4000-8000-000000000005",
  snapshot: null,
  groupSnapshot: {
    completionType: "regular",
    teacherCompensationType: "none",
    teacherCompensationValue: 0,
    trial: false,
    validationState: "valid",
  },
  participants: [studentB, excludedStudent, studentA].map((studentId) => ({
    studentId,
    chargeType: "none" as const,
    chargeValue: 0,
    subscriptionId: null,
  })),
  excludedParticipantIds: [excludedStudent],
} as TransitionSource);

const decision = (clientIds: string[]): LessonFinancialDecision => ({
  settlementTypeKey: "free_lesson",
  teacherCompensationRuleKey: "none",
  clientDecisions: clientIds.map((clientId) => ({
    clientId,
    chargeType: "none" as const,
    chargeDurationMinutes: 0,
  })),
});

const dto = (
  financialDecision: LessonFinancialDecision,
): FinancialTransitionPreviewDto => ({
  operation: "cancel",
  expectedVersion: 1,
  reasonText: "Точная проверка клиентов",
  financialDecision,
});

const rescheduleDto = (
  financialDecision: LessonFinancialDecision,
): TransitionPreviewDto => ({
  operation: "reschedule",
  expectedVersion: 1,
  reasonText: "Точная проверка клиентов",
  successor: { scheduledAt: "2026-09-05T09:00:00.000Z" },
  sourceFinancialDecision: decision(
    financialDecision.clientDecisions?.map(({ clientId }) => clientId) ?? [],
  ),
  successorFinancialDecision: financialDecision,
});

const actor = { userId: "director-a", role: "director" as const };

const preparationWith = (
  settlement: LessonSettlementPort,
  policy: CrmPolicy = new CrmPolicy(),
) => new LessonTransitionPreparationService(
  {} as DatabaseService,
  policy,
  new LessonRequiredFieldValidator(),
  {} as ScheduleConstraintEngine,
  settlement,
  {} as SubscriptionReservationService,
  {} as LessonTransitionFinancialService,
  {
    loadEffectiveTeacherRate: jest.fn(async () => 700),
  } as unknown as LessonCommandRepository,
);

describe("lesson transition exact frozen clients", () => {
  it.each([
    ["student cancel", individualSource("student", studentA), "cancel", [studentA]],
    ["lead reschedule", individualSource("lead", leadA), "reschedule", [leadA]],
    ["group reschedule minus exclusions", groupSource(), "reschedule", [studentA, studentB]],
  ] as const)("passes the exact set for %s", async (_name, source, operation, expectedIds) => {
    const settlement = {
      resolvePlannedPlan: jest.fn(async (_client, input) => ({
        decision: {
          ...input.decision,
          teacherCompensationSource: "automatic" as const,
        },
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      })),
    } as unknown as LessonSettlementPort;
    const preparation = preparationWith(settlement);

    await preparation.resolvedEffectiveTransitionDto(
      {} as PoolClient,
      actor,
      source,
      operation as TransitionOperation,
      operation === "reschedule"
        ? rescheduleDto(decision([...expectedIds]))
        : dto(decision([...expectedIds])),
    );

    expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ requiredClientIds: [...expectedIds] }),
    );
  });

  it("builds an exact no-charge completed-reschedule reversal after raw authorization", async () => {
    const events: string[] = [];
    const source = { ...groupSource(), lifecycleState: "successfully_completed" as const };
    const policy = {
      assertCanSupplyTeacherCompensation: jest.fn(() => events.push("raw-authorization")),
      canManageTeacherCompensation: jest.fn(() => true),
      teacherCompensationMutationAuthorization: jest.fn(() => ({
        actor,
        capabilityKey: "config.commerce.manage" as const,
      })),
    } as unknown as CrmPolicy;
    const settlement = {
      resolvePlannedPlan: jest.fn(async (_client, input) => {
        events.push("resolve");
        return {
          decision: {
            ...input.decision,
            teacherCompensationSource: "automatic" as const,
          },
          settlementRevisionId: "settlement-revision",
          compensationRevisionId: "compensation-revision",
        };
      }),
    } as unknown as LessonSettlementPort;

    const resolved = await preparationWith(settlement, policy)
      .resolvedEffectiveTransitionDto(
        {} as PoolClient,
        actor,
        source,
        "reschedule",
        rescheduleDto({
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "100000",
          teacherCompensationSource: "manual",
          clientDecisions: [{ clientId: studentA }],
        }),
      );

    expect(events).toEqual(["raw-authorization", "resolve", "resolve"]);
    expect(resolved.operation).toBe("reschedule");
    if (resolved.operation !== "reschedule") throw new Error("unreachable");
    expect(resolved.sourceFinancialDecision.clientDecisions).toEqual([
      {
        clientId: studentA,
        settlementTypeKey: "free_lesson",
        chargeType: "none",
        chargeDurationMinutes: 0,
      },
      {
        clientId: studentB,
        settlementTypeKey: "free_lesson",
        chargeType: "none",
        chargeDurationMinutes: 0,
      },
    ]);
  });

  it("lets the settlement policy recompute a stored automatic transition decision", async () => {
    const manager = { userId: "manager-a", role: "manager" as const };
    const policy = {
      canManageTeacherCompensation: jest.fn(() => false),
      teacherCompensationMutationAuthorization: jest.fn(() => ({
        actor: manager,
        capabilityKey: "schedule.lesson.write" as const,
      })),
    } as unknown as CrmPolicy;
    const settlement = {
      loadPlan: jest.fn(async () => ({
        decision: {
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "standard",
          teacherCreditedDurationMinutes: 60,
          teacherCompensationSource: "automatic" as const,
        },
      })),
      resolvePlannedPlan: jest.fn(async (_client, input) => ({
        decision: {
          ...input.decision,
          teacherCompensationRuleKey: "none",
          teacherCreditedDurationMinutes: 0,
          teacherCompensationSource: "automatic" as const,
        },
        settlementRevisionId: "settlement-revision",
        compensationRevisionId: "compensation-revision",
      })),
    } as unknown as LessonSettlementPort;

    const resolved = await preparationWith(settlement, policy)
      .resolvedEffectiveTransitionDto(
        {} as PoolClient,
        manager,
        individualSource("student", studentA),
        "cancel",
        dto(decision([studentA])),
      );

    expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
      expect.anything(),
      expect.not.objectContaining({ preservedTeacherDecision: expect.anything() }),
    );
    expect(resolved.financialDecision).toMatchObject({
      settlementTypeKey: "free_lesson",
      teacherCompensationRuleKey: "none",
      teacherCreditedDurationMinutes: 0,
      teacherCompensationSource: "automatic",
    });
  });

  it.each([
    ["none", 0],
    ["fixed", 700],
  ] as const)(
    "recomputes a successor instead of copying a no-plan legacy %s teacher snapshot",
    async (legacyType, legacyValue) => {
      const manager = { userId: "manager-a", role: "manager" as const };
      const policy = {
        canManageTeacherCompensation: jest.fn(() => false),
        teacherCompensationMutationAuthorization: jest.fn(() => ({
          actor: manager,
          capabilityKey: "schedule.lesson.write" as const,
        })),
      } as unknown as CrmPolicy;
      const settlement = {
        loadPlan: jest.fn(async () => null),
        resolvePlannedPlan: jest.fn(async (_client, input) => ({
          decision: {
            ...input.decision,
            teacherCompensationSource: "automatic" as const,
            ...input.preservedTeacherDecision,
          },
          settlementRevisionId: "settlement-revision",
          compensationRevisionId: "compensation-revision",
        })),
      } as unknown as LessonSettlementPort;
      const source = individualSource("student", studentA);
      source.snapshot = {
        ...source.snapshot!,
        teacherCompensationType: legacyType,
        teacherCompensationValue: legacyValue,
      };

      const resolved = await preparationWith(settlement, policy)
        .resolvedEffectiveTransitionDto(
        {} as PoolClient,
        manager,
        source,
        "reschedule",
        rescheduleDto(decision([studentA])),
      );

      expect(settlement.resolvePlannedPlan).toHaveBeenNthCalledWith(
        2,
        expect.anything(),
        expect.not.objectContaining({ preservedTeacherDecision: expect.anything() }),
      );
      expect(resolved.operation).toBe("reschedule");
      if (resolved.operation !== "reschedule") throw new Error("unreachable");
      expect(resolved.successorFinancialDecision).toMatchObject({
        settlementTypeKey: "free_lesson",
        teacherCompensationRuleKey: "none",
        teacherCompensationSource: "automatic",
      });
    },
  );

  it.each([
    ["missing", decision([studentA]), "CLIENT_DECISION_MISSING"],
    ["duplicate", decision([studentA, studentA, studentB]), "DUPLICATE_CLIENT_DECISION"],
    ["unrelated", decision([studentA, studentB, leadA]), "UNKNOWN_LESSON_CLIENT"],
  ])("rejects %s rows in preview and commit before writes", async (
    _name,
    financialDecision,
    code,
  ) => {
    const settlement = new LessonSettlementService({} as DatabaseService);
    const preparation = preparationWith(settlement);
    const source = groupSource();
    jest.spyOn(preparation, "loadSource").mockResolvedValue(source);
    const client = { query: jest.fn() } as unknown as PoolClient;
    const database = {
      transaction: jest.fn(async (run: (client: PoolClient) => unknown) => run(client)),
    } as unknown as DatabaseService;
    const reservations = {
      lockSettlementCoverage: jest.fn(),
      terminalize: jest.fn(),
    } as unknown as SubscriptionReservationService;
    const financial = {
      previewFinancial: jest.fn(),
      applyCompletedRescheduleCorrection: jest.fn(),
      commitRescheduleFinancials: jest.fn(),
    } as unknown as LessonTransitionFinancialService;
    const preview = new LessonTransitionPreviewService(
      database,
      new CrmPolicy(),
      preparation,
      { issueLessonTransition: jest.fn() } as unknown as SubscriptionPreviewTokenService,
    );
    const commit = new LessonTransitionCommitService(
      preparation,
      financial,
      settlement,
      reservations,
      { appendTransition: jest.fn() } as unknown as LessonLifecycleRepository,
    );

    await expect(preview.previewCancel(
      actor,
      source.id,
      dto(financialDecision) as never,
    ))
      .rejects.toMatchObject({ status: 422, response: { code } });
    await expect(commit.commit(client, {
      actor,
      lessonId: source.id,
      dto: dto(financialDecision),
      operation: "cancel",
      successorId: null,
      nextVersion: 2,
    })).rejects.toMatchObject({ status: 422, response: { code } });

    expect(client.query).not.toHaveBeenCalled();
    expect(reservations.lockSettlementCoverage).not.toHaveBeenCalled();
    expect(financial.previewFinancial).not.toHaveBeenCalled();
    expect(financial.applyCompletedRescheduleCorrection).not.toHaveBeenCalled();
    expect(financial.commitRescheduleFinancials).not.toHaveBeenCalled();
  });
});
