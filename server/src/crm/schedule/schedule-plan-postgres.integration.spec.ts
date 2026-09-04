import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { ClientReferenceService } from "../clients/client-reference.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { CrmPolicy } from "../crm.policy";
import type { ConfiguredLessonFinancialDecisionDto } from "../dto/lesson-financial-decision.dto";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { SchedulePlanConstraintPreviewService } from "./schedule-plan-constraint-preview.service";
import { SchedulePlanDefinitionService } from "./schedule-plan-definition.service";
import { SchedulePlanEndService } from "./schedule-plan-end.service";
import { SchedulePlanMutationService } from "./schedule-plan-mutation.service";
import { SchedulePlanQueryService } from "./schedule-plan-query.service";
import { SchedulePlanRepository } from "./schedule-plan.repository";
import { SchedulePlanService } from "./schedule-plan.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Schedule plan tests require local PostgreSQL.");
}

jest.setTimeout(90_000);

describe("Schedule plan aggregate (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let plans: SchedulePlanService;
  let materializer: ScheduleSeriesMaterializerService;
  let constraints: ScheduleConstraintEngine;
  let reservations: SubscriptionReservationService;
  let lifecycle: LessonLifecycleRepository;
  let settlement: LessonSettlementService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    const policy = new CrmPolicy();
    const realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    } as unknown as RealtimeBus;
    reservations = new SubscriptionReservationService(database, realtime);
    lifecycle = new LessonLifecycleRepository(database);
    constraints = new ScheduleConstraintEngine(
      new ConstraintEngineRepository(
        database,
        new AvailabilityRepository(database),
      ),
    );
    materializer = new ScheduleSeriesMaterializerService(
      database,
      constraints,
      reservations,
    );
    const availability = new AvailabilityRepository(database);
    const platform = new PlatformIntegrityService(
      database,
      new PlatformIntegrityRepository(),
    );
    const series = new LessonSeriesCommandService(
      platform,
      policy,
      new ClientReferenceService(database),
      new LessonRequiredFieldValidator(),
      constraints,
      lifecycle,
      reservations,
    );
    const repository = new SchedulePlanRepository(database);
    const definition = new SchedulePlanDefinitionService(repository);
    settlement = new LessonSettlementService(database);
    const previewTokens = new SubscriptionPreviewTokenService({
      get: (key: string, fallback: string) =>
        key === "COMMERCE_PREVIEW_SECRET"
          ? "schedule-plan-test-preview-secret-0123456789abcdef"
          : fallback,
    } as unknown as ConfigService);
    const previews = new SchedulePlanConstraintPreviewService(
      policy,
      database,
      definition,
      series,
      settlement,
      previewTokens,
    );
    plans = new SchedulePlanService(
      new SchedulePlanQueryService(repository),
      previews,
      new SchedulePlanMutationService(
        platform,
        policy,
        repository,
        series,
        materializer,
        definition,
        previews,
      ),
      new SchedulePlanEndService(
        platform,
        policy,
        repository,
        database,
        previewTokens,
        lifecycle,
        reservations,
        definition,
      ),
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("materializes canonical completion and hourly teacher snapshot, preserving a lesson's edited personal-account funding", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      await pool.query("insert into app.teacher_rates (teacher_id, rate, effective_from) values ($1, 1200, '2020-01-01')", [fixture.teacherId]);
      const dto = { kind: "individual" as const, title: "Оплата занятия", studentId: fixture.studentIds[0], subscriptionId: fixture.subscriptionIds[0], activeFrom: fixture.today, activeUntil: null, rows: [{ ...row(fixture, 1, "10:00"), durationMinutes: 45 }] };
      const created = await plans.create(actor, dto, { idempotencyKey: `funding-plan-${randomUUID()}`, requestId: randomUUID() });
      const lessonId = created.lessonIds[0]!;
      const snapshots = await pool.query("select completion_type, teacher_compensation_type, teacher_compensation_value::text from app.lesson_snapshots where lesson_id=$1", [lessonId]);
      expect(snapshots.rows[0]).toMatchObject({ completion_type: "standard.success", teacher_compensation_type: "hourly", teacher_compensation_value: "1200.00" });
      await database.transaction(async (client) => {
        const service = new LessonSettlementService(database);
        const current = (await service.loadPlan(client, lessonId))!;
        const decision = { ...current.decision, clientDecisions: [{ clientId: fixture.studentIds[0]!, payerStudentId: fixture.studentIds[0]!, chargeType: "personal_account" as const, basePriceMinor: "60000" }] };
        const prepared = await service.preparePlan(client, fixture.branchId, decision);
        await service.replacePlan(client, { ...prepared, lessonId, expectedVersion: current.version, selectedBy: actor.userId, reasonText: "Личный счёт" });
        await reservations.releaseForLessons(client, [lessonId]);
        await materializer.allocatePlanReservations(client, [lessonId]);
        const reserved = await client.query("select count(*)::int as count from app.lesson_reservations where lesson_id=$1 and state='reserved'", [lessonId]);
        expect(reserved.rows[0].count).toBe(0);
        await client.query("savepoint priced_plan_preview");
        try {
          await client.query("update app.lessons set lifecycle_state='successfully_completed' where id=$1", [lessonId]);
          const settled = await service.settle(client, lessonId, { context: "settle", decision });
          expect(settled.clientFact.amountMinor).toBe("60000");
          expect(settled.teacherFact.amountMinor).toBe("90000");
        } finally { await client.query("rollback to savepoint priced_plan_preview"); }
      });
    } finally {
      await pool.query("delete from app.teacher_rates where teacher_id=$1", [fixture.teacherId]);
      await cleanup(pool, fixture);
    }
  });

  it("freezes fractional plan decisions and reserves the resolved client minutes", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "director" as const };
    try {
      await pool.query("update app.users set role = 'director' where id = $1", [
        fixture.managerId,
      ]);
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Частичная оплата",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [
            {
              ...row(fixture, 1, "10:00"),
              plannedSettlementReason: "Согласовано директором",
              financialDecision: {
                settlementTypeKey: "partially_paid_lesson",
                teacherCompensationRuleKey: "percent",
                teacherCreditedDurationMinutes: 45,
                teacherCompensationSource: "manual" as const,
                clientDecisions: [
                  {
                    clientId: fixture.studentIds[0]!,
                    chargeDurationMinutes: 30,
                  },
                ],
              },
            },
          ],
        },
        {
          idempotencyKey: `plan-partial-${randomUUID()}`,
          requestId: randomUUID(),
        },
      );
      const series = await pool.query<{ planned_financial_decision: Record<string, unknown> }>(
        "select planned_financial_decision from app.schedule_series where id = $1",
        [created.seriesIds[0]],
      );
      expect(series.rows[0]!.planned_financial_decision).toMatchObject({
        settlementTypeKey: "partially_paid_lesson",
        teacherCreditedDurationMinutes: 45,
        teacherCompensationSource: "manual",
        clientDecisions: [
          { clientId: fixture.studentIds[0], chargeDurationMinutes: 30 },
        ],
      });
      const reservations = await pool.query<{ units: string }>(
        `select reservation.units::text as units
         from app.lesson_reservations reservation
         join app.lessons lesson on lesson.id = reservation.lesson_id
         where lesson.series_id = $1 order by reservation.id`,
        [created.seriesIds[0]],
      );
      expect(reservations.rows.length).toBeGreaterThan(0);
      expect(reservations.rows.map((item) => item.units)).toEqual(
        reservations.rows.map(() => "0.50"),
      );
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects missing, duplicate, and unrelated clients before creating new plan rows", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const participants = fixture.studentIds.map((studentId, index) => ({
      studentId,
      subscriptionId: fixture.subscriptionIds[index]!,
    }));
    const groupDto = (clientDecisions: Array<{ clientId: string }>) => ({
      kind: "group" as const,
      title: "Проверка клиентов решения",
      groupId: fixture.groupId,
      activeFrom: fixture.today,
      activeUntil: fixture.until60,
      participants,
      rows: [{
        ...row(fixture, 2, "11:00"),
        financialDecision: {
          settlementTypeKey: "lesson",
          clientDecisions,
        } as ConfiguredLessonFinancialDecisionDto,
      }],
    });
    try {
      await expect(plans.create(actor, {
        kind: "individual",
        title: "Нет решения ученика",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: [row(fixture, 1, "10:00", { omitClientDecisions: true })],
      }, {
        idempotencyKey: `plan-client-missing-${randomUUID()}`,
        requestId: randomUUID(),
      })).rejects.toMatchObject({
        status: 422,
        response: { code: "CLIENT_DECISION_MISSING" },
      });
      await expect(plans.create(actor, groupDto([
        { clientId: fixture.studentIds[0]! },
      ]), {
        idempotencyKey: `plan-group-client-missing-${randomUUID()}`,
        requestId: randomUUID(),
      })).rejects.toMatchObject({
        status: 422,
        response: { code: "CLIENT_DECISION_MISSING" },
      });
      await expect(plans.create(actor, groupDto([
        { clientId: fixture.studentIds[0]! },
        { clientId: fixture.studentIds[0]! },
      ]), {
        idempotencyKey: `plan-group-client-duplicate-${randomUUID()}`,
        requestId: randomUUID(),
      })).rejects.toMatchObject({
        status: 422,
        response: { code: "DUPLICATE_CLIENT_DECISION" },
      });
      await expect(plans.create(actor, groupDto([
        { clientId: fixture.studentIds[0]! },
        { clientId: randomUUID() },
      ]), {
        idempotencyKey: `plan-group-client-unrelated-${randomUUID()}`,
        requestId: randomUUID(),
      })).rejects.toMatchObject({
        status: 422,
        response: { code: "UNKNOWN_LESSON_CLIENT" },
      });
      const inserted = await pool.query<{ count: string }>(
        `select count(*)::text from app.schedule_plans
         where title in ('Нет решения ученика', 'Проверка клиентов решения')`,
      );
      expect(inserted.rows[0]!.count).toBe("0");
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("previews a recurring row through the atomic resolved plan operation", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const resolveSpy = jest.spyOn(settlement, "resolvePlannedPlan");
    try {
      const preview = await plans.previewConstraints(actor, {
        kind: "individual",
        title: "Единый снимок каталога",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: [{
          ...row(fixture, 1, "10:00"),
          financialDecision: {
            settlementTypeKey: "lesson",
            clientDecisions: [{ clientId: fixture.studentIds[0]! }],
          } as ConfiguredLessonFinancialDecisionDto,
        }],
      });

      expect(preview.valid).toBe(true);
      expect(resolveSpy).toHaveBeenCalledTimes(1);
    } finally {
      resolveSpy.mockRestore();
      await cleanup(pool, fixture);
    }
  });

  it("resolves sparse operational recurring rows once and persists that prepared revision", async () => {
    const fixture = await createFixture(pool);
    const originalResolve = settlement.resolvePlannedPlan.bind(settlement);
    const preparedPlans: Awaited<ReturnType<typeof originalResolve>>[] = [];
    const resolveSpy = jest
      .spyOn(settlement, "resolvePlannedPlan")
      .mockImplementation(async (...args) => {
        const prepared = await originalResolve(...args);
        preparedPlans.push(prepared);
        return prepared;
      });
    const scenarios = [
      { role: "manager" as const, settlementTypeKey: "free_lesson", weekday: 1 },
      { role: "admin" as const, settlementTypeKey: "unpaid_miss", weekday: 2 },
    ];
    try {
      for (const scenario of scenarios) {
        const actor = { userId: fixture.managerId, role: scenario.role };
        const financialDecision = {
          settlementTypeKey: scenario.settlementTypeKey,
          clientDecisions: [{
            clientId: fixture.studentIds[0]!,
            settlementTypeKey: scenario.settlementTypeKey,
            chargeType: "none" as const,
          }],
        } as ConfiguredLessonFinancialDecisionDto;
        const dto = {
          kind: "individual" as const,
          title: `Sparse ${scenario.role} ${scenario.settlementTypeKey}`,
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [{
            ...row(fixture, scenario.weekday, "14:00"),
            financialDecision,
          }],
        };

        preparedPlans.length = 0;
        resolveSpy.mockClear();
        const preview = await plans.previewConstraints(actor, dto);
        expect(preview.valid).toBe(true);
        expect(resolveSpy).toHaveBeenCalledTimes(1);
        expect(resolveSpy.mock.calls[0]![1].decision).toEqual(financialDecision);
        expect(preparedPlans[0]!.decision).toMatchObject({
          teacherCompensationRuleKey: "none",
          teacherCreditedDurationMinutes: 0,
          teacherCompensationSource: "automatic",
        });

        preparedPlans.length = 0;
        resolveSpy.mockClear();
        const created = await plans.create(actor, dto, {
          idempotencyKey: `sparse-${scenario.role}-${scenario.settlementTypeKey}-${randomUUID()}`,
          requestId: randomUUID(),
        });
        expect(resolveSpy).toHaveBeenCalledTimes(1);
        const persisted = await pool.query<{
          decision: ConfiguredLessonFinancialDecisionDto;
          settlement_revision_id: string;
          compensation_revision_id: string;
        }>(
          `select planned_financial_decision as decision,
             settlement_revision_id, compensation_revision_id
           from app.schedule_series where id = $1`,
          [created.seriesIds[0]],
        );
        expect(persisted.rows[0]!.decision).toMatchObject({
          teacherCompensationRuleKey: "none",
          teacherCreditedDurationMinutes: 0,
          teacherCompensationSource: "automatic",
        });
        expect(persisted.rows[0]!.settlement_revision_id).toBe(
          preparedPlans[0]!.settlementRevisionId,
        );
        expect(persisted.rows[0]!.compensation_revision_id).toBe(
          preparedPlans[0]!.compensationRevisionId,
        );
      }
    } finally {
      resolveSpy.mockRestore();
      await cleanup(pool, fixture);
    }
  });

  it("rejects an unauthorized recurring teacher override without any write", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const requestId = `schedule-plan-rbac-${randomUUID()}`;
    const title = `Forbidden override ${randomUUID()}`;
    try {
      await expect(plans.create(actor, {
        kind: "individual",
        title,
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: [{
          ...row(fixture, 3, "15:00"),
          financialDecision: {
            settlementTypeKey: "free_lesson",
            teacherCompensationRuleKey: "standard",
            clientDecisions: [{
              clientId: fixture.studentIds[0]!,
              settlementTypeKey: "free_lesson",
              chargeType: "none",
            }],
          },
        }],
      }, {
        idempotencyKey: `forbidden-recurring-${randomUUID()}`,
        requestId,
      })).rejects.toMatchObject({
        status: 403,
        response: { code: "TEACHER_COMPENSATION_PERMISSION_REQUIRED" },
      });
      const writes = await pool.query<{
        plans: string;
        series: string;
        lessons: string;
        audits: string;
        outbox: string;
      }>(
        `select
          (select count(*)::text from app.schedule_plans where title = $1) as plans,
          (select count(*)::text from app.schedule_series series
             join app.schedule_plans plan on plan.id = series.plan_id
             where plan.title = $1) as series,
          (select count(*)::text from app.lessons lesson
             join app.schedule_series series on series.id = lesson.series_id
             join app.schedule_plans plan on plan.id = series.plan_id
             where plan.title = $1) as lessons,
          (select count(*)::text from app.audit_events where request_id = $2) as audits,
          (select count(*)::text from app.platform_outbox_events
             where request_id = $2) as outbox`,
        [title, requestId],
      );
      expect(writes.rows[0]).toEqual({
        plans: "0",
        series: "0",
        lessons: "0",
        audits: "0",
        outbox: "0",
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("creates one open-ended individual plan with N series and idempotent unique lessons", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const key = `plan-individual-${randomUUID()}`;
    let additional:
      Awaited<ReturnType<typeof createAdditionalPlanResource>> | undefined;
    try {
      additional = await createAdditionalPlanResource(pool, fixture.branchId);
      const dto = {
        kind: "individual" as const,
        title: "Индивидуальный вокал",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: null,
        rows: [
          row(fixture, 1, "10:00"),
          row(fixture, 4, "11:00"),
          row(fixture, 6, "12:00", {
            teacherId: additional.teacherId,
            roomId: additional.roomId,
          }),
        ],
      };
      const [created, replay] = await Promise.all([
        plans.create(actor, dto, {
          idempotencyKey: key,
          requestId: `request-${randomUUID()}`,
        }),
        plans.create(actor, dto, {
          idempotencyKey: key,
          requestId: `request-${randomUUID()}`,
        }),
      ]);
      expect(created.id).toBe(replay.id);
      expect([created.replayed, replay.replayed].sort()).toEqual([false, true]);
      expect(created.seriesIds).toHaveLength(3);
      expect(created.lessonIds.length).toBeGreaterThan(0);

      const persisted = await pool.query<{
        plans: string;
        series: string;
        lessons: string;
        snapshots: string;
        reservations: string;
        duplicate_dates: string;
      }>(
        `select
          (select count(*)::text from app.schedule_plans where id = $1) as plans,
          (select count(*)::text from app.schedule_series where plan_id = $1) as series,
          (select count(*)::text from app.lessons lesson join app.schedule_series series
             on series.id = lesson.series_id where series.plan_id = $1 and lesson.deleted_at is null) as lessons,
          (select count(*)::text from app.lesson_snapshots snapshot join app.lessons lesson
             on lesson.id = snapshot.lesson_id join app.schedule_series series
             on series.id = lesson.series_id where series.plan_id = $1) as snapshots,
          (select count(*)::text from app.lesson_reservations reservation join app.lessons lesson
             on lesson.id = reservation.lesson_id join app.schedule_series series
             on series.id = lesson.series_id where series.plan_id = $1 and reservation.state = 'reserved') as reservations,
          (select count(*)::text from (
             select lesson.series_id, lesson.series_date from app.lessons lesson
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = $1 and lesson.deleted_at is null
             group by lesson.series_id, lesson.series_date having count(*) > 1
           ) duplicate) as duplicate_dates`,
        [created.id],
      );
      expect(persisted.rows[0]).toEqual({
        plans: "1",
        series: "3",
        lessons: String(created.lessonIds.length),
        snapshots: String(created.lessonIds.length),
        reservations: String(created.lessonIds.length),
        duplicate_dates: "0",
      });
      const readback = await plans.list(actor, {
        studentId: fixture.studentIds[0],
        includeEnded: true,
      });
      const readbackPlan = readback.items.find(
        (item) => item.id === created.id,
      );
      expect(readbackPlan?.rows).toHaveLength(3);
      expect(readbackPlan?.rows).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            teacherId: fixture.teacherId,
            roomId: fixture.roomId,
            weekday: 1,
          }),
          expect.objectContaining({
            teacherId: fixture.teacherId,
            roomId: fixture.roomId,
            weekday: 4,
          }),
          expect.objectContaining({
            teacherId: additional.teacherId,
            teacherName: "Second Plan Teacher",
            roomId: additional.roomId,
            roomName: additional.roomName,
            weekday: 6,
          }),
        ]),
      );
      const regenerated = await database.transaction(async (client) => {
        let count = 0;
        for (const seriesId of created.seriesIds) {
          count += await materializer.materializePlanSeries(client, seriesId);
        }
        return count;
      });
      expect(regenerated).toBe(0);
    } finally {
      await cleanup(pool, fixture, additional);
    }
  });

  it("creates all 13 September-to-December Fridays and reserves only the first 12", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      await pool.query("update app.subscriptions set lessons_total = 12 where id = $1", [fixture.subscriptionIds[0]]);
      const dto = {
        kind: "individual" as const, title: "Пятницы сентября — декабря",
        studentId: fixture.studentIds[0], subscriptionId: fixture.subscriptionIds[0],
        activeFrom: "2026-09-01", activeUntil: "2026-12-01",
        rows: [row(fixture, 5, "10:00")],
      };
      const preview = await plans.previewConstraints(actor, dto);
      expect(preview.valid).toBe(true);
      const historical = (preview as unknown as { historical: { confirmRequired: boolean; previewToken?: string } }).historical;
      const created = await plans.create(actor, {
        ...dto,
        ...(historical.confirmRequired ? { confirmHistorical: true, previewToken: historical.previewToken } : {}),
      } as never, { idempotencyKey: `full-fridays-${randomUUID()}`, requestId: `request-${randomUUID()}` });
      const lessons = await pool.query<{ day: string; covered: boolean }>(
        `select lesson.series_date::text as day,
          exists(select 1 from app.lesson_reservations reservation where reservation.lesson_id = lesson.id and reservation.state = 'reserved') as covered
         from app.lessons lesson where lesson.id = any($1::uuid[]) order by lesson.scheduled_at`,
        [created.lessonIds],
      );
      expect(lessons.rows.map(item => item.day)).toEqual([
        "2026-09-04", "2026-09-11", "2026-09-18", "2026-09-25",
        "2026-10-02", "2026-10-09", "2026-10-16", "2026-10-23", "2026-10-30",
        "2026-11-06", "2026-11-13", "2026-11-20", "2026-11-27",
      ]);
      expect(lessons.rows.map(item => item.covered)).toEqual([
        true, true, true, true, true, true, true, true, true, true, true, true, false,
      ]);
      const listed = await plans.list(actor, { studentId: fixture.studentIds[0] });
      expect(listed.items.find(item => item.id === created.id)).toMatchObject({
        scheduledLessonCount: 13, coveredLessonCount: 12,
      });
      const tray = await plans.tray(actor, created.id, { limit: 40,
        cursor: Buffer.from(JSON.stringify({ scheduledAt: '2026-09-01T00:00:00Z', id: randomUUID() })).toString('base64url'),
        direction: 'next' });
      expect(tray.items.filter(item => item.settlementMarkers.some(marker => marker.key === 'subscription_reserved'))).toHaveLength(12);
      expect(await database.transaction(client => materializer.materializePlanSeries(client, created.seriesIds[0]!))).toBe(0);
    } finally { await cleanup(pool, fixture); }
  });

  it.each([[182, 26], [365, 53]])("materializes the entire %i-day plan (%i Fridays)", async (days, count) => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const weekday = new Date(`${fixture.today}T00:00:00Z`).getUTCDay();
      const start = addDays(fixture.today, (5 - weekday + 7) % 7 + 7);
      const created = await plans.create(actor, {
        kind: "individual", title: "Длительное расписание",
        studentId: fixture.studentIds[0], subscriptionId: fixture.subscriptionIds[0],
        activeFrom: start, activeUntil: addDays(start, days - 1),
        rows: [row(fixture, 5, "10:00")],
      }, { idempotencyKey: `long-plan-${randomUUID()}`, requestId: `request-${randomUUID()}` });
      expect(created.lessonIds).toHaveLength(count);
    } finally { await cleanup(pool, fixture); }
  });

  it("reserves the earliest lessons across multiple weekdays", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      await pool.query('update app.subscriptions set lessons_total = 3 where id = $1', [fixture.subscriptionIds[0]]);
      const created = await plans.create(actor, {
        kind: 'individual', title: 'Два дня недели', studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0], activeFrom: fixture.today,
        activeUntil: addDays(fixture.today, 27), rows: [row(fixture, 5, '10:00'), row(fixture, 1, '10:00')],
      }, { idempotencyKey: `two-days-${randomUUID()}`, requestId: `request-${randomUUID()}` });
      const covered = await pool.query<{ covered: boolean }>(
        `select exists(select 1 from app.lesson_reservations r where r.lesson_id = l.id and r.state = 'reserved') as covered
         from app.lessons l where l.id = any($1::uuid[]) order by l.scheduled_at`, [created.lessonIds]);
      expect(covered.rows.map(item => item.covered)).toEqual([true, true, true, false, false, false, false, false]);
    } finally { await cleanup(pool, fixture); }
  });

  it("reviews and confirms historical occurrences without directly using subscription units", async () => {
    const fixture = await createFixture(pool);
    let additional:
      Awaited<ReturnType<typeof createAdditionalPlanResource>> | undefined;
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const activeFrom = addDays(fixture.today, -21);
    const activeUntil = addDays(fixture.today, 21);
    const dto = {
      kind: "individual" as const,
      title: "Исторический закрытый период",
      studentId: fixture.studentIds[0],
      subscriptionId: fixture.subscriptionIds[0],
      activeFrom,
      activeUntil,
      rows: [row(fixture, 1, "10:00")],
    };
    try {
      const preview = await plans.previewConstraints(actor, dto);
      const historical = (
        preview as unknown as {
          historical: {
            confirmRequired: boolean;
            count: number;
            from: string;
            until: string;
            previewToken: string;
          };
        }
      ).historical;
      expect(preview.valid).toBe(true);
      expect(historical).toMatchObject({
        confirmRequired: true,
      });
      expect(historical.count).toBeGreaterThan(0);
      expect(historical.from.localeCompare(activeFrom)).toBeGreaterThanOrEqual(
        0,
      );
      expect(historical.until.localeCompare(fixture.today)).toBeLessThan(0);

      await expect(
        plans.create(actor, dto, {
          idempotencyKey: `plan-history-unconfirmed-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        }),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_HISTORY_CONFIRMATION_REQUIRED" },
      });

      additional = await createAdditionalPlanResource(pool, fixture.branchId);
      await expect(
        plans.create(
          actor,
          {
            ...dto,
            rows: [
              row(fixture, 1, "10:00", {
                teacherId: additional.teacherId,
                roomId: additional.roomId,
              }),
            ],
            confirmHistorical: true,
            previewToken: historical.previewToken,
          } as never,
          {
            idempotencyKey: `plan-history-stale-resource-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_HISTORY_PREVIEW_STALE" },
      });

      const metadata = {
        idempotencyKey: `plan-history-confirmed-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      };
      const created = await plans.create(
        actor,
        {
          ...dto,
          confirmHistorical: true,
          previewToken: historical.previewToken,
        } as never,
        metadata,
      );
      const replay = await plans.create(
        actor,
        {
          ...dto,
          confirmHistorical: true,
          previewToken: historical.previewToken,
        } as never,
        metadata,
      );
      expect(replay).toEqual({ ...created, replayed: true });
      const state = await pool.query<{
        historical_lessons: string;
        lessons: string;
        used_units: string;
        reserved_units: string;
        available_units: string;
      }>(
        `select
          (select count(*)::text from app.lessons lesson
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = $1 and lesson.series_date < $3::date
               and lesson.deleted_at is null) as historical_lessons,
          (select count(*)::text from app.lessons lesson
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = $1 and lesson.deleted_at is null) as lessons,
          subscription.lessons_used::text as used_units,
          coalesce((select sum(reservation.units)::text
            from app.lesson_reservations reservation
            join app.lessons lesson on lesson.id = reservation.lesson_id
            join app.schedule_series series on series.id = lesson.series_id
            where series.plan_id = $1 and reservation.state = 'reserved'), '0')
              as reserved_units,
          (subscription.lessons_total - subscription.lessons_used
            - coalesce((select sum(reservation.units)
                from app.lesson_reservations reservation
                where reservation.subscription_id = subscription.id
                  and reservation.state = 'reserved'), 0))::text
              as available_units
         from app.subscriptions subscription where subscription.id = $2`,
        [created.id, fixture.subscriptionIds[0], fixture.today],
      );
      const persisted = state.rows[0]!;
      expect(Number(persisted.historical_lessons)).toBe(historical.count);
      expect(Number(persisted.lessons)).toBeGreaterThan(historical.count);
      expect(Number(persisted.lessons)).toBe(created.lessonIds.length);
      expect(Number(persisted.used_units)).toBe(0);
      expect(Number(persisted.reserved_units)).toBeGreaterThan(0);
      expect(
        Number(persisted.available_units) + Number(persisted.reserved_units),
      ).toBe(500);
    } finally {
      await cleanup(pool, fixture, additional);
    }
  });

  it("splits a confirmed past edit and keeps the earlier lesson snapshot immutable", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const activeFrom = addDays(fixture.today, -28);
    const effectiveFrom = addDays(fixture.today, -10);
    const activeUntil = addDays(fixture.today, 21);
    const sourceRow = row(fixture, 1, "10:00");
    try {
      const createDto = {
        kind: "individual" as const,
        title: "Редактируемый закрытый период",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom,
        activeUntil,
        rows: [sourceRow],
      };
      const createPreview = await plans.previewConstraints(actor, createDto);
      const createToken = (
        createPreview as unknown as {
          historical: { previewToken: string };
        }
      ).historical.previewToken;
      const created = await plans.create(
        actor,
        {
          ...createDto,
          confirmHistorical: true,
          previewToken: createToken,
        } as never,
        {
          idempotencyKey: `plan-history-edit-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const before = await pool.query<{ id: string; snapshot: string }>(
        `select lesson.id, row_to_json(snapshot.*)::text as snapshot
           from app.lessons lesson
           join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
          where lesson.series_id = $1 and lesson.series_date < $2::date
          order by lesson.series_date, lesson.id`,
        [created.seriesIds[0], effectiveFrom],
      );
      expect(before.rows.length).toBeGreaterThan(0);

      const updateDto = {
        expectedVersion: 1,
        effectiveFrom,
        activeUntil,
        rows: [
          {
            ...sourceRow,
            seriesId: created.seriesIds[0],
            beginTime: "12:00",
          },
        ],
      };
      const updatePreview = await plans.previewUpdateConstraints(
        actor,
        created.id,
        updateDto,
      );
      const updateHistory = (
        updatePreview as unknown as {
          historical: { confirmRequired: boolean; previewToken: string };
        }
      ).historical;
      expect(updatePreview.valid).toBe(true);
      expect(updateHistory.confirmRequired).toBe(true);

      await plans.update(
        actor,
        created.id,
        {
          ...updateDto,
          confirmHistorical: true,
          previewToken: updateHistory.previewToken,
        } as never,
        {
          idempotencyKey: `plan-history-edit-confirmed-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );

      const after = await pool.query<{ id: string; snapshot: string }>(
        `select lesson.id, row_to_json(snapshot.*)::text as snapshot
           from app.lessons lesson
           join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
          where lesson.id = any($1::uuid[])
          order by lesson.series_date, lesson.id`,
        [before.rows.map((lesson) => lesson.id)],
      );
      expect(after.rows).toEqual(before.rows);
      const split = await pool.query<{
        old_valid_until: string;
        new_valid_from: string;
        old_active_after_split: string;
        old_deleted_after_split: string;
        new_historical_after_split: string;
      }>(
        `select old.valid_until::text as old_valid_until,
          continuation.valid_from::text as new_valid_from,
          (select count(*)::text from app.lessons lesson
            where lesson.series_id = old.id and lesson.series_date >= $3::date
              and lesson.deleted_at is null) as old_active_after_split,
          (select count(*)::text from app.lessons lesson
            where lesson.series_id = old.id and lesson.series_date >= $3::date
              and lesson.deleted_at is not null) as old_deleted_after_split,
          (select count(*)::text from app.lessons lesson
            where lesson.series_id = continuation.id
              and lesson.series_date >= $3::date
              and lesson.series_date < $4::date
              and lesson.deleted_at is null) as new_historical_after_split
         from app.schedule_series old
         join app.schedule_series continuation on continuation.id = old.superseded_by
         where old.id = $1 and continuation.plan_id = $2`,
        [created.seriesIds[0], created.id, effectiveFrom, fixture.today],
      );
      expect(split.rows[0]).toMatchObject({
        old_valid_until: addDays(effectiveFrom, -1),
        new_valid_from: effectiveFrom,
        old_active_after_split: "0",
      });
      expect(Number(split.rows[0]!.old_deleted_after_split)).toBeGreaterThan(0);
      expect(Number(split.rows[0]!.new_historical_after_split)).toBeGreaterThan(
        0,
      );
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects a past split that would rewrite an already-terminal lesson", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const activeFrom = addDays(fixture.today, -28);
    const effectiveFrom = addDays(fixture.today, -14);
    const sourceRow = row(fixture, 1, "10:00");
    try {
      const createDto = {
        kind: "individual" as const,
        title: "Неизменяемая история",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom,
        activeUntil: addDays(fixture.today, 14),
        rows: [sourceRow],
      };
      const createPreview = await plans.previewConstraints(actor, createDto);
      const previewToken = (
        createPreview as unknown as {
          historical: { previewToken: string };
        }
      ).historical.previewToken;
      const created = await plans.create(
        actor,
        {
          ...createDto,
          confirmHistorical: true,
          previewToken,
        } as never,
        {
          idempotencyKey: `plan-terminal-history-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const terminal = await pool.query<{
        id: string;
        series_id: string;
        snapshot: string;
      }>(
        `select lesson.id, lesson.series_id,
          row_to_json(snapshot.*)::text as snapshot
         from app.lessons lesson
         join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
         where lesson.series_id = $1
           and lesson.series_date >= $2::date
           and lesson.series_date < $3::date
         order by lesson.series_date, lesson.id limit 1`,
        [created.seriesIds[0], effectiveFrom, fixture.today],
      );
      expect(terminal.rows[0]).toBeDefined();
      await pool.query(
        "update app.lessons set lifecycle_state = 'cancelled' where id = $1",
        [terminal.rows[0]!.id],
      );
      await pool.query(
        "update app.lesson_reservations set state = 'released' where lesson_id = $1",
        [terminal.rows[0]!.id],
      );

      await expect(
        plans.previewUpdateConstraints(actor, created.id, {
          expectedVersion: 1,
          effectiveFrom,
          activeUntil: createDto.activeUntil,
          rows: [
            {
              ...sourceRow,
              seriesId: created.seriesIds[0],
              beginTime: "12:00",
            },
          ],
        }),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_TERMINAL_HISTORY_IMMUTABLE" },
      });
      const unchanged = await pool.query<{
        series_id: string;
        snapshot: string;
      }>(
        `select lesson.series_id, row_to_json(snapshot.*)::text as snapshot
         from app.lessons lesson
         join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
         where lesson.id = $1`,
        [terminal.rows[0]!.id],
      );
      expect(unchanged.rows[0]).toEqual({
        series_id: terminal.rows[0]!.series_id,
        snapshot: terminal.rows[0]!.snapshot,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("keeps future cancelled, rescheduled, and deleted occurrences immutable across a split", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const sourceRow = row(fixture, 1, "10:00");
    const effectiveFrom = addDays(fixture.today, 7);
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Неизменяемые будущие исключения",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-future-exceptions-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const targets = await pool.query<{ id: string; series_date: string }>(
        `select id, series_date::text
           from app.lessons
          where series_id = $1 and series_date >= $2::date
          order by series_date, id limit 3`,
        [created.seriesIds[0], effectiveFrom],
      );
      expect(targets.rows).toHaveLength(3);
      const [cancelled, rescheduled, deleted] = targets.rows;
      await pool.query(
        `update app.lessons
            set lifecycle_state = 'cancelled', updated_at = clock_timestamp()
          where id = $1`,
        [cancelled!.id],
      );
      await pool.query(
        `update app.lessons
            set original_scheduled_at = scheduled_at,
                scheduled_at = scheduled_at + interval '5 hours',
                updated_at = clock_timestamp()
          where id = $1`,
        [rescheduled!.id],
      );
      await pool.query(
        `update app.lessons
            set deleted_at = clock_timestamp(), updated_at = clock_timestamp()
          where id = $1`,
        [deleted!.id],
      );
      await pool.query(
        `update app.lesson_reservations
            set state = 'released', updated_at = clock_timestamp()
          where lesson_id = any($1::uuid[]) and state = 'reserved'`,
        [[cancelled!.id, deleted!.id]],
      );
      const before = await pool.query<{
        id: string;
        series_id: string;
        updated_at: string;
        snapshot: string;
      }>(
        `select id, series_id, updated_at::text,
                row_to_json(lesson.*)::text as snapshot
           from app.lessons lesson
          where id = any($1::uuid[])
          order by id`,
        [targets.rows.map((lesson) => lesson.id)],
      );

      const updateDto = {
        expectedVersion: 1,
        effectiveFrom,
        activeUntil: fixture.until60,
        rows: [
          {
            ...sourceRow,
            seriesId: created.seriesIds[0],
            beginTime: "12:00",
          },
        ],
      };
      const preview = await plans.previewUpdateConstraints(
        actor,
        created.id,
        updateDto,
      );
      expect(preview.valid).toBe(true);
      const updated = await plans.update(actor, created.id, updateDto, {
        idempotencyKey: `plan-future-exceptions-update-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      });
      await database.transaction((client) =>
        materializer.materializePlanSeries(client, updated.seriesIds[0]!),
      );

      const after = await pool.query<{
        id: string;
        series_id: string;
        updated_at: string;
        snapshot: string;
      }>(
        `select id, series_id, updated_at::text,
                row_to_json(lesson.*)::text as snapshot
           from app.lessons lesson
          where id = any($1::uuid[])
          order by id`,
        [targets.rows.map((lesson) => lesson.id)],
      );
      expect(after.rows).toEqual(before.rows);
      const occurrences = await pool.query<{
        series_date: string;
        occurrence_count: string;
        replacement_count: string;
      }>(
        `select lesson.series_date::text,
                count(*)::text as occurrence_count,
                count(*) filter (where lesson.series_id = $2)::text
                  as replacement_count
           from app.lessons lesson
           join app.schedule_series series on series.id = lesson.series_id
          where series.plan_id = $3
            and lesson.series_date = any($1::date[])
          group by lesson.series_date
          order by lesson.series_date`,
        [
          targets.rows.map((lesson) => lesson.series_date),
          updated.seriesIds[0],
          created.id,
        ],
      );
      expect(occurrences.rows).toEqual(
        targets.rows
          .map((lesson) => lesson.series_date)
          .sort()
          .map((seriesDate) => ({
            series_date: seriesDate,
            occurrence_count: "1",
            replacement_count: "0",
          })),
      );
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("extends an individual plan backwards with prefix-only series and preserves every old artifact", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const sourceRow = row(fixture, 2, "10:00");
    const newStart = addDays(fixture.today, -21);
    const prefixUntil = addDays(fixture.today, -1);
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Расширяемый назад план",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-backdate-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const exceptions = await pool.query<{ id: string }>(
        `select id from app.lessons where series_id = $1
         order by series_date, id limit 3`,
        [created.seriesIds[0]],
      );
      expect(exceptions.rows).toHaveLength(3);
      await pool.query(
        `update app.lessons set lifecycle_state = 'cancelled' where id = $1`,
        [exceptions.rows[0]!.id],
      );
      await pool.query(
        `update app.lessons set original_scheduled_at = scheduled_at,
           scheduled_at = scheduled_at + interval '5 hours' where id = $1`,
        [exceptions.rows[1]!.id],
      );
      await pool.query(
        `update app.lessons set deleted_at = clock_timestamp() where id = $1`,
        [exceptions.rows[2]!.id],
      );
      await pool.query(
        `update app.lesson_reservations set state = 'released'
         where lesson_id = any($1::uuid[]) and state = 'reserved'`,
        [[exceptions.rows[0]!.id, exceptions.rows[2]!.id]],
      );
      const beforeArtifacts = await planSeriesArtifacts(
        pool,
        created.seriesIds,
      );
      const updateDto = {
        expectedVersion: 1,
        effectiveFrom: newStart,
        title: "Расширяемый назад план",
        subscriptionId: fixture.subscriptionIds[0],
        activeUntil: fixture.until60,
        rows: [{ ...sourceRow, seriesId: created.seriesIds[0] }],
      };
      await expect(
        plans.previewUpdateConstraints(actor, created.id, {
          ...updateDto,
          rows: [{ ...updateDto.rows[0], beginTime: "11:00" }],
        }),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_BACKDATE_SHAPE_CHANGE" },
      });
      const preview = await plans.previewUpdateConstraints(
        actor,
        created.id,
        updateDto,
      );
      expect(preview.valid).toBe(true);
      expect(preview.historical).toMatchObject({
        confirmRequired: true,
        from: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
        until: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
      });
      expect(
        preview.historical.from!.localeCompare(newStart),
      ).toBeGreaterThanOrEqual(0);
      expect(
        preview.historical.until!.localeCompare(prefixUntil),
      ).toBeLessThanOrEqual(0);

      const stateBeforeRejectedWrites = await planPersistenceShape(
        pool,
        created.id,
      );
      await expect(
        plans.update(
          actor,
          created.id,
          {
            ...updateDto,
            title: "Токен не относится к этому заголовку",
            confirmHistorical: true,
            previewToken: preview.historical.previewToken,
          } as never,
          {
            idempotencyKey: `plan-backdate-stale-token-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_HISTORY_PREVIEW_STALE" },
      });
      await expect(
        plans.update(
          actor,
          created.id,
          {
            ...updateDto,
            expectedVersion: 2,
            confirmHistorical: true,
            previewToken: preview.historical.previewToken,
          } as never,
          {
            idempotencyKey: `plan-backdate-stale-version-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toBeDefined();
      expect(await planPersistenceShape(pool, created.id)).toEqual(
        stateBeforeRejectedWrites,
      );

      const metadata = {
        idempotencyKey: `plan-backdate-confirmed-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      };
      const command = {
        ...updateDto,
        confirmHistorical: true,
        previewToken: preview.historical.previewToken,
      } as never;
      const updated = await plans.update(actor, created.id, command, metadata);
      const replay = await plans.update(actor, created.id, command, metadata);
      expect(replay).toEqual({ ...updated, replayed: true });
      expect(updated.lessonIds).toHaveLength(preview.historical.count);
      expect(await planSeriesArtifacts(pool, created.seriesIds)).toEqual(
        beforeArtifacts,
      );
      const prefix = await pool.query<{
        active_from: string;
        version: string;
        valid_from: string;
        valid_until: string;
        superseded_by: string;
        subscription_id: string;
        prefix_series: string;
        prefix_lessons: string;
      }>(
        `select plan.active_from::text, plan.version::text,
          series.valid_from::text, series.valid_until::text,
          series.superseded_by, series.subscription_id,
          (select count(*)::text from app.schedule_series candidate
            where candidate.plan_id = plan.id and candidate.valid_from = $2::date)
            as prefix_series,
          (select count(*)::text from app.lessons lesson
            where lesson.series_id = series.id) as prefix_lessons
         from app.schedule_plans plan
         join app.schedule_series series on series.id = $3
         where plan.id = $1`,
        [created.id, newStart, updated.seriesIds[0]],
      );
      expect(prefix.rows[0]).toEqual({
        active_from: newStart,
        version: "2",
        valid_from: newStart,
        valid_until: prefixUntil,
        superseded_by: created.seriesIds[0],
        subscription_id: fixture.subscriptionIds[0],
        prefix_series: "1",
        prefix_lessons: String(preview.historical.count),
      });
      const stateAfterBackdate = await planPersistenceShape(pool, created.id);
      await expect(
        plans.previewUpdateConstraints(actor, created.id, {
          ...updateDto,
          expectedVersion: 2,
          effectiveFrom: addDays(newStart, 7),
        }),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_PREFIX_EDIT_UNSUPPORTED" },
      });
      expect(await planPersistenceShape(pool, created.id)).toEqual(
        stateAfterBackdate,
      );
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("keeps the Plan series subscription snapshot rolling-compatible and immutable once set", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const legacySeriesId = randomUUID();
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Совместимый снимок абонемента",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [row(fixture, 4, "10:00")],
        },
        {
          idempotencyKey: `plan-subscription-snapshot-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      await expect(
        pool.query(
          `insert into app.schedule_series (
             id, plan_id, student_id, group_id, teacher_id, room_id, branch_id,
             weekday, begin_time, duration_minutes, valid_from, valid_until,
             notes, created_by, version, planned_financial_decision,
             settlement_revision_id, compensation_revision_id, superseded_by
           )
           select $2, plan_id, student_id, group_id, teacher_id, room_id,
             branch_id, weekday, begin_time, duration_minutes,
             (valid_from - interval '14 days')::date,
             (valid_from - interval '8 days')::date, notes, created_by, version,
             planned_financial_decision, settlement_revision_id,
             compensation_revision_id, id
           from app.schedule_series where id = $1`,
          [created.seriesIds[0], legacySeriesId],
        ),
      ).resolves.toBeDefined();
      const legacy = await pool.query<{ subscription_id: string | null }>(
        "select subscription_id from app.schedule_series where id = $1",
        [legacySeriesId],
      );
      expect(legacy.rows[0]!.subscription_id).toBeNull();
      await expect(
        pool.query(
          "update app.schedule_series set subscription_id = $2 where id = $1",
          [legacySeriesId, fixture.subscriptionIds[1]],
        ),
      ).rejects.toMatchObject({ code: "23514" });
      await expect(
        pool.query(
          "update app.schedule_series set subscription_id = $2 where id = $1",
          [legacySeriesId, fixture.subscriptionIds[0]],
        ),
      ).resolves.toBeDefined();
      await expect(
        pool.query(
          "update app.schedule_series set subscription_id = null where id = $1",
          [legacySeriesId],
        ),
      ).rejects.toMatchObject({ code: "23514" });
      const immutable = await pool.query<{ subscription_id: string }>(
        "select subscription_id from app.schedule_series where id = $1",
        [legacySeriesId],
      );
      expect(immutable.rows[0]!.subscription_id).toBe(
        fixture.subscriptionIds[0],
      );
      expect(await new MigrationRunner(pool).down()).toBe(
        "0147_lesson_reservation_history",
      );
      expect(await new MigrationRunner(pool).down()).toBe(
        "0146_lesson_funding_payer",
      );
      expect(await new MigrationRunner(pool).down()).toBe(
        "0145_student_contact_email",
      );
      expect(await new MigrationRunner(pool).down()).toBe(
        "0144_direct_subscription_payment_isolation",
      );
      expect(await new MigrationRunner(pool).down()).toBe(
        "0143_payment_record_link_permission",
      );
      try {
        await expect(new MigrationRunner(pool).down()).rejects.toThrow(
          /0142 rollback is unsafe/,
        );
        const migrationStillApplied = await pool.query<{ applied: boolean }>(
          `select exists (select 1 from app_schema_migrations
            where id = '0142_schedule_plan_series_subscription_snapshot') as applied`,
        );
        expect(migrationStillApplied.rows[0]!.applied).toBe(true);
      } finally {
        expect(await new MigrationRunner(pool).up()).toEqual([
          "0143_payment_record_link_permission",
          "0144_direct_subscription_payment_isolation",
          "0145_student_contact_email",
          "0146_lesson_funding_payer",
          "0147_lesson_reservation_history",
        ]);
      }
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("changes an individual subscription before inserting its immutable continuation snapshot", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const sourceRow = row(fixture, 5, "10:00");
    try {
      const alternative = await pool.query<{ id: string }>(
        `insert into app.subscriptions (
           student_id, lessons_total, lessons_used, status
         ) values ($1, 500, 0, 'active') returning id`,
        [fixture.studentIds[0]],
      );
      const alternativeId = alternative.rows[0]!.id;
      fixture.subscriptionIds.push(alternativeId);
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Смена абонемента",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-subscription-change-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const legacyClient = await pool.connect();
      try {
        await legacyClient.query("begin");
        await legacyClient.query(
          "set local session_replication_role = replica",
        );
        await legacyClient.query(
          "update app.schedule_series set subscription_id = null where id = $1",
          [created.seriesIds[0]],
        );
        await legacyClient.query("commit");
      } catch (error) {
        await legacyClient.query("rollback");
        throw error;
      } finally {
        legacyClient.release();
      }
      const updated = await plans.update(
        actor,
        created.id,
        {
          expectedVersion: 1,
          effectiveFrom: fixture.effectiveFrom,
          subscriptionId: alternativeId,
          activeUntil: fixture.until60,
          rows: [{ ...sourceRow, seriesId: created.seriesIds[0] }],
        },
        {
          idempotencyKey: `plan-subscription-change-update-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const snapshots = await pool.query<{
        active_from: string;
        plan_subscription_id: string;
        old_subscription_id: string;
        new_subscription_id: string;
        new_lesson_subscriptions: string;
      }>(
        `select plan.active_from::text, plan.subscription_id as plan_subscription_id,
          old_series.subscription_id as old_subscription_id,
          new_series.subscription_id as new_subscription_id,
          (select count(distinct snapshot.subscription_id)::text
             from app.lesson_snapshots snapshot join app.lessons lesson
               on lesson.id = snapshot.lesson_id
            where lesson.series_id = new_series.id
              and snapshot.subscription_id = new_series.subscription_id)
            as new_lesson_subscriptions
         from app.schedule_plans plan
         join app.schedule_series old_series on old_series.id = $2
         join app.schedule_series new_series on new_series.id = $3
         where plan.id = $1`,
        [created.id, created.seriesIds[0], updated.seriesIds[0]],
      );
      expect(snapshots.rows[0]).toEqual({
        active_from: fixture.today,
        plan_subscription_id: alternativeId,
        old_subscription_id: fixture.subscriptionIds[0],
        new_subscription_id: alternativeId,
        new_lesson_subscriptions: "1",
      });
      await expect(
        database.transaction((client) =>
          materializer.materializePlanSeries(client, updated.seriesIds[0]!),
        ),
      ).resolves.toBe(0);
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("moves the plan start only for a date-only update and preserves it for a later row change", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const sourceRow = row(fixture, 6, "10:00");
    const rowChangeDate = addDays(fixture.today, 14);
    const movedStart = addDays(fixture.today, 35);
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Дата начала без скрытой смены истории",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-forward-start-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const oldPeriod = await pool.query<{ id: string }>(
        `select id from app.lessons where series_id = $1
          and series_date < $2::date and deleted_at is null order by id`,
        [created.seriesIds[0], rowChangeDate],
      );
      expect(oldPeriod.rows.length).toBeGreaterThan(0);
      const changedRow = { ...sourceRow, beginTime: "12:00" };
      const changed = await plans.update(
        actor,
        created.id,
        {
          expectedVersion: 1,
          effectiveFrom: rowChangeDate,
          title: "Дата начала без скрытой смены истории",
          subscriptionId: fixture.subscriptionIds[0],
          activeUntil: fixture.until60,
          rows: [{ ...changedRow, seriesId: created.seriesIds[0] }],
        },
        {
          idempotencyKey: `plan-forward-start-row-change-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const afterRowChange = await pool.query<{
        active_from: string;
        preserved: string;
      }>(
        `select plan.active_from::text,
          (select count(*)::text from app.lessons lesson
            where lesson.id = any($2::uuid[]) and lesson.deleted_at is null)
            as preserved
         from app.schedule_plans plan where plan.id = $1`,
        [created.id, oldPeriod.rows.map((lesson) => lesson.id)],
      );
      expect(afterRowChange.rows[0]).toEqual({
        active_from: fixture.today,
        preserved: String(oldPeriod.rows.length),
      });
      expect(changed).toMatchObject({ version: 2 });

      const simpleRow = row(fixture, 1, "16:00");
      const simpleActiveFrom = addDays(fixture.today, -21);
      const simpleCreateDto = {
        kind: "individual" as const,
        title: "Только перенос даты начала",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: simpleActiveFrom,
        activeUntil: fixture.until60,
        rows: [simpleRow],
      };
      const simpleCreatePreview = await plans.previewConstraints(
        actor,
        simpleCreateDto,
      );
      const movable = await plans.create(
        actor,
        {
          ...simpleCreateDto,
          confirmHistorical: true,
          previewToken: simpleCreatePreview.historical.previewToken,
        } as never,
        {
          idempotencyKey: `plan-forward-start-simple-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const futureBeforeMove = await pool.query<{ id: string }>(
        `select id from app.lessons where series_id = $1
          and series_date >= $2::date and deleted_at is null order by id`,
        [movable.seriesIds[0], movedStart],
      );
      expect(futureBeforeMove.rows.length).toBeGreaterThan(0);
      const moveDto = {
        expectedVersion: 1,
        effectiveFrom: movedStart,
        title: "Только перенос даты начала",
        subscriptionId: fixture.subscriptionIds[0],
        activeUntil: fixture.until60,
        rows: [{ ...simpleRow, seriesId: movable.seriesIds[0] }],
      };
      const movePreview = await plans.previewUpdateConstraints(
        actor,
        movable.id,
        moveDto,
      );
      const prefixProjection = await pool.query<{
        total: string;
        historical: string;
        historical_from: string | null;
        historical_until: string | null;
      }>(
        `select count(*)::text as total,
          count(*) filter (where series_date < $4::date)::text as historical,
          min(series_date) filter (where series_date < $4::date)::text
            as historical_from,
          max(series_date) filter (where series_date < $4::date)::text
            as historical_until
         from app.lessons where series_id = $1
           and series_date >= $2::date and series_date < $3::date
           and deleted_at is null`,
        [movable.seriesIds[0], simpleActiveFrom, movedStart, fixture.today],
      );
      expect(movePreview.rows[0]!.occurrencesChecked).toBe(
        Number(prefixProjection.rows[0]!.total),
      );
      expect(movePreview.historical).toMatchObject({
        confirmRequired: true,
        count: Number(prefixProjection.rows[0]!.historical),
        from: prefixProjection.rows[0]!.historical_from,
        until: prefixProjection.rows[0]!.historical_until,
      });
      const beforeStale = {
        shape: await planPersistenceShape(pool, movable.id),
        artifacts: await planSeriesArtifacts(pool, movable.seriesIds),
      };
      await expect(
        plans.update(
          actor,
          movable.id,
          {
            ...moveDto,
            effectiveFrom: addDays(movedStart, -7),
            confirmHistorical: true,
            previewToken: movePreview.historical.previewToken,
          } as never,
          {
            idempotencyKey: `plan-forward-start-stale-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_HISTORY_PREVIEW_STALE" },
      });
      expect({
        shape: await planPersistenceShape(pool, movable.id),
        artifacts: await planSeriesArtifacts(pool, movable.seriesIds),
      }).toEqual(beforeStale);

      const completedId = futureBeforeMove.rows[0]!.id;
      await pool.query(
        `update app.lessons set lifecycle_state = 'successfully_completed'
         where id = $1`,
        [completedId],
      );
      const completedBeforeMove = await lessonArtifact(pool, completedId);
      const moved = await plans.update(
        actor,
        movable.id,
        {
          ...moveDto,
          confirmHistorical: true,
          previewToken: movePreview.historical.previewToken,
        } as never,
        {
          idempotencyKey: `plan-forward-start-date-only-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const afterMove = await pool.query<{
        active_from: string;
        active_before_start: string;
        released_before_start: string;
        continuation_from: string;
      }>(
        `select plan.active_from::text,
          (select count(*)::text from app.lessons lesson
            join app.schedule_series series on series.id = lesson.series_id
            where series.plan_id = plan.id and lesson.series_date < $2::date
              and lesson.deleted_at is null) as active_before_start,
          (select count(*)::text from app.lesson_reservations reservation
            join app.lessons lesson on lesson.id = reservation.lesson_id
            join app.schedule_series series on series.id = lesson.series_id
            where series.plan_id = plan.id and lesson.series_date < $2::date
              and reservation.state = 'released') as released_before_start,
          (select valid_from::text from app.schedule_series where id = $3)
            as continuation_from
         from app.schedule_plans plan where plan.id = $1`,
        [movable.id, movedStart, moved.seriesIds[0]],
      );
      expect(afterMove.rows[0]).toMatchObject({
        active_from: movedStart,
        active_before_start: "0",
        continuation_from: movedStart,
      });
      expect(Number(afterMove.rows[0]!.released_before_start)).toBeGreaterThan(
        0,
      );
      expect(moved.seriesIds).toEqual(movable.seriesIds);
      const futureAfterMove = await pool.query<{ id: string }>(
        `select id from app.lessons where series_id = $1
          and series_date >= $2::date and deleted_at is null order by id`,
        [movable.seriesIds[0], movedStart],
      );
      expect(futureAfterMove.rows).toEqual(futureBeforeMove.rows);
      expect(await lessonArtifact(pool, completedId)).toEqual(
        completedBeforeMove,
      );

      const groupParticipants = fixture.studentIds.map((studentId, index) => ({
        studentId,
        subscriptionId: fixture.subscriptionIds[index]!,
      }));
      const groupRow = row(fixture, 3, "18:00", {
        clientIds: fixture.studentIds,
      });
      const movableGroup = await plans.create(
        actor,
        {
          kind: "group",
          title: "Перенос начала группы",
          groupId: fixture.groupId,
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          participants: groupParticipants,
          rows: [groupRow],
        },
        {
          idempotencyKey: `plan-forward-start-group-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const groupMovedStart = addDays(fixture.today, 21);
      const movedGroup = await plans.update(
        actor,
        movableGroup.id,
        {
          expectedVersion: 1,
          effectiveFrom: groupMovedStart,
          title: "Перенос начала группы",
          activeUntil: fixture.until60,
          participants: groupParticipants,
          rows: [{ ...groupRow, seriesId: movableGroup.seriesIds[0] }],
        },
        {
          idempotencyKey: `plan-forward-start-group-update-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const groupStart = await pool.query<{
        active_from: string;
        series_from: string;
        participant_count: string;
        shifted_count: string;
        overlaps: boolean;
      }>(
        `select plan.active_from::text,
          (select valid_from::text from app.schedule_series where id = $3)
            as series_from,
          (select count(*)::text from app.schedule_plan_participants participant
            where participant.plan_id = plan.id) as participant_count,
          (select count(*)::text from app.schedule_plan_participants participant
            where participant.plan_id = plan.id
              and participant.effective_from = $2::date
              and participant.effective_until = plan.active_until)
            as shifted_count,
          exists (
            select 1 from app.schedule_plan_participants left_assignment
            join app.schedule_plan_participants right_assignment
              on right_assignment.plan_id = left_assignment.plan_id
             and right_assignment.student_id = left_assignment.student_id
             and right_assignment.id > left_assignment.id
             and daterange(left_assignment.effective_from,
                   coalesce(left_assignment.effective_until, 'infinity'::date), '[]')
               && daterange(right_assignment.effective_from,
                   coalesce(right_assignment.effective_until, 'infinity'::date), '[]')
            where left_assignment.plan_id = plan.id
          ) as overlaps
         from app.schedule_plans plan where plan.id = $1`,
        [movableGroup.id, groupMovedStart, movedGroup.seriesIds[0]],
      );
      expect(groupStart.rows[0]).toEqual({
        active_from: groupMovedStart,
        series_from: groupMovedStart,
        participant_count: String(groupParticipants.length),
        shifted_count: String(groupParticipants.length),
        overlaps: false,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects a forward start move when completion terminalizes a locked prefix lesson", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const activeFrom = addDays(fixture.today, 7);
    const movedStart = addDays(fixture.today, 28);
    const sourceRow = row(fixture, isoWeekday(activeFrom), "10:00");
    const title = "Completion wins the start-move race";
    const completionClient = await pool.connect();
    let completionTransactionOpen = false;
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title,
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom,
          activeUntil: fixture.until60,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-forward-completion-first-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const prefix = await pool.query<{ id: string; active_count: string }>(
        `select lesson.id,
          (select count(*)::text from app.lessons candidate
            where candidate.series_id = lesson.series_id
              and candidate.series_date >= $2::date
              and candidate.series_date < $3::date
              and candidate.deleted_at is null) as active_count
         from app.lessons lesson
         where lesson.series_id = $1 and lesson.series_date >= $2::date
           and lesson.series_date < $3::date and lesson.deleted_at is null
         order by lesson.series_date, lesson.id limit 1`,
        [created.seriesIds[0], activeFrom, movedStart],
      );
      const lessonId = prefix.rows[0]!.id;
      const activePrefixCount = prefix.rows[0]!.active_count;

      await completionClient.query("begin");
      completionTransactionOpen = true;
      const blockerPid = await backendPid(completionClient);
      await completionClient.query(
        `update app.lessons set lifecycle_state = 'successfully_completed'
         where id = $1 and lifecycle_state = 'scheduled' and deleted_at is null`,
        [lessonId],
      );

      const moveOutcome = plans
        .update(
          actor,
          created.id,
          {
            expectedVersion: 1,
            effectiveFrom: movedStart,
            title,
            subscriptionId: fixture.subscriptionIds[0],
            activeUntil: fixture.until60,
            rows: [{ ...sourceRow, seriesId: created.seriesIds[0] }],
          },
          {
            idempotencyKey: `plan-forward-completion-first-update-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        )
        .then(
          (value) => ({ ok: true as const, value }),
          (error: unknown) => ({ ok: false as const, error }),
        );
      await waitForBlockedBy(pool, blockerPid);
      await completionClient.query("commit");
      completionTransactionOpen = false;

      const outcome = await moveOutcome;
      expect(outcome).toMatchObject({
        ok: false,
        error: {
          response: { code: "SCHEDULE_PLAN_START_HISTORY_IMMUTABLE" },
        },
      });
      const state = await pool.query<{
        active_from: string;
        plan_version: string;
        series_from: string;
        series_version: string;
        lifecycle_state: string;
        deleted_at: string | null;
        active_prefix_count: string;
      }>(
        `select plan.active_from::text, plan.version::text as plan_version,
          series.valid_from::text as series_from,
          series.version::text as series_version,
          lesson.lifecycle_state, lesson.deleted_at::text,
          (select count(*)::text from app.lessons candidate
            where candidate.series_id = series.id
              and candidate.series_date >= $4::date
              and candidate.series_date < $5::date
              and candidate.deleted_at is null) as active_prefix_count
         from app.schedule_plans plan
         join app.schedule_series series on series.id = $2
         join app.lessons lesson on lesson.id = $3
         where plan.id = $1`,
        [created.id, created.seriesIds[0], lessonId, activeFrom, movedStart],
      );
      expect(state.rows[0]).toEqual({
        active_from: activeFrom,
        plan_version: "1",
        series_from: activeFrom,
        series_version: "1",
        lifecycle_state: "successfully_completed",
        deleted_at: null,
        active_prefix_count: activePrefixCount,
      });
    } finally {
      if (completionTransactionOpen) {
        await completionClient.query("rollback");
      }
      completionClient.release();
      await cleanup(pool, fixture);
    }
  });

  it("makes completion observe a deleted prefix lesson when the start move locks first", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const activeFrom = addDays(fixture.today, 7);
    const movedStart = addDays(fixture.today, 28);
    const sourceRow = row(fixture, isoWeekday(activeFrom), "12:00");
    const title = "Start move wins the completion race";
    const moveClient = await pool.connect();
    const completionClient = await pool.connect();
    let moveTransactionOpen = false;
    let completionTransactionOpen = false;
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title,
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom,
          activeUntil: fixture.until60,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-forward-move-first-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const target = await pool.query<{ id: string }>(
        `select id from app.lessons where series_id = $1
          and series_date >= $2::date and series_date < $3::date
          and lifecycle_state = 'scheduled' and deleted_at is null
         order by series_date, id limit 1`,
        [created.seriesIds[0], activeFrom, movedStart],
      );
      const lessonId = target.rows[0]!.id;
      const repository = new SchedulePlanRepository(database);

      await moveClient.query("begin");
      moveTransactionOpen = true;
      const movePid = await backendPid(moveClient);
      await expect(
        repository.hasImmutableLessonsInRange(
          moveClient,
          created.id,
          activeFrom,
          movedStart,
        ),
      ).resolves.toBe(false);

      await completionClient.query("begin");
      completionTransactionOpen = true;
      const completionPid = await backendPid(completionClient);
      const completionSource = completionClient.query<{ id: string }>(
        `select id from app.lessons
         where id = $1 and lifecycle_state = 'scheduled' and deleted_at is null
         for update`,
        [lessonId],
      );
      await waitForSpecificBlock(pool, completionPid, movePid);

      const removed = await repository.deleteScheduledLessonsInRange(
        moveClient,
        created.id,
        activeFrom,
        movedStart,
      );
      expect(removed).toContain(lessonId);
      await repository.moveSeriesStart(
        moveClient,
        created.seriesIds,
        movedStart,
        2,
      );
      await repository.updatePlan(moveClient, {
        planId: created.id,
        title,
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: movedStart,
        activeUntil: fixture.until60,
        version: 2,
      });
      await moveClient.query("commit");
      moveTransactionOpen = false;

      await expect(completionSource).resolves.toMatchObject({ rows: [] });
      await completionClient.query("commit");
      completionTransactionOpen = false;
      const state = await pool.query<{
        active_from: string;
        series_from: string;
        deleted: boolean;
        reservation_state: string;
      }>(
        `select plan.active_from::text,
          series.valid_from::text as series_from,
          lesson.deleted_at is not null as deleted,
          reservation.state as reservation_state
         from app.schedule_plans plan
         join app.schedule_series series on series.id = $2
         join app.lessons lesson on lesson.id = $3
         join app.lesson_reservations reservation on reservation.lesson_id = lesson.id
         where plan.id = $1`,
        [created.id, created.seriesIds[0], lessonId],
      );
      expect(state.rows[0]).toEqual({
        active_from: movedStart,
        series_from: movedStart,
        deleted: true,
        reservation_state: "released",
      });
    } finally {
      if (completionTransactionOpen) {
        await completionClient.query("rollback");
      }
      if (moveTransactionOpen) {
        await moveClient.query("rollback");
      }
      completionClient.release();
      moveClient.release();
      await cleanup(pool, fixture);
    }
  });

  it("rolls a group prefix back on reservation failure and inserts non-overlapping old-start assignments", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const sourceRow = row(fixture, 3, "14:00", {
      clientIds: fixture.studentIds,
    });
    const newStart = addDays(fixture.today, -14);
    const prefixUntil = addDays(fixture.today, -1);
    const participants = fixture.studentIds.map((studentId, index) => ({
      studentId,
      subscriptionId: fixture.subscriptionIds[index]!,
    }));
    try {
      const created = await plans.create(
        actor,
        {
          kind: "group",
          title: "Группа с историческим префиксом",
          groupId: fixture.groupId,
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          participants,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-group-backdate-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      await expect(
        pool.query(
          "update app.schedule_series set subscription_id = $2 where id = $1",
          [created.seriesIds[0], fixture.subscriptionIds[0]],
        ),
      ).rejects.toMatchObject({ code: "23514" });
      const updateDto = {
        expectedVersion: 1,
        effectiveFrom: newStart,
        activeUntil: fixture.until60,
        participants,
        rows: [{ ...sourceRow, seriesId: created.seriesIds[0] }],
      };
      const preview = await plans.previewUpdateConstraints(
        actor,
        created.id,
        updateDto,
      );
      expect(preview.valid).toBe(true);
      await pool.query(
        `update app.subscriptions subscription
         set lessons_total = ceil(coalesce((
           select sum(reservation.units) from app.lesson_reservations reservation
           where reservation.subscription_id = subscription.id
             and reservation.state = 'reserved'
         ), 0))
         where subscription.id = $1`,
        [fixture.subscriptionIds[0]],
      );
      const beforeFailure = await planPersistenceShape(pool, created.id);
      const allocationFailure = jest.spyOn(reservations, 'allocate').mockRejectedValueOnce(new Error('injected reservation failure'));
      await expect(
        plans.update(
          actor,
          created.id,
          {
            ...updateDto,
            confirmHistorical: true,
            previewToken: preview.historical.previewToken,
          } as never,
          {
            idempotencyKey: `plan-group-backdate-capacity-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toThrow('injected reservation failure');
      allocationFailure.mockRestore();
      expect(await planPersistenceShape(pool, created.id)).toEqual(
        beforeFailure,
      );

      await pool.query(
        "update app.subscriptions set lessons_total = 500 where id = $1",
        [fixture.subscriptionIds[0]],
      );
      const metadata = {
        idempotencyKey: `plan-group-backdate-confirmed-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      };
      const command = {
        ...updateDto,
        confirmHistorical: true,
        previewToken: preview.historical.previewToken,
      } as never;
      const updated = await plans.update(actor, created.id, command, metadata);
      expect(await plans.update(actor, created.id, command, metadata)).toEqual({
        ...updated,
        replayed: true,
      });
      const assignments = await pool.query<{
        prefix: string;
        original: string;
        overlaps: string;
        prefix_series: string;
      }>(
        `select
          count(*) filter (where effective_from = $2::date
            and effective_until = $3::date)::text as prefix,
          count(*) filter (where effective_from = $4::date)::text as original,
          (select count(*)::text
             from app.schedule_plan_participants left_row
             join app.schedule_plan_participants right_row
               on right_row.plan_id = left_row.plan_id
              and right_row.student_id = left_row.student_id
              and right_row.id > left_row.id
              and daterange(left_row.effective_from,
                    coalesce(left_row.effective_until, 'infinity'::date), '[]')
                && daterange(right_row.effective_from,
                    coalesce(right_row.effective_until, 'infinity'::date), '[]')
            where left_row.plan_id = $1) as overlaps,
          (select count(*)::text from app.schedule_series series
            where series.plan_id = $1 and series.valid_from = $2::date)
            as prefix_series
         from app.schedule_plan_participants where plan_id = $1`,
        [created.id, newStart, prefixUntil, fixture.today],
      );
      expect(assignments.rows[0]).toEqual({
        prefix: "2",
        original: "2",
        overlaps: "0",
        prefix_series: "1",
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects an oversized historical span in preview and commit", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const dto = {
      kind: "individual" as const,
      title: "Слишком длинная история",
      studentId: fixture.studentIds[0],
      subscriptionId: fixture.subscriptionIds[0],
      activeFrom: addDays(fixture.today, -367),
      activeUntil: addDays(fixture.today, 30),
      rows: [row(fixture, 1, "10:00")],
    };
    try {
      await expect(plans.previewConstraints(actor, dto)).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_HISTORICAL_RANGE_TOO_LARGE" },
      });
      await expect(
        plans.create(
          actor,
          {
            ...dto,
            confirmHistorical: true,
            previewToken: "invalid-preview-token",
          } as never,
          {
            idempotencyKey: `plan-history-range-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_HISTORICAL_RANGE_TOO_LARGE" },
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects too many plan occurrences before expanding rows", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const rows = Array.from({ length: 10 }, (_, index) => ({
      ...row(
        fixture,
        (index % 7) + 1,
        `${String(index + 8).padStart(2, "0")}:00`,
      ),
      durationMinutes: 30,
    }));
    try {
      await expect(
        plans.previewConstraints(actor, {
          kind: "individual",
          title: "Слишком много занятий",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: addDays(fixture.today, -300),
          activeUntil: addDays(fixture.today, 60),
          rows,
        }),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_OCCURRENCE_LIMIT_EXCEEDED" },
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("previews every row and explains overlaps inside the new plan before create", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const preview = await plans.previewConstraints(actor, {
        kind: "individual",
        title: "Проверка пересечений",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: [row(fixture, 1, "10:00"), row(fixture, 1, "10:30")],
      });

      expect(preview.valid).toBe(false);
      expect(preview.rows).toHaveLength(2);
      for (const [index, result] of preview.rows.entries()) {
        expect(result.valid).toBe(false);
        expect(result.occurrencesChecked).toBeGreaterThan(0);
        expect(result.failures).toEqual(
          expect.arrayContaining([
            expect.objectContaining({
              violations: expect.arrayContaining([
                expect.objectContaining({
                  code: "CLIENT_OVERLAP",
                  conflictingRowIndexes: [index === 0 ? 1 : 0],
                }),
                expect.objectContaining({ code: "TEACHER_OVERLAP" }),
                expect.objectContaining({ code: "ROOM_OVERLAP" }),
              ]),
            }),
          ]),
        );
      }
      const persisted = await pool.query<{ count: string }>(
        "select count(*)::text as count from app.schedule_plans where created_by = $1",
        [fixture.managerId],
      );
      expect(persisted.rows[0]?.count).toBe("0");
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("previews an effective Plan edit without self-conflicts and keeps rescheduled lessons as blockers", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const sourceRow = row(fixture, 2, "10:00");
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Предпросмотр изменения",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [sourceRow],
        },
        {
          idempotencyKey: `plan-update-preview-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const command = {
        expectedVersion: 1,
        effectiveFrom: fixture.effectiveFrom,
        rows: [
          {
            ...sourceRow,
            notes: "Изменённая строка",
            seriesId: created.seriesIds[0],
          },
        ],
      };

      const ownLessonsExcluded = await plans.previewUpdateConstraints(
        actor,
        created.id,
        command,
      );
      expect(ownLessonsExcluded.valid).toBe(true);
      expect(ownLessonsExcluded.rows).toEqual([
        expect.objectContaining({ valid: true, failures: [] }),
      ]);

      const rescheduled = await pool.query<{ id: string }>(
        `update app.lessons
         set original_scheduled_at = scheduled_at - interval '1 day'
         where id = (
           select lesson.id from app.lessons lesson
           where lesson.series_id = $1 and lesson.series_date >= $2::date
             and lesson.deleted_at is null
           order by lesson.series_date limit 1
         ) returning id`,
        [created.seriesIds[0], fixture.effectiveFrom],
      );
      expect(rescheduled.rows[0]?.id).toBeDefined();
      const preservedLessonBlocks = await plans.previewUpdateConstraints(
        actor,
        created.id,
        command,
      );
      expect(preservedLessonBlocks.valid).toBe(false);
      expect(preservedLessonBlocks.rows[0]!.failures).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            violations: expect.arrayContaining([
              expect.objectContaining({
                code: "CLIENT_OVERLAP",
                conflictingLessonIds: [rescheduled.rows[0]!.id],
              }),
            ]),
          }),
        ]),
      );
      const persisted = await pool.query<{
        version: string;
        active_series: string;
        deleted_lessons: string;
      }>(
        `select plan.version::text,
          (select count(*)::text from app.schedule_series series
           where series.plan_id = plan.id and series.deleted_at is null
             and series.superseded_by is null) as active_series,
          (select count(*)::text from app.lessons lesson
           join app.schedule_series series on series.id = lesson.series_id
           where series.plan_id = plan.id and lesson.deleted_at is not null)
             as deleted_lessons
         from app.schedule_plans plan where plan.id = $1`,
        [created.id],
      );
      expect(persisted.rows[0]).toEqual({
        version: "1",
        active_series: "1",
        deleted_lessons: "0",
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("creates a group plan with immutable participants and one reservation per subscription", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const participantAssignments = fixture.studentIds.map(
        (studentId, index) => ({
          studentId,
          subscriptionId: fixture.subscriptionIds[index]!,
        }),
      );
      const groupPreview = await plans.previewConstraints(actor, {
        kind: "group",
        title: "Группа ансамбля",
        groupId: fixture.groupId,
        activeFrom: fixture.today,
        activeUntil: fixture.until400,
        participants: participantAssignments,
        rows: [
          row(fixture, 3, "14:00", { clientIds: fixture.studentIds }),
          row(fixture, 3, "14:30", { clientIds: fixture.studentIds }),
        ],
      });
      expect(groupPreview.valid).toBe(false);
      expect(
        new Set(
          groupPreview.rows.flatMap((previewRow) =>
            previewRow.failures.map((failure) => failure.studentId),
          ),
        ),
      ).toEqual(new Set(fixture.studentIds));

      const created = await plans.create(
        actor,
        {
          kind: "group",
          title: "Группа ансамбля",
          groupId: fixture.groupId,
          activeFrom: fixture.today,
          activeUntil: fixture.until400,
          participants: participantAssignments,
          rows: [
            row(fixture, 3, "14:00", { clientIds: fixture.studentIds }),
          ],
        },
        {
          idempotencyKey: `plan-group-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const persisted = await pool.query<{
        participant_assignments: string;
        lessons: string;
        participant_snapshots: string;
        reservations: string;
        distinct_subscriptions: string;
      }>(
        `select
          (select count(*)::text from app.schedule_plan_participants where plan_id = $1)
            as participant_assignments,
          (select count(*)::text from app.lessons lesson join app.schedule_series series
             on series.id = lesson.series_id where series.plan_id = $1 and lesson.deleted_at is null)
            as lessons,
          (select count(*)::text from app.lesson_snapshot_participants participant
             join app.lessons lesson on lesson.id = participant.lesson_id
             join app.schedule_series series on series.id = lesson.series_id where series.plan_id = $1)
            as participant_snapshots,
          (select count(*)::text from app.lesson_reservations reservation
             join app.lessons lesson on lesson.id = reservation.lesson_id
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = $1 and reservation.state = 'reserved') as reservations,
          (select count(distinct reservation.subscription_id)::text
             from app.lesson_reservations reservation join app.lessons lesson
               on lesson.id = reservation.lesson_id join app.schedule_series series
               on series.id = lesson.series_id where series.plan_id = $1) as distinct_subscriptions`,
        [created.id],
      );
      const lessonCount = Number(persisted.rows[0]!.lessons);
      expect(lessonCount).toBeGreaterThan(0);
      expect(persisted.rows[0]).toEqual({
        participant_assignments: "2",
        lessons: String(lessonCount),
        participant_snapshots: String(lessonCount * 2),
        reservations: String(lessonCount * 2),
        distinct_subscriptions: "2",
      });
      const projection = await plans.list(actor, {
        groupId: fixture.groupId,
        includeEnded: true,
      });
      expect(projection.items).toEqual([
        expect.objectContaining({
          id: created.id,
          kind: "group",
          title: "Группа ансамбля",
          version: 1,
          rows: [expect.objectContaining({ active: true })],
          participants: expect.arrayContaining([
            expect.objectContaining({ studentId: fixture.studentIds[0] }),
            expect.objectContaining({ studentId: fixture.studentIds[1] }),
          ]),
        }),
      ]);
      const participantProjection = await plans.list(actor, {
        studentId: fixture.studentIds[0],
        includeEnded: true,
      });
      expect(participantProjection.items).toEqual([
        expect.objectContaining({
          id: created.id,
          kind: "group",
          rows: [
            expect.objectContaining({
              teacherName: "Plan Teacher",
              roomName: expect.stringContaining("Plan room"),
              branchName: expect.stringContaining("Plan branch"),
            }),
          ],
        }),
      ]);
      const updated = await plans.update(
        actor,
        created.id,
        {
          expectedVersion: 1,
          effectiveFrom: fixture.effectiveFrom,
          rows: [
            {
              ...row(fixture, 3, "15:00", {
                clientIds: fixture.studentIds,
              }),
              seriesId: created.seriesIds[0],
            },
          ],
        },
        {
          idempotencyKey: `plan-group-edit-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      expect(updated).toMatchObject({ version: 2, replayed: false });
      const assignments = await pool.query<{
        historical: string;
        current: string;
      }>(
        `select count(*)::text as historical,
          count(*) filter (where effective_from = $2::date)::text as current
         from app.schedule_plan_participants where plan_id = $1`,
        [created.id, fixture.effectiveFrom],
      );
      expect(assignments.rows[0]).toEqual({ historical: "4", current: "2" });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("materializes each group participant's frozen payer and partial minutes once", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "director" as const };
    try {
      await pool.query("update app.users set role = 'director' where id = $1", [
        fixture.managerId,
      ]);
      const participants = fixture.studentIds.map((studentId, index) => ({
        studentId,
        subscriptionId: fixture.subscriptionIds[index]!,
      }));
      const created = await plans.create(
        actor,
        {
          kind: "group",
          title: "Разные плательщики",
          groupId: fixture.groupId,
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          participants,
          rows: [
            {
              ...row(fixture, 3, "14:00"),
              plannedSettlementReason: "Согласовано директором",
              financialDecision: {
                settlementTypeKey: "partially_paid_lesson",
                teacherCompensationRuleKey: "percent",
                teacherCreditedDurationMinutes: 45,
                teacherCompensationSource: "manual" as const,
                clientDecisions: [
                  {
                    clientId: fixture.studentIds[0]!,
                    payerStudentId: fixture.studentIds[1]!,
                    subscriptionId: fixture.subscriptionIds[1]!,
                    chargeType: "subscription" as const,
                    chargeDurationMinutes: 30,
                  },
                  {
                    clientId: fixture.studentIds[1]!,
                    payerStudentId: fixture.studentIds[0]!,
                    subscriptionId: fixture.subscriptionIds[0]!,
                    chargeType: "subscription" as const,
                    chargeDurationMinutes: 45,
                  },
                ],
              },
            },
          ],
        },
        {
          idempotencyKey: `plan-group-partial-${randomUUID()}`,
          requestId: randomUUID(),
        },
      );
      const materialized = await pool.query<{
        student_id: string;
        subscription_id: string;
        charge_value: string;
      }>(
        `select participant.student_id, participant.subscription_id,
           participant.charge_value::text
         from app.lesson_snapshot_participants participant
         join app.lessons lesson on lesson.id = participant.lesson_id
         where lesson.series_id = $1
         order by participant.lesson_id, participant.student_id`,
        [created.seriesIds[0]],
      );
      expect(materialized.rows.length).toBeGreaterThan(0);
      for (const lessonId of created.lessonIds) {
        const reservations = await pool.query<{ units: string }>(
          "select units::text from app.lesson_reservations where lesson_id = $1 order by units",
          [lessonId],
        );
        expect(reservations.rows.map((item) => item.units)).toEqual([
          "0.50",
          "0.75",
        ]);
      }
      const firstLessonParticipants = materialized.rows.slice(0, 2);
      expect(
        firstLessonParticipants.map((item) => ({
          studentId: item.student_id,
          subscriptionId: item.subscription_id,
          units: item.charge_value,
        })),
      ).toEqual(
        expect.arrayContaining([
          {
            studentId: fixture.studentIds[0],
            subscriptionId: fixture.subscriptionIds[1],
            units: "0.50",
          },
          {
            studentId: fixture.studentIds[1],
            subscriptionId: fixture.subscriptionIds[0],
            units: "0.75",
          },
        ]),
      );
      const plansPerLesson = await pool.query<{ count: string }>(
        `select count(*)::text
         from app.lesson_settlement_plans settlement
         join app.lessons lesson on lesson.id = settlement.lesson_id
         where lesson.series_id = $1`,
        [created.seriesIds[0]],
      );
      expect(plansPerLesson.rows[0]!.count).toBe(String(created.lessonIds.length));
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("applies one concurrent effective edit and leaves earlier snapshots unchanged", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Фортепиано",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [row(fixture, 2, "10:00")],
        },
        {
          idempotencyKey: `plan-edit-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const before = await pool.query<{ id: string; snapshot: string }>(
        `select lesson.id, row_to_json(snapshot.*)::text as snapshot
         from app.lessons lesson join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
         where lesson.series_id = $1 and lesson.series_date < $2::date
         order by lesson.series_date`,
        [created.seriesIds[0], fixture.effectiveFrom],
      );
      expect(before.rows.length).toBeGreaterThan(0);
      const base = {
        expectedVersion: 1,
        effectiveFrom: fixture.effectiveFrom,
        rows: [
          {
            ...row(fixture, 2, "12:00"),
            seriesId: created.seriesIds[0],
          },
        ],
      };
      const results = await Promise.allSettled([
        plans.update(actor, created.id, base, {
          idempotencyKey: `plan-edit-a-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        }),
        plans.update(
          actor,
          created.id,
          {
            ...base,
            rows: [{ ...base.rows[0], beginTime: "13:00" }],
          },
          {
            idempotencyKey: `plan-edit-b-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ]);
      expect(
        results.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      expect(
        results.filter((result) => result.status === "rejected"),
      ).toHaveLength(1);
      const succeeded = results.find(
        (result) => result.status === "fulfilled",
      )!;
      expect(succeeded.value).toMatchObject({ version: 2, replayed: false });

      const after = await pool.query<{ id: string; snapshot: string }>(
        `select lesson.id, row_to_json(snapshot.*)::text as snapshot
         from app.lessons lesson join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
         where lesson.id = any($1::uuid[]) order by lesson.series_date`,
        [before.rows.map((row) => row.id)],
      );
      expect(after.rows).toEqual(before.rows);
      const continuation = await pool.query<{
        version: string;
        valid_from: string;
        old_future_active: string;
        released: string;
      }>(
        `select plan.version::text, series.valid_from::text,
          (select count(*)::text from app.lessons old_lesson
             where old_lesson.series_id = $2 and old_lesson.series_date >= $3::date
               and old_lesson.deleted_at is null and old_lesson.lifecycle_state = 'scheduled')
            as old_future_active,
          (select count(*)::text from app.lesson_reservations reservation
             join app.lessons old_lesson on old_lesson.id = reservation.lesson_id
             where old_lesson.series_id = $2 and old_lesson.series_date >= $3::date
               and reservation.state = 'released') as released
         from app.schedule_plans plan join app.schedule_series series
           on series.plan_id = plan.id and series.valid_from = $3::date
         where plan.id = $1`,
        [created.id, created.seriesIds[0], fixture.effectiveFrom],
      );
      expect(continuation.rows[0]).toMatchObject({
        version: "2",
        valid_from: fixture.effectiveFrom,
        old_future_active: "0",
      });
      expect(Number(continuation.rows[0]!.released)).toBeGreaterThan(0);
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("ends a plan mid-week, preserves history and terminal lessons, and replays once", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Завершаемое расписание",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [row(fixture, 1, "10:00"), row(fixture, 4, "11:00")],
        },
        {
          idempotencyKey: `plan-end-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const lastDate = addDays(fixture.today, 14);
      const before = await pool.query<{
        id: string;
        series_date: string;
        lifecycle_state: string;
        version: string;
      }>(
        `select lesson.id, lesson.series_date::text, lesson.lifecycle_state,
          lesson.version::text
         from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id
         where series.plan_id = $1 order by lesson.series_date, lesson.id`,
        [created.id],
      );
      const historical = before.rows.find(
        (lesson) => lesson.series_date <= lastDate,
      )!;
      const terminal = before.rows.find(
        (lesson) => lesson.series_date > lastDate,
      )!;
      expect(historical).toBeDefined();
      expect(terminal).toBeDefined();
      await pool.query(
        "update app.lessons set lifecycle_state = 'cancelled' where id = $1",
        [terminal.id],
      );
      await pool.query(
        "update app.lesson_reservations set state = 'released' where lesson_id = $1",
        [terminal.id],
      );

      const preview = await plans.previewEnd(actor, created.id, {
        expectedVersion: 1,
        lastDate,
        reasonText: "Клиент завершил регулярные занятия",
      });
      expect(preview).toMatchObject({
        canConfirm: true,
        confirmRequired: true,
        impact: { preservedTerminalLessons: 1 },
      });
      expect(preview.impact.futureUnsettledLessons).toBeGreaterThan(0);
      const command = {
        expectedVersion: 1,
        lastDate,
        reasonText: "Клиент завершил регулярные занятия",
        previewToken: preview.previewToken,
        confirm: true as const,
      };
      const key = `plan-end-${randomUUID()}`;
      const ended = await plans.end(actor, created.id, command, {
        idempotencyKey: key,
        requestId: `request-${randomUUID()}`,
      });
      const replay = await plans.end(actor, created.id, command, {
        idempotencyKey: key,
        requestId: `request-${randomUUID()}`,
      });
      expect(ended).toMatchObject({
        status: "ended",
        version: 2,
        replayed: false,
        preservedTerminalLessons: 1,
      });
      expect(replay).toEqual({ ...ended, replayed: true });

      const persisted = await pool.query<{
        status: string;
        active_until: string;
        end_reason: string;
        active_series_after_end: string;
        uncancelled_future: string;
        end_transitions: string;
        reserved_future: string;
        historical_state: string;
        historical_version: string;
        terminal_state: string;
      }>(
        `select plan.status, plan.active_until::text, plan.end_reason,
          (select count(*)::text from app.schedule_series series
             where series.plan_id = plan.id and series.deleted_at is null
               and series.superseded_by is null and series.valid_until > $2::date)
            as active_series_after_end,
          (select count(*)::text from app.lessons lesson
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = plan.id and lesson.series_date > $2::date
               and lesson.lifecycle_state in ('scheduled', 'settlement_pending'))
            as uncancelled_future,
          (select count(*)::text from app.lesson_transitions transition
             join app.schedule_series series on series.id = (
               select lesson.series_id from app.lessons lesson where lesson.id = transition.lesson_id
             ) where series.plan_id = plan.id and transition.reason_code = 'schedule.plan.end')
            as end_transitions,
          (select count(*)::text from app.lesson_reservations reservation
             join app.lessons lesson on lesson.id = reservation.lesson_id
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = plan.id and lesson.series_date > $2::date
               and reservation.state = 'reserved') as reserved_future,
          (select lifecycle_state from app.lessons where id = $3) as historical_state,
          (select version::text from app.lessons where id = $3) as historical_version,
          (select lifecycle_state from app.lessons where id = $4) as terminal_state
         from app.schedule_plans plan where plan.id = $1`,
        [created.id, lastDate, historical.id, terminal.id],
      );
      expect(persisted.rows[0]).toEqual({
        status: "ended",
        active_until: lastDate,
        end_reason: command.reasonText,
        active_series_after_end: "0",
        uncancelled_future: "0",
        end_transitions: String(ended.endedLessons),
        reserved_future: "0",
        historical_state: historical.lifecycle_state,
        historical_version: historical.version,
        terminal_state: "cancelled",
      });

      const projection = await plans.list(actor, {
        studentId: fixture.studentIds[0],
        includeEnded: true,
      });
      expect(
        projection.items.find((item) => item.id === created.id),
      ).toMatchObject({
        status: "ended",
        version: 2,
        activeUntil: lastDate,
        endedBy: fixture.managerId,
        endedByName: "Мария Управляющая",
        endReason: command.reasonText,
      });
      const owner = await pool.query<{ user_id: string }>(
        `select profile.user_id from app.students student
         join app.profiles profile on profile.id = student.profile_id
         where student.id = $1`,
        [fixture.studentIds[0]],
      );
      const clientProjection = await plans.list(
        {
          userId: owner.rows[0]!.user_id,
          role: "client",
        },
        {
          studentId: fixture.studentIds[0],
          includeEnded: true,
        },
      );
      expect(
        clientProjection.items.find((item) => item.id === created.id),
      ).toMatchObject({
        status: "ended",
        endedBy: null,
        endedByName: null,
        endReason: null,
      });

      await expect(
        plans.update(
          actor,
          created.id,
          {
            expectedVersion: 2,
            effectiveFrom: addDays(lastDate, 1),
            title: "Нельзя вернуть завершённый Plan",
            subscriptionId: fixture.subscriptionIds[0],
            activeUntil: lastDate,
            rows: [
              { ...row(fixture, 1, "10:00"), seriesId: created.seriesIds[0] },
            ],
          },
          {
            idempotencyKey: `plan-ended-update-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({ response: { code: "SCHEDULE_PLAN_ENDED" } });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects a stale end preview and rolls the whole end mutation back on failure", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Атомарное завершение",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: [row(fixture, 2, "10:00"), row(fixture, 5, "11:00")],
        },
        {
          idempotencyKey: `plan-atomic-source-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const lastDate = addDays(fixture.today, 14);
      const base = {
        expectedVersion: 1,
        lastDate,
        reasonText: "Проверка атомарности",
      };
      const stale = await plans.previewEnd(actor, created.id, base);
      const changed = await pool.query<{ id: string }>(
        `update app.lessons set lifecycle_state = 'cancelled'
         where id = (select lesson.id from app.lessons lesson
           join app.schedule_series series on series.id = lesson.series_id
           where series.plan_id = $1 and lesson.series_date > $2::date
             and lesson.lifecycle_state = 'scheduled' order by lesson.series_date limit 1)
         returning id`,
        [created.id, lastDate],
      );
      await pool.query(
        "update app.lesson_reservations set state = 'released' where lesson_id = $1",
        [changed.rows[0]!.id],
      );
      await expect(
        plans.end(
          actor,
          created.id,
          {
            ...base,
            previewToken: stale.previewToken,
            confirm: true,
          },
          {
            idempotencyKey: `plan-stale-${randomUUID()}`,
            requestId: `request-${randomUUID()}`,
          },
        ),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_END_PREVIEW_STALE" },
      });

      const fresh = await plans.previewEnd(actor, created.id, base);
      const before = await pool.query<{ scheduled: string; reserved: string }>(
        `select
          (select count(*)::text from app.lessons lesson join app.schedule_series series
             on series.id = lesson.series_id where series.plan_id = $1
               and lesson.series_date > $2::date and lesson.lifecycle_state = 'scheduled') as scheduled,
          (select count(*)::text from app.lesson_reservations reservation
             join app.lessons lesson on lesson.id = reservation.lesson_id
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = $1 and lesson.series_date > $2::date
               and reservation.state = 'reserved') as reserved`,
        [created.id, lastDate],
      );
      expect(Number(before.rows[0]!.scheduled)).toBeGreaterThan(1);
      const originalAppend = lifecycle.appendTransition.bind(lifecycle);
      let appendCount = 0;
      const fault = jest
        .spyOn(lifecycle, "appendTransition")
        .mockImplementation((client, input) => {
          appendCount += 1;
          if (appendCount === 2) throw new Error("injected plan-end failure");
          return originalAppend(client, input);
        });
      try {
        await expect(
          plans.end(
            actor,
            created.id,
            {
              ...base,
              previewToken: fresh.previewToken,
              confirm: true,
            },
            {
              idempotencyKey: `plan-fault-${randomUUID()}`,
              requestId: `request-${randomUUID()}`,
            },
          ),
        ).rejects.toThrow("injected plan-end failure");
      } finally {
        fault.mockRestore();
      }
      const after = await pool.query<{
        status: string;
        version: string;
        scheduled: string;
        reserved: string;
        transitions: string;
      }>(
        `select plan.status, plan.version::text,
          (select count(*)::text from app.lessons lesson join app.schedule_series series
             on series.id = lesson.series_id where series.plan_id = plan.id
               and lesson.series_date > $2::date and lesson.lifecycle_state = 'scheduled') as scheduled,
          (select count(*)::text from app.lesson_reservations reservation
             join app.lessons lesson on lesson.id = reservation.lesson_id
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = plan.id and lesson.series_date > $2::date
               and reservation.state = 'reserved') as reserved,
          (select count(*)::text from app.lesson_transitions transition
             join app.lessons lesson on lesson.id = transition.lesson_id
             join app.schedule_series series on series.id = lesson.series_id
             where series.plan_id = plan.id and transition.reason_code = 'schedule.plan.end')
            as transitions
         from app.schedule_plans plan where plan.id = $1`,
        [created.id, lastDate],
      );
      expect(after.rows[0]).toEqual({
        status: "active",
        version: "1",
        scheduled: before.rows[0]!.scheduled,
        reserved: before.rows[0]!.reserved,
        transitions: "0",
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("pages a bounded plan tray without duplicates and does not leak it to another client", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const created = await plans.create(
        actor,
        {
          kind: "individual",
          title: "Длинный трей",
          studentId: fixture.studentIds[0],
          subscriptionId: fixture.subscriptionIds[0],
          activeFrom: fixture.today,
          activeUntil: fixture.until60,
          rows: Array.from({ length: 7 }, (_, index) =>
            row(fixture, index + 1, "18:00"),
          ),
        },
        {
          idempotencyKey: `plan-tray-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        },
      );
      const linkedLessons = await pool.query<{ id: string }>(
        `select lesson.id
           from app.lessons lesson
           join app.schedule_series series on series.id = lesson.series_id
          where series.plan_id = $1
          order by lesson.scheduled_at, lesson.id
          limit 2`,
        [created.id],
      );
      const sourceLessonId = linkedLessons.rows[0]!.id;
      const successorLessonId = linkedLessons.rows[1]!.id;
      await pool.query(
        `update app.lessons
            set scheduled_at = date_trunc('day', now()) + interval '1 day 5 hours'
              + case when id = $2 then interval '1 hour' else interval '0' end
          where id = any($1::uuid[])`,
        [[sourceLessonId, successorLessonId], successorLessonId],
      );
      await pool.query(
        "update app.lessons set successor_id = $2 where id = $1",
        [sourceLessonId, successorLessonId],
      );
      await pool.query(
        "update app.lessons set predecessor_id = $2 where id = $1",
        [successorLessonId, sourceLessonId],
      );
      await pool.query(
        `insert into app.lesson_client_charge_facts (
           lesson_id, client_type, client_id, charge_type, snapshot_value,
           amount_minor, units, settlement_type_key, settlement_label,
           settlement_color_token, hour_share_basis_points,
           fixed_penalty_minor, configuration_revision_id
         )
         select $1, 'student', $2, 'none', 0, 0, 0,
           'paid_absence', 'Оплачиваемый пропуск', 'blue', 10000, 0,
           revision.id
         from app.crm_configuration_revisions revision
         where revision.branch_id is null
         order by revision.version desc
         limit 1`,
        [sourceLessonId, fixture.studentIds[0]],
      );

      await expect(
        plans.tray(actor, created.id, { direction: "next" }),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_TRAY_CURSOR_REQUIRED" },
      });
      await expect(
        plans.tray(actor, created.id, { cursor: "not-a-valid-cursor" }),
      ).rejects.toMatchObject({
        response: { code: "SCHEDULE_PLAN_TRAY_CURSOR_INVALID" },
      });

      const ids: string[] = [];
      let page = await plans.tray(actor, created.id, { limit: 10 });
      const firstPageIds = page.items.map((item) => item.id);
      expect(
        page.items.find((item) => item.id === sourceLessonId),
      ).toMatchObject({
        relationMarker: "source",
        successorId: successorLessonId,
        settlementMarkers: expect.arrayContaining([
          {
            key: "paid_absence",
            label: "Оплачиваемый пропуск",
            colorToken: "blue",
          },
        ]),
      });
      expect(
        page.items.find((item) => item.id === successorLessonId),
      ).toMatchObject({
        relationMarker: "successor",
        predecessorId: sourceLessonId,
      });
      expect(page.nextCursor).toBeTruthy();
      const nextPage = await plans.tray(actor, created.id, {
        limit: 10,
        cursor: page.nextCursor!,
        direction: "next",
      });
      expect(nextPage.previousCursor).toBeTruthy();
      const returnedPage = await plans.tray(actor, created.id, {
        limit: 10,
        cursor: nextPage.previousCursor!,
        direction: "previous",
      });
      expect(returnedPage.items.map((item) => item.id)).toEqual(firstPageIds);

      for (let pageNumber = 0; pageNumber < 10; pageNumber += 1) {
        expect(page.items.length).toBeLessThanOrEqual(10);
        expect(page.items).toEqual(
          [...page.items].sort(
            (left, right) =>
              left.scheduledAt.localeCompare(right.scheduledAt) ||
              left.id.localeCompare(right.id),
          ),
        );
        ids.push(...page.items.map((item) => item.id));
        if (!page.nextCursor) break;
        page = await plans.tray(actor, created.id, {
          limit: 10,
          cursor: page.nextCursor,
          direction: "next",
        });
      }
      expect(ids.length).toBeGreaterThan(40);
      expect(new Set(ids).size).toBe(ids.length);
      expect(page.hasNext).toBe(false);
      expect(ids[0]).toBeDefined();
      const owner = await pool.query<{ user_id: string }>(
        `select profile.user_id from app.students student
         join app.profiles profile on profile.id = student.profile_id
         where student.id = $1`,
        [fixture.studentIds[0]],
      );
      const clientTray = await plans.tray(
        {
          userId: owner.rows[0]!.user_id,
          role: "client",
        },
        created.id,
        { limit: 5 },
      );
      expect(clientTray.items.length).toBeGreaterThan(0);
      const hidden = await plans.tray(
        {
          userId: randomUUID(),
          role: "client",
        },
        created.id,
        { limit: 5 },
      );
      expect(hidden).toMatchObject({
        items: [],
        hasPrevious: false,
        hasNext: false,
      });

      await pool.query(
        `insert into app.schedule_plans (
           kind, title, student_id, subscription_id, active_from, active_until,
           status, ended_at, ended_by, end_reason, created_by
         ) select 'individual', 'Архив ' || item,
           $1, $2, current_date - item, current_date - item,
           'ended', now(), $3, 'Тест ограничения истории', $3
         from generate_series(1, 22) item`,
        [fixture.studentIds[0], fixture.subscriptionIds[0], fixture.managerId],
      );
      const bounded = await plans.list(actor, {
        studentId: fixture.studentIds[0],
        includeEnded: true,
      });
      expect(
        bounded.items.filter((item) => item.status === "active"),
      ).toHaveLength(1);
      expect(
        bounded.items.filter((item) => item.status === "ended"),
      ).toHaveLength(20);
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("revalidates horizon candidates atomically and uses the branch timezone", async () => {
    const fixture = await createFixture(pool);
    const client = await pool.connect();
    try {
      await client.query("begin");
      await client.query(
        "update app.branches set timezone_name = 'Asia/Yekaterinburg' where id = $1",
        [fixture.branchId],
      );
      const candidate = await client.query<{
        local_date: string;
        weekday: number;
        starts_at: Date;
        ends_at: Date;
      }>(
        `select local_date::text, extract(isodow from local_date)::int as weekday,
           (local_date + time '10:00') at time zone 'Asia/Yekaterinburg' as starts_at,
           (local_date + time '11:00') at time zone 'Asia/Yekaterinburg' as ends_at
         from (
           select timezone('Asia/Yekaterinburg', now())::date + 1 as local_date
         ) target`,
      );
      const slot = candidate.rows[0]!;
      const otherUser = await client.query<{ id: string }>(
        "insert into app.users (email, role, email_verified_at) values ($1, 'teacher', now()) returning id",
        [`horizon-other-${randomUUID()}@example.test`],
      );
      const otherProfile = await client.query<{ id: string }>(
        "insert into app.profiles (user_id, first_name, last_name) values ($1, 'Other', 'Teacher') returning id",
        [otherUser.rows[0]!.id],
      );
      const otherTeacher = await client.query<{ id: string }>(
        "insert into app.teachers (profile_id) values ($1) returning id",
        [otherProfile.rows[0]!.id],
      );
      const otherRoom = await client.query<{ id: string }>(
        "insert into app.rooms (branch_id, name) values ($1, $2) returning id",
        [fixture.branchId, `Horizon room ${randomUUID()}`],
      );
      const busy = await client.query<{ id: string }>(
        `insert into app.lessons (
           student_id, teacher_id, branch_id, room_id, scheduled_at,
           duration_minutes, created_by
         ) values ($1,$2,$3,$4,$5::timestamptz + interval '30 minutes',60,$6)
         returning id`,
        [
          fixture.studentIds[0],
          otherTeacher.rows[0]!.id,
          fixture.branchId,
          otherRoom.rows[0]!.id,
          slot.starts_at,
          fixture.managerId,
        ],
      );
      const series = await client.query<{ id: string }>(
        `insert into app.schedule_series (
           student_id, teacher_id, room_id, branch_id, weekday, begin_time,
           duration_minutes, valid_from, valid_until, created_by
         ) values ($1,$2,$3,$4,$5,'10:00',60,$6::date,$6::date,$7)
         returning id`,
        [
          fixture.studentIds[0],
          fixture.teacherId,
          fixture.roomId,
          fixture.branchId,
          slot.weekday,
          slot.local_date,
          fixture.managerId,
        ],
      );
      const seriesId = series.rows[0]!.id;

      await expect(
        materializer.materializePlanSeries(client, seriesId),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
          violations: expect.arrayContaining([
            expect.objectContaining({
              code: "CLIENT_OVERLAP",
              conflictingLessonIds: [busy.rows[0]!.id],
            }),
          ]),
        }),
      });
      await expect(seriesLessonCount(client, seriesId)).resolves.toBe(0);

      await client.query("delete from app.lessons where id = $1", [
        busy.rows[0]!.id,
      ]);
      await client.query(
        `insert into app.branch_hour_exceptions (
           branch_id, local_date, closed, reason
         ) values ($1,$2::date,true,'UAT-092 closed day')`,
        [fixture.branchId, slot.local_date],
      );
      await expect(
        materializer.materializePlanSeries(client, seriesId),
      ).rejects.toMatchObject({
        response: expect.objectContaining({
          code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
          violations: expect.arrayContaining([
            expect.objectContaining({ code: "OUTSIDE_BRANCH_HOURS" }),
          ]),
        }),
      });
      await expect(seriesLessonCount(client, seriesId)).resolves.toBe(0);

      await client.query(
        "delete from app.branch_hour_exceptions where branch_id = $1 and local_date = $2::date",
        [fixture.branchId, slot.local_date],
      );
      await expect(
        materializer.materializePlanSeries(client, seriesId),
      ).resolves.toBe(1);
      const materialized = await client.query<{ scheduled_at: Date }>(
        "select scheduled_at from app.lessons where series_id = $1",
        [seriesId],
      );
      expect(materialized.rows[0]!.scheduled_at.toISOString()).toBe(
        slot.starts_at.toISOString(),
      );
    } finally {
      await client.query("rollback");
      client.release();
      await cleanup(pool, fixture);
    }
  });
});

async function seriesLessonCount(client: PoolClient, seriesId: string) {
  const result = await client.query<{ count: string }>(
    "select count(*)::text as count from app.lessons where series_id = $1",
    [seriesId],
  );
  return Number(result.rows[0]?.count ?? 0);
}

async function backendPid(client: PoolClient) {
  const result = await client.query<{ pid: number }>(
    "select pg_backend_pid() as pid",
  );
  return result.rows[0]!.pid;
}

async function waitForBlockedBy(pool: Pool, blockerPid: number) {
  for (let attempt = 0; attempt < 1_000; attempt += 1) {
    const result = await pool.query<{ pid: number }>(
      `select pid from pg_stat_activity
       where $1::int = any(pg_blocking_pids(pid))
       order by pid limit 1`,
      [blockerPid],
    );
    if (result.rows[0]) return result.rows[0].pid;
  }
  throw new Error(`No backend became blocked by PostgreSQL pid ${blockerPid}.`);
}

async function waitForSpecificBlock(
  pool: Pool,
  blockedPid: number,
  blockerPid: number,
) {
  for (let attempt = 0; attempt < 1_000; attempt += 1) {
    const result = await pool.query<{ blocked: boolean }>(
      "select $2::int = any(pg_blocking_pids($1::int)) as blocked",
      [blockedPid, blockerPid],
    );
    if (result.rows[0]!.blocked) return;
  }
  throw new Error(
    `PostgreSQL pid ${blockedPid} was not blocked by pid ${blockerPid}.`,
  );
}

function isoWeekday(date: string) {
  const day = new Date(`${date}T00:00:00.000Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

async function planPersistenceShape(pool: Pool, planId: string) {
  const result = await pool.query<{
    active_from: string;
    version: string;
    series: string;
    lessons: string;
    participants: string;
  }>(
    `select plan.active_from::text, plan.version::text,
      (select count(*)::text from app.schedule_series series
        where series.plan_id = plan.id) as series,
      (select count(*)::text from app.lessons lesson
        join app.schedule_series series on series.id = lesson.series_id
        where series.plan_id = plan.id) as lessons,
      (select count(*)::text from app.schedule_plan_participants participant
        where participant.plan_id = plan.id) as participants
     from app.schedule_plans plan where plan.id = $1`,
    [planId],
  );
  return result.rows[0]!;
}

async function planSeriesArtifacts(pool: Pool, seriesIds: string[]) {
  const result = await pool.query<{
    series: string;
    lessons: string;
    snapshots: string;
    participants: string;
    settlement_plans: string;
    settlement_revisions: string;
    reservations: string;
  }>(
    `select
      coalesce((select jsonb_agg(to_jsonb(series) order by series.id)
        from app.schedule_series series where series.id = any($1::uuid[])),
        '[]'::jsonb)::text as series,
      coalesce((select jsonb_agg(to_jsonb(lesson) order by lesson.id)
        from app.lessons lesson where lesson.series_id = any($1::uuid[])),
        '[]'::jsonb)::text as lessons,
      coalesce((select jsonb_agg(to_jsonb(snapshot) order by snapshot.lesson_id)
        from app.lesson_snapshots snapshot join app.lessons lesson
          on lesson.id = snapshot.lesson_id
        where lesson.series_id = any($1::uuid[])), '[]'::jsonb)::text as snapshots,
      coalesce((select jsonb_agg(to_jsonb(participant)
          order by participant.lesson_id, participant.student_id)
        from app.lesson_snapshot_participants participant join app.lessons lesson
          on lesson.id = participant.lesson_id
        where lesson.series_id = any($1::uuid[])), '[]'::jsonb)::text as participants,
      coalesce((select jsonb_agg(to_jsonb(plan) order by plan.lesson_id)
        from app.lesson_settlement_plans plan join app.lessons lesson
          on lesson.id = plan.lesson_id
        where lesson.series_id = any($1::uuid[])), '[]'::jsonb)::text
        as settlement_plans,
      coalesce((select jsonb_agg(to_jsonb(revision)
          order by revision.lesson_id, revision.version)
        from app.lesson_settlement_plan_revisions revision join app.lessons lesson
          on lesson.id = revision.lesson_id
        where lesson.series_id = any($1::uuid[])), '[]'::jsonb)::text
        as settlement_revisions,
      coalesce((select jsonb_agg(to_jsonb(reservation) order by reservation.id)
        from app.lesson_reservations reservation join app.lessons lesson
          on lesson.id = reservation.lesson_id
        where lesson.series_id = any($1::uuid[])), '[]'::jsonb)::text
        as reservations`,
    [seriesIds],
  );
  return result.rows[0]!;
}

async function lessonArtifact(pool: Pool, lessonId: string) {
  const result = await pool.query<{
    lesson: string;
    snapshots: string;
    reservations: string;
  }>(
    `select row_to_json(lesson)::text as lesson,
      coalesce((select jsonb_agg(to_jsonb(snapshot) order by snapshot.lesson_id)
        from app.lesson_snapshots snapshot where snapshot.lesson_id = lesson.id),
        '[]'::jsonb)::text as snapshots,
      coalesce((select jsonb_agg(to_jsonb(reservation) order by reservation.id)
        from app.lesson_reservations reservation
        where reservation.lesson_id = lesson.id), '[]'::jsonb)::text
        as reservations
     from app.lessons lesson where lesson.id = $1`,
    [lessonId],
  );
  return result.rows[0]!;
}

function row(
  fixture: Awaited<ReturnType<typeof createFixture>>,
  weekday: number,
  beginTime: string,
  resources: {
    teacherId?: string;
    roomId?: string;
    clientIds?: string[];
    omitClientDecisions?: boolean;
  } = {},
) {
  return {
    teacherId: resources.teacherId ?? fixture.teacherId,
    roomId: resources.roomId ?? fixture.roomId,
    branchId: fixture.branchId,
    weekday,
    beginTime,
    durationMinutes: 60,
    financialDecision: {
      settlementTypeKey: "lesson",
      ...(resources.omitClientDecisions
        ? {}
        : {
            clientDecisions: (resources.clientIds ?? [fixture.studentIds[0]!])
              .map((clientId) => ({
                clientId,
                chargeDurationMinutes: 60,
              })),
          }),
    } as ConfiguredLessonFinancialDecisionDto,
  };
}

async function createAdditionalPlanResource(pool: Pool, branchId: string) {
  const roomName = `Plan room B ${randomUUID()}`;
  const room = await pool.query<{ id: string }>(
    "insert into app.rooms (branch_id, name) values ($1, $2) returning id",
    [branchId, roomName],
  );
  const user = await pool.query<{ id: string }>(
    "insert into app.users (email, role, email_verified_at) values ($1, 'teacher', now()) returning id",
    [`plan-teacher-b-${randomUUID()}@example.test`],
  );
  const profile = await pool.query<{ id: string }>(
    "insert into app.profiles (user_id, first_name, last_name) values ($1, 'Second', 'Plan Teacher') returning id",
    [user.rows[0]!.id],
  );
  const teacher = await pool.query<{ id: string }>(
    "insert into app.teachers (profile_id) values ($1) returning id",
    [profile.rows[0]!.id],
  );
  await pool.query(
    `insert into app.teacher_branches (teacher_id, branch_id, active_from, active_until)
     values ($1, $2, '2020-01-01', '2100-12-31')`,
    [teacher.rows[0]!.id, branchId],
  );
  await pool.query(
    `insert into app.teacher_availability_rules (
       teacher_id, kind, available, timezone_name, weekday,
       local_start, local_end, valid_from, valid_until
     ) select $1, 'recurring', true, 'Europe/Moscow', day,
       '08:00', '22:00', '2020-01-01', '2100-12-31'
       from generate_series(1, 7) day`,
    [teacher.rows[0]!.id],
  );
  return {
    roomId: room.rows[0]!.id,
    roomName,
    teacherId: teacher.rows[0]!.id,
    profileId: profile.rows[0]!.id,
    userId: user.rows[0]!.id,
  };
}

function addDays(date: string, days: number) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

async function createFixture(pool: Pool) {
  const dates = await pool.query<{
    today: string;
    until60: string;
    until400: string;
    effective_from: string;
  }>(`select timezone('Europe/Moscow', now())::date::text as today,
      (timezone('Europe/Moscow', now())::date + 60)::text as until60,
      (timezone('Europe/Moscow', now())::date + 400)::text as until400,
      (timezone('Europe/Moscow', now())::date + 21)::text as effective_from`);
  const branch = await pool.query<{ id: string }>(
    "insert into app.branches (name, timezone_name) values ($1, 'Europe/Moscow') returning id",
    [`Plan branch ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  await pool.query(
    `insert into app.branch_hours (branch_id, weekday, open_local, close_local)
     select $1, day, '08:00', '22:00' from generate_series(1, 7) day`,
    [branchId],
  );
  const room = await pool.query<{ id: string }>(
    "insert into app.rooms (branch_id, name) values ($1, $2) returning id",
    [branchId, `Plan room ${randomUUID()}`],
  );
  const users = await pool.query<{ id: string; role: string }>(
    `insert into app.users (email, role, email_verified_at) values
       ($1, 'manager', now()), ($2, 'teacher', now()),
       ($3, 'client', now()), ($4, 'client', now())
     returning id, role::text`,
    [
      `plan-manager-${randomUUID()}@example.test`,
      `plan-teacher-${randomUUID()}@example.test`,
      `plan-client-a-${randomUUID()}@example.test`,
      `plan-client-b-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((user) => user.role === "manager")!.id;
  const teacherUserId = users.rows.find((user) => user.role === "teacher")!.id;
  const clientUserIds = users.rows
    .filter((user) => user.role === "client")
    .map((user) => user.id);
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `insert into app.profiles (user_id, first_name, last_name) values
       ($1, 'Plan', 'Teacher'), ($2, 'Plan', 'Student A'),
       ($3, 'Plan', 'Student B'), ($4, 'Мария', 'Управляющая')
     returning id, user_id`,
    [teacherUserId, ...clientUserIds, managerId],
  );
  const teacherProfileId = profiles.rows.find(
    (profile) => profile.user_id === teacherUserId,
  )!.id;
  const teacher = await pool.query<{ id: string }>(
    "insert into app.teachers (profile_id) values ($1) returning id",
    [teacherProfileId],
  );
  const teacherId = teacher.rows[0]!.id;
  await pool.query(
    `insert into app.teacher_branches (teacher_id, branch_id, active_from, active_until)
     values ($1, $2, '2020-01-01', '2100-12-31')`,
    [teacherId, branchId],
  );
  await pool.query(
    `insert into app.teacher_availability_rules (
       teacher_id, kind, available, timezone_name, weekday,
       local_start, local_end, valid_from, valid_until
     ) select $1, 'recurring', true, 'Europe/Moscow', day,
       '08:00', '22:00', '2020-01-01', '2100-12-31'
       from generate_series(1, 7) day`,
    [teacherId],
  );
  const students = await pool.query<{ id: string }>(
    `insert into app.students (profile_id, branch_id)
     select id, $1 from app.profiles where id = any($2::uuid[]) order by id returning id`,
    [
      branchId,
      profiles.rows
        .filter((profile) => clientUserIds.includes(profile.user_id))
        .map((profile) => profile.id),
    ],
  );
  const studentIds = students.rows.map((student) => student.id);
  const subscriptions = await pool.query<{ id: string; student_id: string }>(
    `insert into app.subscriptions (student_id, lessons_total, lessons_used, status)
     select id, 500, 0, 'active' from app.students where id = any($1::uuid[])
     order by id returning id, student_id`,
    [studentIds],
  );
  const group = await pool.query<{ id: string }>(
    "insert into app.groups (branch_id, name) values ($1, $2) returning id",
    [branchId, `Plan group ${randomUUID()}`],
  );
  await pool.query(
    "insert into app.group_students (group_id, student_id) select $1, unnest($2::uuid[])",
    [group.rows[0]!.id, studentIds],
  );
  const byStudent = new Map(
    subscriptions.rows.map((item) => [item.student_id, item.id]),
  );
  return {
    branchId,
    roomId: room.rows[0]!.id,
    teacherId,
    managerId,
    teacherUserId,
    clientUserIds,
    profileIds: profiles.rows.map((profile) => profile.id),
    studentIds,
    subscriptionIds: studentIds.map((studentId) => byStudent.get(studentId)!),
    groupId: group.rows[0]!.id,
    today: dates.rows[0]!.today,
    until60: dates.rows[0]!.until60,
    until400: dates.rows[0]!.until400,
    effectiveFrom: dates.rows[0]!.effective_from,
  };
}

async function cleanup(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
  additional?: Awaited<ReturnType<typeof createAdditionalPlanResource>>,
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query(
      "delete from app.idempotency_records where actor_key = $1",
      [`user:${fixture.managerId}`],
    );
    await client.query(
      `delete from app.platform_outbox_events where aggregate_type = 'schedule:plan'
       and aggregate_id in (select id::text from app.schedule_plans where created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      "delete from app.audit_events where actor_user_id = $1",
      [fixture.managerId],
    );
    await client.query(
      `delete from app.aggregate_versions where aggregate_type = 'schedule:plan'
       and aggregate_id in (select id::text from app.schedule_plans where created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_reservations where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_teacher_compensation_facts where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_client_charge_facts where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_settlement_plan_revisions where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_settlement_plans where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_transitions where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_snapshot_participants where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lesson_snapshots where lesson_id in (
         select lesson.id from app.lessons lesson join app.schedule_series series
           on series.id = lesson.series_id join app.schedule_plans plan on plan.id = series.plan_id
         where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      `delete from app.lessons where series_id in (
         select series.id from app.schedule_series series join app.schedule_plans plan
           on plan.id = series.plan_id where plan.created_by = $1)`,
      [fixture.managerId],
    );
    await client.query(
      "delete from app.schedule_series where plan_id in (select id from app.schedule_plans where created_by = $1)",
      [fixture.managerId],
    );
    await client.query(
      "delete from app.schedule_plan_participants where plan_id in (select id from app.schedule_plans where created_by = $1)",
      [fixture.managerId],
    );
    await client.query("delete from app.schedule_plans where created_by = $1", [
      fixture.managerId,
    ]);
    await client.query("delete from app.group_students where group_id = $1", [
      fixture.groupId,
    ]);
    await client.query("delete from app.groups where id = $1", [
      fixture.groupId,
    ]);
    await client.query(
      "delete from app.subscriptions where id = any($1::uuid[])",
      [fixture.subscriptionIds],
    );
    await client.query("delete from app.students where id = any($1::uuid[])", [
      fixture.studentIds,
    ]);
    const teacherIds = [
      fixture.teacherId,
      ...(additional == null ? [] : [additional.teacherId]),
    ];
    const roomIds = [
      fixture.roomId,
      ...(additional == null ? [] : [additional.roomId]),
    ];
    await client.query(
      "delete from app.teacher_availability_rules where teacher_id = any($1::uuid[])",
      [teacherIds],
    );
    await client.query(
      "delete from app.teacher_branches where teacher_id = any($1::uuid[])",
      [teacherIds],
    );
    await client.query("delete from app.teachers where id = any($1::uuid[])", [
      teacherIds,
    ]);
    await client.query("delete from app.rooms where id = any($1::uuid[])", [
      roomIds,
    ]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      [
        ...fixture.profileIds,
        ...(additional == null ? [] : [additional.profileId]),
      ],
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      [
        fixture.managerId,
        fixture.teacherUserId,
        ...fixture.clientUserIds,
        ...(additional == null ? [] : [additional.userId]),
      ],
    ]);
    await client.query("delete from app.branch_hours where branch_id = $1", [
      fixture.branchId,
    ]);
    await client.query("delete from app.branches where id = $1", [
      fixture.branchId,
    ]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
