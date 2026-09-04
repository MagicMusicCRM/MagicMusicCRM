import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import type { DatabaseService } from "../../db/database.service";
import type { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import type { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import type { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import type { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { CrmPolicy } from "../crm.policy";
import type { SchedulePlanRowDto } from "../dto/schedule-plan.dto";
import type { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { SchedulePlanConstraintPreviewService } from "./schedule-plan-constraint-preview.service";
import { SchedulePlanDefinitionService } from "./schedule-plan-definition.service";
import { SchedulePlanEndService } from "./schedule-plan-end.service";
import { SchedulePlanMutationService } from "./schedule-plan-mutation.service";
import { SchedulePlanOverlapAnalyzer } from "./schedule-plan-overlap-analyzer";
import { SchedulePlanQueryService } from "./schedule-plan-query.service";
import { SchedulePlanRepository } from "./schedule-plan.repository";
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
  it("recomputes stored automatic recurring pay while exempting only an unchanged legacy row", async () => {
    const client = {} as PoolClient;
    const settlement = {
      resolvePlannedPlan: jest.fn(async (_client, input) => ({
        decision: {
          ...input.decision,
          teacherCompensationRuleKey: "none",
          teacherCreditedDurationMinutes: 0,
          teacherCompensationSource: "automatic",
        },
        settlementRevisionId: "new-settlement",
        compensationRevisionId: "new-compensation",
      })),
    } as unknown as LessonSettlementService;
    const policy = {
      assertCanSupplyTeacherCompensation: jest.fn(),
      canManageTeacherCompensation: jest.fn(() => false),
      teacherCompensationMutationAuthorization: jest.fn(() => ({
        actor,
        capabilityKey: "schedule.lesson.write" as const,
      })),
    } as unknown as CrmPolicy;
    const service = new SchedulePlanConstraintPreviewService(
      policy,
      {} as DatabaseService,
      {} as SchedulePlanDefinitionService,
      {} as LessonSeriesCommandService,
      settlement,
      {} as SubscriptionPreviewTokenService,
    );
    const automatic = {
      id: "series-a",
      settlement_revision_id: "old-settlement",
      compensation_revision_id: "old-compensation",
      planned_financial_decision: {
        settlementTypeKey: "lesson",
        teacherCompensationRuleKey: "standard",
        teacherCreditedDurationMinutes: 60,
        teacherCompensationSource: "automatic" as const,
        clientDecisions: [{ clientId: "student-a" }],
      },
    };

    await service.prepareRows(
      client,
      actor,
      [scheduleRow({
        seriesId: "series-a",
        durationMinutes: 30,
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "standard",
          teacherCreditedDurationMinutes: 60,
          teacherCompensationSource: "automatic",
          clientDecisions: [{ clientId: "student-a" }],
        },
      })],
      ["student-a"],
      { activeSeries: [automatic] } as never,
    );

    expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
      client,
      expect.objectContaining({
        durationMinutes: 30,
        requiredClientIds: ["student-a"],
      }),
    );
    expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
      client,
      expect.not.objectContaining({ preservedTeacherDecision: expect.anything() }),
    );

    (settlement.resolvePlannedPlan as jest.Mock).mockClear();
    const legacyDecision = {
      settlementTypeKey: "lesson",
      teacherCompensationRuleKey: "standard",
    };
    await service.prepareRows(
      client,
      actor,
      [scheduleRow({
        seriesId: "series-a",
        financialDecision: legacyDecision,
      })],
      ["student-a"],
      {
        activeSeries: [{
          ...automatic,
          planned_financial_decision: legacyDecision,
        }],
      } as never,
    );
    expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
      client,
      expect.not.objectContaining({ requiredClientIds: expect.anything() }),
    );
  });

  it.each([
    ["missing", undefined],
    ["unrelated", [{ clientId: "student-x" }]],
    ["exact", [{ clientId: "student-a" }, { clientId: "student-b" }]],
  ] as const)(
    "requires exact clients for a changed legacy recurring row with %s decisions",
    async (_name, clientDecisions) => {
      const settlement = {
        resolvePlannedPlan: jest.fn(async (_client, input) => ({
          decision: { ...input.decision, teacherCompensationSource: "manual" },
          settlementRevisionId: "new-settlement",
          compensationRevisionId: "new-compensation",
        })),
      } as unknown as LessonSettlementService;
      const service = new SchedulePlanConstraintPreviewService(
        {
          assertCanSupplyTeacherCompensation: jest.fn(),
          canManageTeacherCompensation: jest.fn(() => false),
          teacherCompensationMutationAuthorization: jest.fn(() => ({
            actor,
            capabilityKey: "schedule.lesson.write" as const,
          })),
        } as unknown as CrmPolicy,
        {} as DatabaseService,
        {} as SchedulePlanDefinitionService,
        {} as LessonSeriesCommandService,
        settlement,
        {} as SubscriptionPreviewTokenService,
      );
      await service.prepareRows(
        {} as PoolClient,
        actor,
        [scheduleRow({
          seriesId: "series-a",
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "standard",
            ...(clientDecisions ? { clientDecisions: [...clientDecisions] } : {}),
          },
        })],
        ["student-a", "student-b"],
        {
          activeSeries: [{
            id: "series-a",
            settlement_revision_id: "old-settlement",
            compensation_revision_id: "old-compensation",
            planned_financial_decision: {
              settlementTypeKey: "lesson",
              teacherCompensationRuleKey: "standard",
            },
          }],
        } as never,
      );
      expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          requiredClientIds: ["student-a", "student-b"],
        }),
      );
    },
  );

  it.each(["create", "update"] as const)(
    "rejects raw %s teacher compensation before platform integrity",
    async (operation) => {
      const platform = {
        executeVersionedMutation: jest.fn(async () => ({
          version: 1,
          replayed: false,
          resultRef: {},
        })),
      } as unknown as PlatformIntegrityService;
      const definition = {
        normalizeCreate: jest.fn((dto) => dto),
        planId: jest.fn(() => "plan-a"),
        assertRows: jest.fn(),
      } as unknown as SchedulePlanDefinitionService;
      const mutation = new SchedulePlanMutationService(
        platform,
        new CrmPolicy(),
        {} as SchedulePlanRepository,
        {} as LessonSeriesCommandService,
        {} as ScheduleSeriesMaterializerService,
        definition,
        {} as SchedulePlanConstraintPreviewService,
      );
      const rows = [
        scheduleRow({
          financialDecision: {
            settlementTypeKey: "free_lesson",
          } as SchedulePlanRowDto["financialDecision"],
        }),
        scheduleRow({
          beginTime: "11:00",
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "fixed",
            teacherCompensationValueMinor: "50000",
            teacherCreditedDurationMinutes: 30,
            teacherCompensationSource: "manual",
          },
        }),
      ];

      const result = operation === "create"
        ? mutation.create(actor, {
            kind: "individual",
            title: "Plan",
            studentId: "student-a",
            activeFrom: "2026-09-01",
            rows,
          }, metadata)
        : mutation.update(actor, "plan-a", {
            expectedVersion: 1,
            effectiveFrom: "2026-09-01",
            rows,
          }, metadata);

      await expect(result).rejects.toMatchObject({
        status: 403,
        response: { code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED" },
      });
      expect(platform.executeVersionedMutation).not.toHaveBeenCalled();
      expect(definition.normalizeCreate).not.toHaveBeenCalled();
      expect(definition.assertRows).not.toHaveBeenCalled();
    },
  );

  it.each(["create", "update"] as const)(
    "rejects raw %s preview teacher compensation before a transaction",
    async (operation) => {
      const database = {
        transaction: jest.fn(),
      } as unknown as DatabaseService;
      const definition = {
        normalizeCreate: jest.fn((dto) => dto),
        assertRows: jest.fn(),
      } as unknown as SchedulePlanDefinitionService;
      const previews = new SchedulePlanConstraintPreviewService(
        new CrmPolicy(),
        database,
        definition,
        {} as LessonSeriesCommandService,
        {} as LessonSettlementService,
        {} as SubscriptionPreviewTokenService,
      );
      const rows = [scheduleRow({
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationSource: "manual",
        } as SchedulePlanRowDto["financialDecision"],
      })];

      const result = operation === "create"
        ? previews.previewConstraints(actor, {
            kind: "individual",
            title: "Plan",
            studentId: "student-a",
            activeFrom: "2026-09-01",
            rows,
          })
        : previews.previewUpdateConstraints(actor, "plan-a", {
            expectedVersion: 1,
            effectiveFrom: "2026-09-01",
            rows,
          });

      await expect(result).rejects.toMatchObject({
        status: 403,
        response: { code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED" },
      });
      expect(database.transaction).not.toHaveBeenCalled();
      expect(definition.normalizeCreate).not.toHaveBeenCalled();
      expect(definition.assertRows).not.toHaveBeenCalled();
    },
  );

  it.each([
    [0, 13, 0, 13],
    [13, 0, 13, 0],
    [3, 30, 3, 21],
    [30, 3, 21, 3],
    [30, 30, 12, 12],
  ])("fills the initial tray with %i past and %i future lessons", async (
    past, future, expectedPast, expectedFuture,
  ) => {
    const previous = Array.from({length: past}, (_, i) => trayRow(
      `00000000-0000-4000-8000-${String(100 - i).padStart(12, '0')}`,
      new Date(Date.UTC(2026, 0, 31 - i, 12)).toISOString(),
    ));
    const next = Array.from({length: future}, (_, i) => trayRow(
      `00000000-0000-4000-8000-${String(101 + i).padStart(12, '0')}`,
      new Date(Date.UTC(2026, 1, 1 + i, 12)).toISOString(),
    ));
    const repository = {trayPage: jest.fn(async (
      _actor: ActorContext, _plan: string, direction: string,
      _cursor: unknown, limit: number,
    ) => (direction === 'previous' ? previous : next).slice(0, limit + 1))};
    const service = new SchedulePlanQueryService(repository as unknown as SchedulePlanRepository);
    const page = await service.tray(actor, 'plan-a', {limit: 24});
    expect(page.items.map((item) => item.id)).toEqual([
      ...previous.slice(0, expectedPast).reverse(), ...next.slice(0, expectedFuture),
    ].map((item) => item.id));
    expect(page.hasPrevious).toBe(past > expectedPast);
    expect(page.hasNext).toBe(future > expectedFuture);
    expect(page.previousCursor === null).toBe(!page.hasPrevious);
    expect(page.nextCursor === null).toBe(!page.hasNext);
  });

  it("rejects a centuries-long historical range before occurrence expansion", async () => {
    const client = {
      query: jest.fn(async (sql: string) => {
        expect(sql).not.toContain("generate_series");
        return {
          rows: [{ id: "branch-a", local_today: "2026-08-29" }],
        };
      }),
    } as unknown as PoolClient;
    const series = new LessonSeriesCommandService(
      {} as PlatformIntegrityService,
      {} as CrmPolicy,
      {} as never,
      {} as never,
      {} as never,
      {} as LessonLifecycleRepository,
      {} as SubscriptionReservationService,
    );

    await expect(
      (
        series as unknown as {
          assertPlanExpansionBounds(
            client: PoolClient,
            rows: SchedulePlanRowDto[],
            validFrom: string,
            validUntil: string | null,
          ): Promise<void>;
        }
      ).assertPlanExpansionBounds(
        client,
        [scheduleRow()],
        "1900-01-01",
        "2100-01-01",
      ),
    ).rejects.toMatchObject({
      response: { code: "SCHEDULE_PLAN_HISTORICAL_RANGE_TOO_LARGE" },
    });
    expect(client.query).toHaveBeenCalledTimes(1);
  });

  it("locks plan subjects and resources in sorted unique order before subscriptions", async () => {
    const advisoryKeys: string[] = [];
    const events: string[] = [];
    let activeReferences: Array<{ type: string; id: string }> = [];
    let subscriptionSql = "";
    const client = {
      query: jest.fn(async (sql: string, values?: unknown[]) => {
        if (sql.includes("pg_advisory_xact_lock")) {
          advisoryKeys.push(String(values?.[0]));
          events.push(`lock:${String(values?.[0])}`);
          return { rows: [] };
        }
        if (sql.includes("jsonb_to_recordset")) {
          events.push("active-client-recheck");
          activeReferences = JSON.parse(String(values?.[0]));
          return { rows: [] };
        }
        if (sql.includes("from app.subscriptions")) {
          events.push("subscriptions");
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
    expect(activeReferences).toEqual([
      { type: "student", id: "student-a" },
      { type: "student", id: "student-b" },
    ]);
    expect(events.indexOf("active-client-recheck")).toBe(advisoryKeys.length);
    expect(events.indexOf("subscriptions")).toBe(advisoryKeys.length + 1);
    expect(subscriptionSql).toMatch(/order by id for update/);
  });

  it("loads rule history and exceptions in bounded batches while keeping only current rows editable", async () => {
    const database = {
      query: jest
        .fn()
        .mockResolvedValueOnce({
          rows: [
            {
              id: "plan-a",
              kind: "individual",
              title: "History plan",
              student_id: "student-a",
              group_id: null,
              subscription_id: "subscription-a",
              active_from: "2025-01-01",
              active_until: null,
              status: "active",
              version: 2,
              ended_at: null,
              ended_by: null,
              ended_by_name: null,
              end_reason: null,
              participants: [],
              scheduled_lesson_count: "4",
              covered_lesson_count: "3",
            },
          ],
        })
        .mockResolvedValueOnce({
          rows: [
            {
              plan_id: "plan-a",
              id: "series-retired",
              teacher_id: "teacher-a",
              teacher_name: "Teacher A",
              room_id: "room-a",
              room_name: "Room A",
              branch_id: "branch-a",
              branch_name: "Branch A",
              weekday: 1,
              begin_time: "10:00",
              duration_minutes: 60,
              valid_from: "2025-01-01",
              valid_until: "2025-12-31",
              business_date: "2026-09-03",
              notes: null,
              planned_financial_decision: {},
              superseded_by: "series-current",
              deleted_at: null,
            },
            {
              plan_id: "plan-a",
              id: "series-current",
              teacher_id: "teacher-a",
              teacher_name: "Teacher A",
              room_id: "room-a",
              room_name: "Room A",
              branch_id: "branch-a",
              branch_name: "Branch A",
              weekday: 1,
              begin_time: "11:00",
              duration_minutes: 60,
              valid_from: "2026-01-01",
              valid_until: null,
              business_date: "2026-09-03",
              notes: null,
              planned_financial_decision: {},
              superseded_by: null,
              deleted_at: null,
            },
            {
              plan_id: "plan-a",
              id: "series-finite-expired",
              teacher_id: "teacher-a",
              teacher_name: "Teacher A",
              room_id: "room-a",
              room_name: "Room A",
              branch_id: "branch-a",
              branch_name: "Branch A",
              weekday: 1,
              begin_time: "12:00",
              duration_minutes: 60,
              valid_from: "2026-08-01",
              valid_until: "2026-09-02",
              business_date: "2026-09-03",
              notes: null,
              planned_financial_decision: {},
              superseded_by: null,
              deleted_at: null,
            },
            {
              plan_id: "plan-a",
              id: "series-deleted-before-start",
              teacher_id: "teacher-a",
              teacher_name: "Teacher A",
              room_id: "room-a",
              room_name: "Room A",
              branch_id: "branch-a",
              branch_name: "Branch A",
              weekday: 1,
              begin_time: "13:00",
              duration_minutes: 60,
              valid_from: "2027-01-01",
              valid_until: null,
              business_date: "2026-09-03",
              notes: null,
              planned_financial_decision: {},
              superseded_by: "series-current",
              deleted_at: "2026-09-01T10:00:00.000Z",
            },
          ],
        })
        .mockResolvedValueOnce({
          rows: [
            {
              plan_id: "plan-a",
              lesson_id: "lesson-exception",
              source_series_id: "series-current",
              series_id: "series-current",
              scheduled_at: "2099-01-05T08:00:00.000Z",
              expected_scheduled_at: "2099-01-05T08:00:00.000Z",
              scheduled_date: "2099-01-05",
              business_date: "2026-09-03",
              source_series_date: "2099-01-05",
              reschedule_depth: 0,
              teacher_id: "teacher-b",
              teacher_name: "Teacher B",
              room_id: "room-a",
              room_name: "Room A",
              branch_id: "branch-a",
              branch_name: "Branch A",
              weekday: 1,
              begin_time: "11:00",
              duration_minutes: 60,
              predecessor_id: null,
            },
            {
              plan_id: "plan-a",
              lesson_id: "successor-b",
              source_series_id: "series-current",
              series_id: null,
              scheduled_at: "2099-01-06T08:00:00.000Z",
              expected_scheduled_at: "2099-01-06T08:00:00.000Z",
              scheduled_date: "2099-01-06",
              business_date: "2026-09-03",
              source_series_date: "2099-01-06",
              reschedule_depth: 1,
              teacher_id: "teacher-a",
              teacher_name: "Teacher A",
              room_id: "room-a",
              room_name: "Room A",
              branch_id: "branch-a",
              branch_name: "Branch A",
              weekday: 2,
              begin_time: "11:00",
              duration_minutes: 60,
              predecessor_id: "source-a",
            },
            {
              plan_id: "plan-a",
              lesson_id: "successor-c",
              source_series_id: "series-current",
              series_id: null,
              scheduled_at: "2099-01-07T08:00:00.000Z",
              expected_scheduled_at: "2099-01-06T08:00:00.000Z",
              scheduled_date: "2099-01-07",
              business_date: "2026-09-03",
              source_series_date: "2099-01-06",
              reschedule_depth: 2,
              teacher_id: "teacher-a",
              teacher_name: "Teacher A",
              room_id: "room-a",
              room_name: "Room A",
              branch_id: "branch-a",
              branch_name: "Branch A",
              weekday: 3,
              begin_time: "11:00",
              duration_minutes: 60,
              predecessor_id: "successor-b",
            },
          ],
        }),
    } as unknown as DatabaseService;
    const service = new SchedulePlanQueryService(
      new SchedulePlanRepository(database),
    );

    const result = await service.list(actor, {
      studentId: "student-a",
      includeEnded: true,
    });

    expect((database.query as jest.Mock)).toHaveBeenCalledTimes(3);
    expect((database.query as jest.Mock).mock.calls[1][1]).toEqual([["plan-a"]]);
    expect((database.query as jest.Mock).mock.calls[2][1]).toEqual([["plan-a"]]);
    expect(result.items[0]).toMatchObject({
      rows: [{ id: "series-current", active: true }],
      ruleTimeline: expect.arrayContaining([
        expect.objectContaining({ id: "series-retired", kind: "recurring_rule" }),
        expect.objectContaining({ id: "series-current", kind: "recurring_rule" }),
        expect.objectContaining({
          id: "series-finite-expired",
          kind: "recurring_rule",
          status: "expired",
        }),
        expect.objectContaining({
          id: "series-deleted-before-start",
          kind: "recurring_rule",
          status: "expired",
        }),
        expect.objectContaining({ id: "lesson-exception", kind: "dated_exception" }),
        expect.objectContaining({ id: "successor-c", kind: "dated_exception" }),
      ]),
      exceptions: expect.arrayContaining([
        expect.objectContaining({
          lessonId: "lesson-exception",
          changedFields: ["teacherId"],
        }),
        expect.objectContaining({ lessonId: "successor-c" }),
      ]),
    });
    expect(result.items[0]!.rows).toHaveLength(1);
    expect(result.items[0]!.exceptions.map((item) => item.lessonId)).not.toContain(
      "successor-b",
    );
  });

  it("preserves update lock and write ordering", async () => {
    const updateEvents: string[] = [];
    const client = {
      query: jest.fn(async (sql: string) => {
        if (sql.includes("pg_advisory_xact_lock")) {
          updateEvents.push("coordination-gate");
        }
        return { rows: [] };
      }),
    } as unknown as PoolClient;
    const platform = {
      executeVersionedMutation: jest.fn(
        async ({
          beforeVersionAdvance,
          mutate,
        }: {
          beforeVersionAdvance?: (client: PoolClient) => Promise<void>;
          mutate: (client: PoolClient, version: number) => Promise<unknown>;
        }) => {
          await beforeVersionAdvance?.(client);
          return {
            version: 2,
            replayed: false,
            resultRef: await mutate(client, 2),
          };
        },
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
          activeSeries: [{
            id: "series-old",
            duration_minutes: 60,
            settlement_revision_id: "settlement-a",
            compensation_revision_id: "compensation-a",
            planned_financial_decision: {
              settlementTypeKey: "lesson",
              teacherCompensationRuleKey: "none",
              clientDecisions: [{ clientId: "student-a" }],
            },
          }],
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
      retireSeries: jest.fn(async () => {
        updateEvents.push("retire-old-series");
        return [];
      }),
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
      allocatePlanReservations: jest.fn(async () => {}),
      materializePlanSeries: jest.fn(async () =>
        updateEvents.push("materialize-new-series"),
      ),
    } as unknown as ScheduleSeriesMaterializerService;
    const settlement = {
      resolvePlannedPlan: jest.fn(async (_client, input) => ({
        decision: {
          ...input.decision,
          teacherCreditedDurationMinutes: 45,
          teacherCompensationSource: "manual",
          clientDecisions: [
            { clientId: "student-a", chargeDurationMinutes: 30 },
          ],
        },
        settlementRevisionId: "settlement-a",
        compensationRevisionId: "compensation-a",
      })),
    } as unknown as LessonSettlementService;
    const policy = {
      assertCanWriteCrm: jest.fn(),
      assertCanSupplyTeacherCompensation: jest.fn(),
      canManageTeacherCompensation: jest.fn(() => true),
      teacherCompensationMutationAuthorization: jest.fn((targetActor) => ({
        actor: targetActor,
        capabilityKey: "config.commerce.manage",
      })),
    } as unknown as CrmPolicy;
    const previews = {
      prepareRows: jest.fn(async (
        targetClient: PoolClient,
        targetActor: ActorContext,
        rows: SchedulePlanRowDto[],
      ) => Promise.all(rows.map(async (row) => {
        const settlementPlan = await settlement.resolvePlannedPlan(
          targetClient,
          {
            branchId: row.branchId,
            durationMinutes: row.durationMinutes ?? 60,
            decision: row.financialDecision,
            actorUserId: targetActor.userId,
            authorization: {
              actor: targetActor,
              capabilityKey: "config.commerce.manage",
            },
            requiredClientIds: ["student-a"],
            reasonText: row.plannedSettlementReason,
            configurationRevisionIds: {
              settlementRevisionId: "settlement-a",
              compensationRevisionId: "compensation-a",
            },
          },
        );
        return {
          row: { ...row, financialDecision: settlementPlan.decision },
          settlementPlan,
        };
      }))),
      assertUpdateHistoricalConfirmation: jest.fn(async () => false),
    } as unknown as SchedulePlanConstraintPreviewService;
    const mutation = new SchedulePlanMutationService(
      platform,
      policy,
      repository,
      series,
      materializer,
      definition,
      previews,
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
          rows: [scheduleRow({
            seriesId: "series-old",
            financialDecision: {
              settlementTypeKey: "lesson",
              teacherCompensationRuleKey: "none",
              clientDecisions: [{ clientId: "student-a" }],
            },
          })],
        },
        metadata,
      );
    } finally {
      lockSpy.mockRestore();
    }

    expect(updateEvents).toEqual([
      "coordination-gate",
      "plan-lock",
      "participant-lock",
      "resource-locks",
      "subscription-lock",
      "active-series-read",
      "series-locks",
      "update-plan",
      "insert-continuations",
      "retire-old-series",
      "replace-participants",
      "validate-new-series",
      "materialize-new-series",
    ]);
    expect(settlement.resolvePlannedPlan).toHaveBeenCalledWith(
      client,
      expect.objectContaining({
      branchId: "branch-a",
      durationMinutes: 60,
      decision: expect.objectContaining({ settlementTypeKey: "lesson" }),
      requiredClientIds: ["student-a"],
      configurationRevisionIds: {
        settlementRevisionId: "settlement-a",
        compensationRevisionId: "compensation-a",
      },
      actorUserId: actor.userId,
      authorization: {
        actor,
        capabilityKey: "config.commerce.manage",
      },
      reasonText: undefined,
      }),
    );
    expect(repository.insertSeries).toHaveBeenCalledWith(
      client,
      expect.objectContaining({
        row: expect.objectContaining({
          financialDecision: expect.objectContaining({
            teacherCreditedDurationMinutes: 45,
            teacherCompensationSource: "manual",
            clientDecisions: [
              { clientId: "student-a", chargeDurationMinutes: 30 },
            ],
          }),
        }),
      }),
    );
  });

  it("acquires the coordination gate before update preview plan rows", async () => {
    const events: string[] = [];
    const sentinel = new Error("stop after prepare");
    const client = {
      query: jest.fn(async (sql: string) => {
        if (sql.includes("pg_advisory_xact_lock")) events.push("gate");
        return { rows: [] };
      }),
    } as unknown as PoolClient;
    const database = {
      transaction: jest.fn((work: (target: PoolClient) => Promise<unknown>) =>
        work(client),
      ),
    } as unknown as DatabaseService;
    const definition = {
      assertRows: jest.fn(),
      prepareUpdate: jest.fn(async () => {
        events.push("prepare-update");
        throw sentinel;
      }),
    } as unknown as SchedulePlanDefinitionService;
    const previews = new SchedulePlanConstraintPreviewService(
      new CrmPolicy(),
      database,
      definition,
      {} as LessonSeriesCommandService,
      {} as LessonSettlementService,
      {} as SubscriptionPreviewTokenService,
    );

    await expect(previews.previewUpdateConstraints(
      { ...actor, role: "director" },
      "plan-a",
      {
      expectedVersion: 1,
      effectiveFrom: "2026-09-01",
      rows: [scheduleRow()],
      },
    )).rejects.toBe(sentinel);
    expect(events).toEqual(["gate", "prepare-update"]);
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
