import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { ClientReferenceService } from "../clients/client-reference.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { CrmPolicy } from "../crm.policy";
import { ScheduleService } from "../schedule.service";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { SchedulePlanRepository } from "./schedule-plan.repository";
import { SchedulePlanService } from "./schedule-plan.service";

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(new URL(databaseUrl).hostname)) {
  throw new Error("Schedule plan tests require local PostgreSQL.");
}

jest.setTimeout(90_000);

describe("Schedule plan aggregate (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let plans: SchedulePlanService;
  let schedule: ScheduleService;
  let reservations: SubscriptionReservationService;
  let lifecycle: LessonLifecycleRepository;

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
    schedule = new ScheduleService(
      database,
      {} as never,
      policy,
      {} as never,
      realtime,
      reservations,
    );
    const availability = new AvailabilityRepository(database);
    const series = new LessonSeriesCommandService(
      new PlatformIntegrityService(database, new PlatformIntegrityRepository()),
      policy,
      new ClientReferenceService(database),
      new LessonRequiredFieldValidator(),
      new ScheduleConstraintEngine(
        new ConstraintEngineRepository(database, availability),
      ),
      lifecycle,
      reservations,
    );
    plans = new SchedulePlanService(
      new PlatformIntegrityService(database, new PlatformIntegrityRepository()),
      policy,
      new SchedulePlanRepository(database),
      series,
      schedule,
      database,
      new SubscriptionPreviewTokenService({
        get: (key: string, fallback: string) =>
          key === "COMMERCE_PREVIEW_SECRET"
            ? "schedule-plan-test-preview-secret-0123456789abcdef"
            : fallback,
      } as unknown as ConfigService),
      lifecycle,
      reservations,
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("creates one open-ended individual plan with N series and idempotent unique lessons", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const key = `plan-individual-${randomUUID()}`;
    try {
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
        ],
      };
      const [created, replay] = await Promise.all([
        plans.create(actor, dto, { idempotencyKey: key, requestId: `request-${randomUUID()}` }),
        plans.create(actor, dto, { idempotencyKey: key, requestId: `request-${randomUUID()}` }),
      ]);
      expect(created.id).toBe(replay.id);
      expect([created.replayed, replay.replayed].sort()).toEqual([false, true]);
      expect(created.seriesIds).toHaveLength(2);
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
        series: "2",
        lessons: String(created.lessonIds.length),
        snapshots: String(created.lessonIds.length),
        reservations: String(created.lessonIds.length),
        duplicate_dates: "0",
      });
      const regenerated = await database.transaction(async (client) => {
        let count = 0;
        for (const seriesId of created.seriesIds) {
          count += await schedule.materializePlanSeries(client, seriesId);
        }
        return count;
      });
      expect(regenerated).toBe(0);
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("creates a group plan with immutable participants and one reservation per subscription", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const created = await plans.create(actor, {
        kind: "group",
        title: "Группа ансамбля",
        groupId: fixture.groupId,
        activeFrom: fixture.today,
        activeUntil: fixture.until400,
        participants: fixture.studentIds.map((studentId, index) => ({
          studentId,
          subscriptionId: fixture.subscriptionIds[index]!,
        })),
        rows: [row(fixture, 3, "14:00")],
      }, {
        idempotencyKey: `plan-group-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      });
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
          rows: [expect.objectContaining({
            teacherName: "Plan Teacher",
            roomName: expect.stringContaining("Plan room"),
            branchName: expect.stringContaining("Plan branch"),
          })],
        }),
      ]);
      const updated = await plans.update(actor, created.id, {
        expectedVersion: 1,
        effectiveFrom: fixture.effectiveFrom,
        rows: [{
          ...row(fixture, 3, "15:00"),
          seriesId: created.seriesIds[0],
        }],
      }, {
        idempotencyKey: `plan-group-edit-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      });
      expect(updated).toMatchObject({ version: 2, replayed: false });
      const assignments = await pool.query<{ historical: string; current: string }>(
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

  it("applies one concurrent effective edit and leaves earlier snapshots unchanged", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const created = await plans.create(actor, {
        kind: "individual",
        title: "Фортепиано",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: [row(fixture, 2, "10:00")],
      }, {
        idempotencyKey: `plan-edit-source-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      });
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
        rows: [{
          ...row(fixture, 2, "12:00"),
          seriesId: created.seriesIds[0],
        }],
      };
      const results = await Promise.allSettled([
        plans.update(actor, created.id, base, {
          idempotencyKey: `plan-edit-a-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        }),
        plans.update(actor, created.id, {
          ...base,
          rows: [{ ...base.rows[0], beginTime: "13:00" }],
        }, {
          idempotencyKey: `plan-edit-b-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        }),
      ]);
      expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
      expect(results.filter((result) => result.status === "rejected")).toHaveLength(1);
      const succeeded = results.find((result) => result.status === "fulfilled")!;
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
      const created = await plans.create(actor, {
        kind: "individual",
        title: "Завершаемое расписание",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: [row(fixture, 1, "10:00"), row(fixture, 4, "11:00")],
      }, {
        idempotencyKey: `plan-end-source-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      });
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
      const historical = before.rows.find((lesson) => lesson.series_date <= lastDate)!;
      const terminal = before.rows.find((lesson) => lesson.series_date > lastDate)!;
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
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("rejects a stale end preview and rolls the whole end mutation back on failure", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const created = await plans.create(actor, {
        kind: "individual",
        title: "Атомарное завершение",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: [row(fixture, 2, "10:00"), row(fixture, 5, "11:00")],
      }, {
        idempotencyKey: `plan-atomic-source-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      });
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
      await expect(plans.end(actor, created.id, {
        ...base,
        previewToken: stale.previewToken,
        confirm: true,
      }, {
        idempotencyKey: `plan-stale-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      })).rejects.toMatchObject({ response: { code: "SCHEDULE_PLAN_END_PREVIEW_STALE" } });

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
      const fault = jest.spyOn(lifecycle, "appendTransition").mockImplementation(
        (client, input) => {
          appendCount += 1;
          if (appendCount === 2) throw new Error("injected plan-end failure");
          return originalAppend(client, input);
        },
      );
      try {
        await expect(plans.end(actor, created.id, {
          ...base,
          previewToken: fresh.previewToken,
          confirm: true,
        }, {
          idempotencyKey: `plan-fault-${randomUUID()}`,
          requestId: `request-${randomUUID()}`,
        })).rejects.toThrow("injected plan-end failure");
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
      const created = await plans.create(actor, {
        kind: "individual",
        title: "Длинный трей",
        studentId: fixture.studentIds[0],
        subscriptionId: fixture.subscriptionIds[0],
        activeFrom: fixture.today,
        activeUntil: fixture.until60,
        rows: Array.from({ length: 7 }, (_, index) =>
          row(fixture, index + 1, "18:00")),
      }, {
        idempotencyKey: `plan-tray-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      });
      const ids: string[] = [];
      let page = await plans.tray(actor, created.id, { limit: 10 });
      for (let pageNumber = 0; pageNumber < 10; pageNumber += 1) {
        expect(page.items.length).toBeLessThanOrEqual(10);
        expect(page.items).toEqual([...page.items].sort((left, right) =>
          left.scheduledAt.localeCompare(right.scheduledAt) || left.id.localeCompare(right.id)));
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
      const clientTray = await plans.tray({
        userId: owner.rows[0]!.user_id,
        role: "client",
      }, created.id, { limit: 5 });
      expect(clientTray.items.length).toBeGreaterThan(0);
      const hidden = await plans.tray({
        userId: randomUUID(),
        role: "client",
      }, created.id, { limit: 5 });
      expect(hidden).toMatchObject({ items: [], hasPrevious: false, hasNext: false });

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
      expect(bounded.items.filter((item) => item.status === "active")).toHaveLength(1);
      expect(bounded.items.filter((item) => item.status === "ended")).toHaveLength(20);
    } finally {
      await cleanup(pool, fixture);
    }
  });
});

function row(
  fixture: Awaited<ReturnType<typeof createFixture>>,
  weekday: number,
  beginTime: string,
) {
  return {
    teacherId: fixture.teacherId,
    roomId: fixture.roomId,
    branchId: fixture.branchId,
    weekday,
    beginTime,
    durationMinutes: 60,
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
  }>(`select current_date::text as today,
      (current_date + 60)::text as until60,
      (current_date + 400)::text as until400,
      (current_date + 21)::text as effective_from`);
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
  const clientUserIds = users.rows.filter((user) => user.role === "client").map((user) => user.id);
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `insert into app.profiles (user_id, first_name, last_name) values
       ($1, 'Plan', 'Teacher'), ($2, 'Plan', 'Student A'), ($3, 'Plan', 'Student B')
     returning id, user_id`,
    [teacherUserId, ...clientUserIds],
  );
  const teacherProfileId = profiles.rows.find((profile) => profile.user_id === teacherUserId)!.id;
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
      profiles.rows.filter((profile) => clientUserIds.includes(profile.user_id)).map((profile) => profile.id),
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
  const byStudent = new Map(subscriptions.rows.map((item) => [item.student_id, item.id]));
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

async function cleanup(pool: Pool, fixture: Awaited<ReturnType<typeof createFixture>>) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query("delete from app.idempotency_records where actor_key = $1", [`user:${fixture.managerId}`]);
    await client.query(
      `delete from app.platform_outbox_events where aggregate_type = 'schedule:plan'
       and aggregate_id in (select id::text from app.schedule_plans where created_by = $1)`,
      [fixture.managerId],
    );
    await client.query("delete from app.audit_events where actor_user_id = $1", [fixture.managerId]);
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
    await client.query("delete from app.schedule_plans where created_by = $1", [fixture.managerId]);
    await client.query("delete from app.group_students where group_id = $1", [fixture.groupId]);
    await client.query("delete from app.groups where id = $1", [fixture.groupId]);
    await client.query("delete from app.subscriptions where id = any($1::uuid[])", [fixture.subscriptionIds]);
    await client.query("delete from app.students where id = any($1::uuid[])", [fixture.studentIds]);
    await client.query("delete from app.teacher_availability_rules where teacher_id = $1", [fixture.teacherId]);
    await client.query("delete from app.teacher_branches where teacher_id = $1", [fixture.teacherId]);
    await client.query("delete from app.teachers where id = $1", [fixture.teacherId]);
    await client.query("delete from app.rooms where id = $1", [fixture.roomId]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [fixture.profileIds]);
    await client.query("delete from app.users where id = any($1::uuid[])", [[
      fixture.managerId,
      fixture.teacherUserId,
      ...fixture.clientUserIds,
    ]]);
    await client.query("delete from app.branch_hours where branch_id = $1", [fixture.branchId]);
    await client.query("delete from app.branches where id = $1", [fixture.branchId]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
