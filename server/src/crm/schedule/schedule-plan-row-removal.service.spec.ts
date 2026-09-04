import {
  ConflictException,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import type { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import type { CrmPolicy } from "../crm.policy";
import type { SchedulePlanEndService } from "./schedule-plan-end.service";
import type { SchedulePlanRepository } from "./schedule-plan.repository";
import { FuturePlanLessonCancellationService } from "./future-plan-lesson-cancellation.service";
import type { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import type { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { SchedulePlanRowRemovalService } from "./schedule-plan-row-removal.service";

const USER_ID = "00000000-0000-4000-8000-000000000001";
const PLAN_ID = "00000000-0000-4000-8000-000000000002";
const SERIES_ID = "00000000-0000-4000-8000-000000000003";
const OTHER_SERIES_ID = "00000000-0000-4000-8000-000000000004";

const actor = { userId: USER_ID, role: "manager" as const };
const metadata = {
  idempotencyKey: "remove-row-request-0001",
  requestId: "request-remove-row-0001",
};
const plan = {
  id: PLAN_ID,
  kind: "individual" as const,
  title: "Фортепиано",
  student_id: "00000000-0000-4000-8000-000000000005",
  group_id: null,
  subscription_id: "00000000-0000-4000-8000-000000000006",
  active_from: "2026-08-01",
  active_until: null,
  status: "active" as const,
  version: 4,
};
const currentRow = {
  id: SERIES_ID,
  planId: PLAN_ID,
  version: 2,
  validFrom: "2026-08-01",
  validUntil: null,
};
const impact = {
  eligibleLessons: [
    {
      id: "00000000-0000-4000-8000-000000000011",
      version: 1,
      lifecycleState: "scheduled" as const,
      clientIds: [plan.student_id],
    },
    {
      id: "00000000-0000-4000-8000-000000000012",
      version: 1,
      lifecycleState: "scheduled" as const,
      clientIds: [plan.student_id],
    },
    {
      id: "00000000-0000-4000-8000-000000000013",
      version: 1,
      lifecycleState: "settlement_pending" as const,
      clientIds: [plan.student_id],
    },
  ],
  reservations: [
    {
      id: "00000000-0000-4000-8000-000000000021",
      lessonId: "00000000-0000-4000-8000-000000000011",
      subscriptionId: plan.subscription_id,
      version: 1,
      units: "1.00",
    },
    {
      id: "00000000-0000-4000-8000-000000000022",
      lessonId: "00000000-0000-4000-8000-000000000012",
      subscriptionId: plan.subscription_id,
      version: 1,
      units: "1.00",
    },
    {
      id: "00000000-0000-4000-8000-000000000023",
      lessonId: "00000000-0000-4000-8000-000000000013",
      subscriptionId: plan.subscription_id,
      version: 1,
      units: "1.00",
    },
  ],
  preservedTerminalLessonIds: [
    "00000000-0000-4000-8000-000000000031",
    "00000000-0000-4000-8000-000000000032",
  ],
  preservedChangedLessonIds: [
    "00000000-0000-4000-8000-000000000041",
  ],
};

type HarnessOverrides = {
  row?: typeof currentRow;
  currentSeriesIds?: string[];
  localToday?: string;
  planVersion?: number;
  verifyError?: unknown;
};

const createHarness = (overrides: HarnessOverrides = {}) => {
  const client = {
    query: jest.fn(async () => ({ rows: [] })),
  } as unknown as PoolClient;
  const lockedPlan = {
    ...plan,
    version: overrides.planVersion ?? plan.version,
  };
  const row = overrides.row ?? currentRow;
  const currentSeriesIds = overrides.currentSeriesIds ?? [
    SERIES_ID,
    OTHER_SERIES_ID,
  ];
  const repository = {
    lock: jest.fn(async () => lockedPlan),
    lockCurrentRow: jest.fn(async () => row),
    currentSeriesIds: jest.fn(async () => ({
      rows: currentSeriesIds.map((id) => ({ id })),
    })),
    localToday: jest.fn(async () => overrides.localToday ?? "2026-09-04"),
    retireRow: jest.fn(async () => ({ rows: [{ id: SERIES_ID }] })),
    bumpAfterRowRemoval: jest.fn(async () => ({ rows: [{ id: PLAN_ID }] })),
  } as unknown as SchedulePlanRepository;
  const cancellations = {
    inspectEligible: jest.fn(async () => impact),
    cancelEligible: jest.fn(async () => ({
      cancelledLessonIds: impact.eligibleLessons.map((lesson) => lesson.id),
      releasedReservationIds: impact.reservations.map((item) => item.id),
      preservedTerminalLessonIds: impact.preservedTerminalLessonIds,
      preservedChangedLessonIds: impact.preservedChangedLessonIds,
    })),
  } as unknown as FuturePlanLessonCancellationService;
  const issuedPayloads: Array<Record<string, unknown>> = [];
  const tokens = {
    issueSchedulePlanRowRemoval: jest.fn((payload) => {
      issuedPayloads.push(payload);
      return {
        token: "signed-row-preview",
        expiresAt: "2026-09-04T12:05:00.000Z",
        payload,
      };
    }),
    verifySchedulePlanRowRemoval: jest.fn(() => {
      if (overrides.verifyError) throw overrides.verifyError;
      return issuedPayloads[0];
    }),
  } as unknown as SubscriptionPreviewTokenService;
  const ending = {
    endLockedInTransaction: jest.fn(async () => ({
      endedLessons: impact.eligibleLessons.length,
      releasedReservations: impact.reservations.length,
      preservedTerminalLessons: impact.preservedTerminalLessonIds.length,
      preservedChangedLessons: impact.preservedChangedLessonIds.length,
    })),
  } as unknown as SchedulePlanEndService;
  const idempotency = new Map<
    string,
    {
      fingerprint: string;
      result: {
        version: number;
        replayed: boolean;
        resultRef: Record<string, unknown>;
        auditId: string;
        eventId: string;
      };
    }
  >();
  const platform = {
    executeVersionedMutation: jest.fn(async (command) => {
      const requestFingerprint = fingerprintPayload({
        operation: command.operation,
        aggregateType: command.aggregateType,
        aggregateId: command.aggregateId,
        expectedVersion: command.expectedVersion,
        payload: command.payload,
      });
      const existing = idempotency.get(command.idempotencyKey);
      if (existing) {
        if (existing.fingerprint !== requestFingerprint) {
          throw new ConflictException({ code: "IDEMPOTENCY_KEY_REUSED" });
        }
        return { ...existing.result, replayed: true };
      }
      const result = {
        version: 5,
        replayed: false,
        resultRef: await command.mutate(client, 5),
        auditId: "audit-row-remove",
        eventId: "outbox-row-remove",
      };
      idempotency.set(command.idempotencyKey, {
        fingerprint: requestFingerprint,
        result,
      });
      return result;
    }),
  } as unknown as PlatformIntegrityService;
  const database = {
    transaction: jest.fn((work: (target: PoolClient) => Promise<unknown>) =>
      work(client),
    ),
  } as unknown as DatabaseService;
  const service = new SchedulePlanRowRemovalService(
    platform,
    { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy,
    repository,
    database,
    tokens,
    cancellations,
    ending,
  );
  return {
    client,
    service,
    platform,
    repository,
    cancellations,
    tokens,
    ending,
  };
};

describe("SchedulePlanRowRemovalService", () => {
  it("previews only cancellable future row lessons and signs the complete impact", async () => {
    const { service, tokens } = createHarness();

    const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
      expectedVersion: 4,
      effectiveFrom: "2026-09-04",
      reasonText: "Смена преподавателя",
    });

    expect(preview.impact).toEqual({
      futureUnfinishedLessons: 3,
      terminalLessonsPreserved: 2,
      changedLessonsPreserved: 1,
      activeReservationsToRelease: 3,
      endsPlan: false,
    });
    expect(preview.effectiveFrom).toBe("2026-09-04");
    expect(tokens.issueSchedulePlanRowRemoval).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: "schedule.plan.row.remove",
        actorUserId: USER_ID,
        planId: PLAN_ID,
        seriesId: SERIES_ID,
        expectedVersion: 4,
        effectiveFrom: "2026-09-04",
        impactFingerprint: expect.stringMatching(/^[a-f0-9]{64}$/),
      }),
    );
  });

  it.each([
    ["future row start", "2026-10-01", "2026-10-01"],
    ["current row organization-local today", "2026-08-01", "2026-09-04"],
  ])("defaults removal to the %s", async (_label, validFrom, expected) => {
    const { service } = createHarness({
      row: { ...currentRow, validFrom },
      localToday: "2026-09-04",
    });

    const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
      expectedVersion: 4,
      reasonText: "Изменение расписания",
    });

    expect(preview.effectiveFrom).toBe(expected);
  });

  it("rejects a stale plan version before issuing a preview", async () => {
    const { service, tokens } = createHarness({ planVersion: 5 });

    await expect(
      service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
        expectedVersion: 4,
        effectiveFrom: "2026-09-04",
        reasonText: "Изменение расписания",
      }),
    ).rejects.toMatchObject({
      status: 409,
      response: { code: "SCHEDULE_PLAN_VERSION_STALE" },
    });
    expect(tokens.issueSchedulePlanRowRemoval).not.toHaveBeenCalled();
  });

  it("rejects a stale plan version during commit without row writes", async () => {
    const { service, repository, cancellations } = createHarness();
    const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
      expectedVersion: 4,
      effectiveFrom: "2026-09-04",
      reasonText: "Изменение расписания",
    });
    (repository.lock as jest.Mock).mockResolvedValueOnce({ ...plan, version: 5 });

    await expect(
      service.removeRow(
        actor,
        PLAN_ID,
        SERIES_ID,
        {
          expectedVersion: 4,
          effectiveFrom: "2026-09-04",
          reasonText: "Изменение расписания",
          previewToken: preview.previewToken,
          confirm: true,
        },
        metadata,
      ),
    ).rejects.toMatchObject({
      status: 409,
      response: { code: "SCHEDULE_PLAN_VERSION_STALE" },
    });
    expect(repository.retireRow).not.toHaveBeenCalled();
    expect(repository.bumpAfterRowRemoval).not.toHaveBeenCalled();
    expect(cancellations.cancelEligible).not.toHaveBeenCalled();
  });

  it("retires one row, cancels eligible lessons, and records one idempotent mutation", async () => {
    const { service, platform, repository, cancellations } = createHarness();
    const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
      expectedVersion: 4,
      effectiveFrom: "2026-09-04",
      reasonText: "Смена преподавателя",
    });

    const result = await service.removeRow(
      actor,
      PLAN_ID,
      SERIES_ID,
      {
        expectedVersion: 4,
        effectiveFrom: "2026-09-04",
        reasonText: "Смена преподавателя",
        previewToken: preview.previewToken,
        confirm: true,
      },
      metadata,
    );

    expect(result).toMatchObject({
      id: PLAN_ID,
      seriesId: SERIES_ID,
      version: 5,
      endsPlan: false,
      cancelledLessons: 3,
      releasedReservations: 3,
      replayed: false,
    });
    expect(repository.retireRow).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        planId: PLAN_ID,
        seriesId: SERIES_ID,
        effectiveFrom: "2026-09-04",
      }),
    );
    expect(repository.bumpAfterRowRemoval).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ expectedVersion: 4, version: 5 }),
    );
    expect(cancellations.cancelEligible).toHaveBeenCalledWith(
      expect.anything(),
      {
        planId: PLAN_ID,
        seriesIds: [SERIES_ID],
        effectiveFrom: "2026-09-04",
        actorUserId: USER_ID,
        reasonText: "Смена преподавателя",
      },
    );
    expect(platform.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "schedule.plan.row.remove",
        idempotencyKey: metadata.idempotencyKey,
        expectedVersion: 4,
        audit: expect.objectContaining({
          action: "crm.schedule_plan_row_removed",
          reasonText: "Смена преподавателя",
        }),
        outbox: expect.objectContaining({ type: "schedule.plan.changed" }),
      }),
    );
  });

  it("rejects a same-key cross-series replay without reporting or changing row B", async () => {
    const { service, repository } = createHarness();
    const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
      expectedVersion: 4,
      effectiveFrom: "2026-09-04",
      reasonText: "Смена преподавателя",
    });
    const command = {
      expectedVersion: 4,
      effectiveFrom: "2026-09-04",
      reasonText: "Смена преподавателя",
      previewToken: preview.previewToken,
      confirm: true as const,
    };

    const removed = await service.removeRow(
      actor,
      PLAN_ID,
      SERIES_ID,
      command,
      metadata,
    );
    expect(removed.seriesId).toBe(SERIES_ID);

    await expect(
      service.removeRow(
        actor,
        PLAN_ID,
        OTHER_SERIES_ID,
        command,
        metadata,
      ),
    ).rejects.toMatchObject({
      status: 409,
      response: { code: "IDEMPOTENCY_KEY_REUSED" },
    });
    expect(repository.retireRow).toHaveBeenCalledTimes(1);
    expect(repository.retireRow).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ seriesId: SERIES_ID }),
    );
    expect(repository.retireRow).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ seriesId: OTHER_SERIES_ID }),
    );
  });

  it("maps invalid or expired signed previews to the row-removal error", async () => {
    const { service } = createHarness({
      verifyError: new UnprocessableEntityException({
        code: "PREVIEW_TOKEN_EXPIRED",
      }),
    });

    await expect(
      service.removeRow(
        actor,
        PLAN_ID,
        SERIES_ID,
        {
          expectedVersion: 4,
          effectiveFrom: "2026-09-04",
          reasonText: "Смена преподавателя",
          previewToken: "expired",
          confirm: true,
        },
        metadata,
      ),
    ).rejects.toMatchObject({
      status: 422,
      response: { code: "SCHEDULE_PLAN_ROW_PREVIEW_INVALID" },
    });
  });

  it("delegates final-row removal to the shared plan-end transaction", async () => {
    const { service, ending, repository, cancellations } = createHarness({
      currentSeriesIds: [SERIES_ID],
    });
    const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
      expectedVersion: 4,
      effectiveFrom: "2026-09-04",
      reasonText: "Завершение курса",
    });

    const result = await service.removeRow(
      actor,
      PLAN_ID,
      SERIES_ID,
      {
        expectedVersion: 4,
        effectiveFrom: "2026-09-04",
        reasonText: "Завершение курса",
        previewToken: preview.previewToken,
        confirm: true,
      },
      metadata,
    );

    expect(result).toMatchObject({ endsPlan: true, status: "ended" });
    expect(ending.endLockedInTransaction).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        plan: expect.objectContaining({ id: PLAN_ID, version: 4 }),
        seriesIds: [SERIES_ID],
        effectiveFrom: "2026-09-04",
        actorUserId: USER_ID,
        reasonText: "Завершение курса",
        version: 5,
      }),
    );
    expect(repository.retireRow).not.toHaveBeenCalled();
    expect(cancellations.cancelEligible).not.toHaveBeenCalled();
  });

  it("rejects a changed impact fingerprint without partial row writes", async () => {
    const { service, repository, cancellations } = createHarness();
    const preview = await service.previewRemoveRow(actor, PLAN_ID, SERIES_ID, {
      expectedVersion: 4,
      effectiveFrom: "2026-09-04",
      reasonText: "Смена преподавателя",
    });
    (cancellations.inspectEligible as jest.Mock).mockResolvedValueOnce({
      ...impact,
      eligibleLessons: impact.eligibleLessons.slice(1),
    });

    await expect(
      service.removeRow(
        actor,
        PLAN_ID,
        SERIES_ID,
        {
          expectedVersion: 4,
          effectiveFrom: "2026-09-04",
          reasonText: "Смена преподавателя",
          previewToken: preview.previewToken,
          confirm: true,
        },
        metadata,
      ),
    ).rejects.toMatchObject({
      status: 422,
      response: { code: "SCHEDULE_PLAN_ROW_PREVIEW_INVALID" },
    });
    expect(repository.retireRow).not.toHaveBeenCalled();
    expect(repository.bumpAfterRowRemoval).not.toHaveBeenCalled();
    expect(cancellations.cancelEligible).not.toHaveBeenCalled();
  });
});

