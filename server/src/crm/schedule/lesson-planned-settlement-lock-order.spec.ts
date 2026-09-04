import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import type { VersionedMutationCommand } from "../../platform/platform-integrity.types";
import type { LessonSettlementService } from "../commerce/lesson-settlement.service";
import type { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import type { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { CrmPolicy } from "../crm.policy";
import type { ScheduleConstraintEngine } from "./constraint-engine.service";
import type { LessonCommandRepository } from "./lesson-command.repository";
import { LessonPlannedSettlementCommandService } from "./lesson-planned-settlement-command.service";

const actor = {
  userId: "00000000-0000-4000-8000-000000000001",
  role: "director" as const,
};
const lessonId = "00000000-0000-4000-8000-000000000002";
const fingerprint = "a".repeat(64);
const calculated = {
  currentPlanVersion: 1,
  prepared: {
    decision: {},
    settlementRevisionId: "settlement-revision",
    compensationRevisionId: "compensation-revision",
  },
  financial: {},
  reservations: { before: [], after: [] },
  warnings: [],
  fingerprint,
  resourceChange: null,
};
type TestablePlannedService = {
  calculateSettlementPlanChange(
    client: PoolClient,
    actor: unknown,
    lessonId: string,
    dto: unknown,
  ): Promise<typeof calculated>;
};

describe("planned settlement lock ordering", () => {
  it("acquires the coordination gate before preview source work", async () => {
    const events: string[] = [];
    const client = lockRecordingClient(events);
    const database = {
      transaction: jest.fn(async (work: (target: PoolClient) => unknown) =>
        work(client)),
    } as unknown as DatabaseService;
    const service = plannedService({
      database,
      previewTokens: {
        issueLessonTransition: jest.fn(() => ({
          token: "signed",
          expiresAt: "2026-09-04T12:00:00.000Z",
        })),
      } as unknown as SubscriptionPreviewTokenService,
    });
    jest.spyOn(
      service as unknown as TestablePlannedService,
      "calculateSettlementPlanChange",
    )
      .mockImplementation(async () => {
        events.push("calculate");
        return calculated;
      });

    await service.previewSettlementPlan(actor, lessonId, {
      expectedVersion: 1,
      reasonText: "Проверка порядка preview",
      financialDecision: {},
    } as never);

    expect(events.slice(0, 3)).toEqual([
      "coordination-gate",
      "savepoint",
      "calculate",
    ]);
  });

  it("acquires the coordination gate before aggregate version advance", async () => {
    const events: string[] = [];
    const client = lockRecordingClient(events);
    const platform = {
      executeVersionedMutation: jest.fn(
        async (command: VersionedMutationCommand<Record<string, unknown>>) => {
          await command.beforeVersionAdvance?.(client);
          events.push("version-advance");
          const resultRef = await command.mutate(client, 2);
          return {
            resultRef,
            version: 2,
            replayed: false,
            auditId: "audit",
            eventId: "event",
          };
        },
      ),
    } as unknown as PlatformIntegrityService;
    const service = plannedService({
      platform,
      settlement: {
        replacePlan: jest.fn().mockResolvedValue(2),
      } as unknown as LessonSettlementService,
      previewTokens: {
        verifyLessonTransition: jest.fn(() => ({
          operation: "planned-settlement",
          actorUserId: actor.userId,
          lessonId,
          expectedVersion: 1,
          transitionFingerprint: fingerprint,
        })),
      } as unknown as SubscriptionPreviewTokenService,
      repository: {
        touchSettlementPlan: jest.fn().mockResolvedValue({
          rows: [{ version: 2 }],
        }),
      } as unknown as LessonCommandRepository,
    });
    jest.spyOn(
      service as unknown as TestablePlannedService,
      "calculateSettlementPlanChange",
    )
      .mockImplementation(async () => {
        events.push("calculate");
        return calculated;
      });

    await service.updateSettlementPlan(actor, lessonId, {
      expectedVersion: 1,
      reasonText: "Проверка порядка commit",
      financialDecision: {},
      previewToken: "signed",
      confirm: true,
    } as never, {
      idempotencyKey: "planned-lock-order",
      requestId: "planned-lock-order-request",
    });

    expect(events.slice(0, 3)).toEqual([
      "coordination-gate",
      "version-advance",
      "calculate",
    ]);
  });
});

function lockRecordingClient(events: string[]): PoolClient {
  return {
    query: jest.fn(async (query: string, params?: unknown[]) => {
      if (params?.[0] === "commerce:multi-lesson-settlement") {
        events.push("coordination-gate");
      } else if (query.trim().toLowerCase().startsWith("savepoint")) {
        events.push("savepoint");
      }
      return { rows: [] };
    }),
  } as unknown as PoolClient;
}

function plannedService(overrides: {
  database?: DatabaseService;
  platform?: PlatformIntegrityService;
  settlement?: LessonSettlementService;
  previewTokens?: SubscriptionPreviewTokenService;
  repository?: LessonCommandRepository;
}) {
  return new LessonPlannedSettlementCommandService(
    overrides.database ?? ({} as DatabaseService),
    overrides.platform ?? ({} as PlatformIntegrityService),
    new CrmPolicy(),
    {} as SubscriptionReservationService,
    overrides.settlement ?? ({} as LessonSettlementService),
    overrides.previewTokens ?? ({} as SubscriptionPreviewTokenService),
    overrides.repository ?? ({} as LessonCommandRepository),
    {} as ScheduleConstraintEngine,
  );
}
