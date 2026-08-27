import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import type { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import type { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import type { LessonSettlementService } from "../commerce/lesson-settlement.service";
import type { CrmPolicy } from "../crm.policy";
import type { SchedulePlanRowDto } from "../dto/schedule-plan.dto";
import type { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import type { LessonSeriesCommandService } from "./lesson-series-command.service";
import { SchedulePlanDefinitionService } from "./schedule-plan-definition.service";
import { SchedulePlanEndService } from "./schedule-plan-end.service";
import { SchedulePlanMutationService } from "./schedule-plan-mutation.service";
import { SchedulePlanOverlapAnalyzer } from "./schedule-plan-overlap-analyzer";
import { SchedulePlanQueryService } from "./schedule-plan-query.service";
import type { SchedulePlanRepository } from "./schedule-plan.repository";
import type { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";

const actor: ActorContext = { userId: "actor-a", role: "manager" };
const metadata = {
  idempotencyKey: "schedule-plan-test",
  requestId: "request-a",
};

const scheduleRow = (
  overrides: Partial<SchedulePlanRowDto> = {},
): SchedulePlanRowDto => ({
  teacherId: "teacher-a",
  roomId: "room-a",
  branchId: "branch-a",
  weekday: 1,
  beginTime: "10:00",
  durationMinutes: 60,
  financialDecision: {
    settlementTypeKey: "lesson",
    teacherCompensationRuleKey: "none",
  },
  ...overrides,
});

describe("Schedule plan semantic owners", () => {
  it("locks plan subjects and resources in sorted unique order before subscriptions", async () => {
    const advisoryKeys: string[] = [];
    let subscriptionSql = "";
    const client = {
      query: jest.fn(async (sql: string, values?: unknown[]) => {
        if (sql.includes("pg_advisory_xact_lock")) {
          advisoryKeys.push(String(values?.[0]));
          return { rows: [] };
        }
        if (sql.includes("from app.subscriptions")) {
          subscriptionSql = sql;
          return {
            rows: [
              {
                id: "subscription-a",
                student_id: "student-a",
                status: "active",
              },
              {
                id: "subscription-b",
                student_id: "student-b",
                status: "active",
              },
            ],
          };
        }
        if (sql.includes("from app.students"))
          return { rows: [{ valid: true }] };
        if (sql.includes("from app.groups"))
          return { rows: [{ member_count: "2" }] };
        return { rows: [] };
      }),
    } as unknown as PoolClient;
    const definition = new SchedulePlanDefinitionService(
      {} as SchedulePlanRepository,
    );

    await definition.lockAndValidate(client, {
      planId: "plan-a",
      kind: "group",
      studentId: null,
      groupId: "group-a",
      subscriptionId: null,
      participants: [
        { studentId: "student-b", subscriptionId: "subscription-b" },
        { studentId: "student-a", subscriptionId: "subscription-a" },
      ],
      rows: [scheduleRow(), scheduleRow()],
    });

    expect(advisoryKeys).toEqual(
      [
        ...new Set([
          "plan:plan-a",
          "group:group-a",
          "client:student:student-a",
          "client:student:student-b",
          "subscription:subscription-a",
          "subscription:subscription-b",
          "branch:branch-a",
          "room:room-a",
          "teacher:teacher-a",
        ]),
      ].sort(),
    );
    expect(subscriptionSql).toMatch(/order by id for update/);
  });

  it("preserves update lock and write ordering", async () => {
    const updateEvents: string[] = [];
    const client = {} as PoolClient;
    const platform = {
      executeVersionedMutation: jest.fn(
        async ({
          mutate,
        }: {
          mutate: (client: PoolClient, version: number) => Promise<unknown>;
        }) => ({
          version: 2,
          replayed: false,
          resultRef: await mutate(client, 2),
        }),
      ),
    } as unknown as PlatformIntegrityService;
    const definition = {
      assertRows: jest.fn(),
      prepareUpdate: jest.fn(async () => {
        updateEvents.push(
          "plan-lock",
          "participant-lock",
          "resource-locks",
          "subscription-lock",
          "active-series-read",
        );
        return {
          plan: {
            kind: "group",
            student_id: null,
            group_id: "group-a",
            title: "Group",
          },
          participants: [
            { studentId: "student-a", subscriptionId: "subscription-a" },
          ],
          subscriptionId: null,
          activeUntil: null,
          studentIds: ["student-a"],
          activeSeries: [{ id: "series-old" }],
          effectiveFrom: "2026-09-01",
        };
      }),
      seriesId: jest.fn(() => "series-new"),
      lessonIds: jest.fn(async () => ["lesson-new"]),
    } as unknown as SchedulePlanDefinitionService;
    const repository = {
      insertSeries: jest.fn(async () =>
        updateEvents.push("insert-continuations"),
      ),
      retireSeries: jest.fn(async () => updateEvents.push("retire-old-series")),
      replaceParticipants: jest.fn(async () =>
        updateEvents.push("replace-participants"),
      ),
      updatePlan: jest.fn(async () => updateEvents.push("update-plan")),
    } as unknown as SchedulePlanRepository;
    const series = {
      validatePlanRow: jest.fn(async () =>
        updateEvents.push("validate-new-series"),
      ),
    } as unknown as LessonSeriesCommandService;
    const materializer = {
      materializePlanSeries: jest.fn(async () =>
        updateEvents.push("materialize-new-series"),
      ),
    } as unknown as ScheduleSeriesMaterializerService;
    const settlement = {
      preparePlan: jest.fn(async () => ({
        decision: {},
        settlementRevisionId: null,
        compensationRevisionId: null,
      })),
    } as unknown as LessonSettlementService;
    const policy = { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy;
    const mutation = new SchedulePlanMutationService(
      platform,
      policy,
      repository,
      series,
      materializer,
      settlement,
      definition,
    );

    const lockSpy = jest
      .spyOn(require("./schedule-locks"), "lockSchedulePlanSeries")
      .mockImplementation(async () => {
        updateEvents.push("series-locks");
      });
    try {
      await mutation.update(
        actor,
        "plan-a",
        {
          expectedVersion: 1,
          effectiveFrom: "2026-09-01",
          participants: [
            { studentId: "student-a", subscriptionId: "subscription-a" },
          ],
          rows: [scheduleRow({ seriesId: "series-old" })],
        },
        metadata,
      );
    } finally {
      lockSpy.mockRestore();
    }

    expect(updateEvents).toEqual([
      "plan-lock",
      "participant-lock",
      "resource-locks",
      "subscription-lock",
      "active-series-read",
      "series-locks",
      "insert-continuations",
      "retire-old-series",
      "replace-participants",
      "update-plan",
      "validate-new-series",
      "materialize-new-series",
    ]);
  });

  it("preserves end lock, fingerprint, history, and reservation ordering", async () => {
    const endEvents: string[] = [];
    const client = {} as PoolClient;
    const impact = {
      series: [
        {
          id: "series-a",
          version: 1,
          validFrom: "2026-01-01",
          validUntil: null,
        },
      ],
      lessons: [
        { id: "lesson-a", version: 1, lifecycleState: "scheduled" as const },
      ],
      reservations: [],
      terminalLessonCount: 1,
    };
    const plan = {
      id: "plan-a",
      kind: "individual" as const,
      title: "Plan",
      student_id: "student-a",
      group_id: null,
      subscription_id: "subscription-a",
      active_from: "2026-01-01",
      active_until: null,
      status: "active" as const,
      version: 1,
    };
    const expectedFingerprint = fingerprintPayload({
      planId: plan.id,
      expectedVersion: 1,
      lastDate: "2026-09-01",
      reasonText: "reason",
      series: impact.series,
      lessons: impact.lessons,
      reservations: impact.reservations,
      terminalLessonCount: impact.terminalLessonCount,
    });
    const definition = {
      normalizeEnd: jest.fn(() => ({
        expectedVersion: 1,
        lastDate: "2026-09-01",
        reasonText: "reason",
      })),
      assertEndable: jest.fn(async () => endEvents.push("local-date-check")),
    } as unknown as SchedulePlanDefinitionService;
    const repository = {
      lock: jest.fn(async () => {
        endEvents.push("plan-lock");
        return plan;
      }),
      currentSeriesIds: jest.fn(async () => {
        endEvents.push("current-series-read");
        return { rows: [{ id: "series-a" }] };
      }),
      endImpact: jest.fn(async () => {
        endEvents.push("locked-impact");
        return impact;
      }),
      finish: jest.fn(async () => {
        endEvents.push("finish-plan");
        return { rows: [{ id: "plan-a" }] };
      }),
      cancelLesson: jest.fn(async () => {
        endEvents.push("cancel-lessons");
        return { rows: [{ version: 2 }] };
      }),
    } as unknown as SchedulePlanRepository;
    const tokens = {
      verifySchedulePlanEnd: jest.fn(() => ({
        actorUserId: actor.userId,
        planId: "plan-a",
        expectedVersion: 1,
        lastDate: "2026-09-01",
        get impactFingerprint() {
          endEvents.push("fingerprint-check");
          return expectedFingerprint;
        },
      })),
    } as unknown as SubscriptionPreviewTokenService;
    const lifecycle = {
      appendTransition: jest.fn(async () =>
        endEvents.push("append-transitions"),
      ),
    } as unknown as LessonLifecycleRepository;
    const reservations = {
      releaseForLessons: jest.fn(async () => {
        endEvents.push("release-reservations");
        return 0;
      }),
    } as unknown as SubscriptionReservationService;
    const platform = {
      executeVersionedMutation: jest.fn(
        async ({
          mutate,
        }: {
          mutate: (client: PoolClient, version: number) => Promise<unknown>;
        }) => ({
          version: 2,
          replayed: false,
          resultRef: await mutate(client, 2),
        }),
      ),
    } as unknown as PlatformIntegrityService;
    const ending = new SchedulePlanEndService(
      platform,
      { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy,
      repository,
      {} as DatabaseService,
      tokens,
      lifecycle,
      reservations,
      definition,
    );
    const lockSpy = jest
      .spyOn(require("./schedule-locks"), "lockSchedulePlanSeries")
      .mockImplementation(async () => {
        endEvents.push("series-locks");
      });
    try {
      await ending.end(
        actor,
        "plan-a",
        {
          expectedVersion: 1,
          lastDate: "2026-09-01",
          reasonText: "reason",
          previewToken: "preview-token",
          confirm: true,
        },
        metadata,
      );
    } finally {
      lockSpy.mockRestore();
    }

    expect(endEvents).toEqual([
      "plan-lock",
      "local-date-check",
      "current-series-read",
      "series-locks",
      "locked-impact",
      "fingerprint-check",
      "finish-plan",
      "cancel-lessons",
      "append-transitions",
      "release-reservations",
    ]);
  });

  it("validates keyset trays and adds symmetric cross-row violations per student", async () => {
    const repository = {
      trayPage: jest.fn(),
    } as unknown as SchedulePlanRepository;
    const queries = new SchedulePlanQueryService(repository);
    await expect(
      queries.tray(actor, "plan-a", { direction: "next" }),
    ).rejects.toMatchObject({
      response: { code: "SCHEDULE_PLAN_TRAY_CURSOR_REQUIRED" },
    });
    await expect(
      queries.tray(actor, "plan-a", { cursor: "broken" }),
    ).rejects.toMatchObject({
      response: { code: "SCHEDULE_PLAN_TRAY_CURSOR_INVALID" },
    });

    const cursor = Buffer.from(
      JSON.stringify({
        scheduledAt: "2026-09-01T10:00:00.000Z",
        id: "00000000-0000-4000-8000-000000000001",
      }),
      "utf8",
    ).toString("base64url");
    (repository.trayPage as jest.Mock).mockResolvedValue([
      trayRow(
        "00000000-0000-4000-8000-000000000003",
        "2026-09-01T12:00:00.000Z",
      ),
      trayRow(
        "00000000-0000-4000-8000-000000000002",
        "2026-09-01T11:00:00.000Z",
      ),
    ]);
    const page = await queries.tray(actor, "plan-a", {
      cursor,
      direction: "previous",
      limit: 99,
    });
    expect(repository.trayPage).toHaveBeenCalledWith(
      actor,
      "plan-a",
      "previous",
      {
        scheduledAt: "2026-09-01T10:00:00.000Z",
        id: "00000000-0000-4000-8000-000000000001",
      },
      40,
    );
    expect(page.items.map((item) => item.id)).toEqual([
      "00000000-0000-4000-8000-000000000002",
      "00000000-0000-4000-8000-000000000003",
    ]);

    const rows = [scheduleRow(), scheduleRow({ beginTime: "10:30" })];
    const previews = [0, 1].map((index) => ({
      index,
      occurrences: [
        {
          startAt:
            index === 0
              ? "2026-09-01T10:00:00.000Z"
              : "2026-09-01T10:30:00.000Z",
          endAt:
            index === 0
              ? "2026-09-01T11:00:00.000Z"
              : "2026-09-01T11:30:00.000Z",
        },
      ],
      failures: [] as Array<Record<string, unknown>>,
      suggestions: [],
    }));
    new SchedulePlanOverlapAnalyzer().addCrossRowViolations(
      rows,
      previews as never,
      ["student-a", "student-b"],
    );
    expect(previews.map((preview) => preview.failures)).toHaveLength(2);
    for (const [index, preview] of previews.entries()) {
      expect(preview.failures).toHaveLength(2);
      expect(preview.failures.map((failure) => failure.studentId)).toEqual([
        "student-a",
        "student-b",
      ]);
      for (const failure of preview.failures as Array<{
        violations: Array<{
          conflictingRowIndexes: number[];
          ruleIds: string[];
        }>;
      }>) {
        expect(
          failure.violations.every(
            (violation) => violation.ruleIds[0] === "schedule_plan.rows",
          ),
        ).toBe(true);
        expect(
          failure.violations.every(
            (violation) => violation.conflictingRowIndexes[0] === 1 - index,
          ),
        ).toBe(true);
      }
    }
  });
});

const trayRow = (id: string, scheduledAt: string) => ({
  id,
  scheduled_at: scheduledAt,
  local_date: scheduledAt.slice(0, 10),
  local_time: scheduledAt.slice(11, 16),
  lifecycle_state: "scheduled",
  predecessor_id: null,
  successor_id: null,
  teacher_id: null,
  teacher_name: null,
  room_id: null,
  room_name: null,
  markers: [],
});