describe("FuturePlanLessonCancellationService", () => {
  it("appends system cancellation facts and releases only active reservations", async () => {
    const repository = {
      futureLessonCancellationImpact: jest.fn(async () => impact),
      cancelLesson: jest.fn(async (_client, _lessonId, version) => ({
        rows: [{ version: version + 1 }],
      })),
    } as unknown as SchedulePlanRepository;
    const lifecycle = {
      appendTransition: jest.fn(async () => ({ rows: [] })),
    } as unknown as LessonLifecycleRepository;
    const reservations = {
      releaseForLessons: jest.fn(async () => impact.reservations.length),
    } as unknown as SubscriptionReservationService;
    const service = new FuturePlanLessonCancellationService(
      repository,
      lifecycle,
      reservations,
    );

    const result = await service.cancelEligible({} as PoolClient, {
      planId: PLAN_ID,
      seriesIds: [SERIES_ID],
      effectiveFrom: "2026-09-04",
      actorUserId: USER_ID,
      reasonText: "Причина оператора остаётся только в аудите",
    });

    expect(result).toEqual({
      cancelledLessonIds: impact.eligibleLessons.map((lesson) => lesson.id),
      releasedReservationIds: impact.reservations.map((item) => item.id),
      preservedTerminalLessonIds: impact.preservedTerminalLessonIds,
      preservedChangedLessonIds: impact.preservedChangedLessonIds,
    });
    expect(lifecycle.appendTransition).toHaveBeenCalledTimes(3);
    expect(lifecycle.appendTransition).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        reasonCode: "schedule.plan.row.remove",
        reasonText: "Строка постоянного расписания удалена",
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
          clientDecisions: [
            {
              clientId: plan.student_id,
              chargeType: "none",
              chargeDurationMinutes: 0,
            },
          ],
        },
      }),
    );
    expect(reservations.releaseForLessons).toHaveBeenCalledWith(
      expect.anything(),
      impact.eligibleLessons.map((lesson) => lesson.id),
    );
  });

  it("fails a raced lesson version before reporting released reservations", async () => {
    const repository = {
      futureLessonCancellationImpact: jest.fn(async () => impact),
      cancelLesson: jest.fn(async () => ({ rows: [] })),
    } as unknown as SchedulePlanRepository;
    const lifecycle = {
      appendTransition: jest.fn(),
    } as unknown as LessonLifecycleRepository;
    const reservations = {
      releaseForLessons: jest.fn(),
    } as unknown as SubscriptionReservationService;
    const service = new FuturePlanLessonCancellationService(
      repository,
      lifecycle,
      reservations,
    );

    await expect(
      service.cancelEligible({} as PoolClient, {
        planId: PLAN_ID,
        seriesIds: [SERIES_ID],
        effectiveFrom: "2026-09-04",
        actorUserId: USER_ID,
        reasonText: "Гонка",
      }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(lifecycle.appendTransition).not.toHaveBeenCalled();
    expect(reservations.releaseForLessons).not.toHaveBeenCalled();
  });
});
