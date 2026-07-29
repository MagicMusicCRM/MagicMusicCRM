import { HttpException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { ClientReferenceService } from "../clients/client-reference.service";
import { CrmPolicy } from "../crm.policy";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonSeriesCommandService } from "./lesson-series-command.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { RealtimeBus } from "../../realtime/realtime-bus";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Lesson series tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Atomic LessonSeries (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let commands: LessonSeriesCommandService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: testDatabaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const availability = new AvailabilityRepository(database);
    commands = new LessonSeriesCommandService(
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new CrmPolicy(),
      new ClientReferenceService(database),
      new LessonRequiredFieldValidator(),
      new ScheduleConstraintEngine(
        new ConstraintEngineRepository(database, availability),
      ),
      new LessonLifecycleRepository(database),
      new SubscriptionReservationService(
        database,
        {
          emitCrmChanged: jest.fn(),
          emitFinanceChanged: jest.fn(),
        } as unknown as RealtimeBus,
      ),
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("rolls back an Nth conflict and creates a valid DST-aware series fully", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const failedKey = `series-failed-${randomUUID()}`;
    const validMetadata = {
      idempotencyKey: `series-valid-${randomUUID()}`,
      requestId: `request-valid-${randomUUID()}`,
    };
    let createdSeriesId: string | undefined;
    const base = {
      clientRef: { type: "student" as const, id: fixture.studentId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      weekday: 1,
      durationMinutes: 60,
      validFrom: "2026-10-26",
      validUntil: "2026-11-09",
      isTrial: false,
      completionType: "standard.success",
      clientChargeType: "none" as const,
      clientChargeValue: 0,
      teacherCompensationType: "fixed" as const,
      teacherCompensationValue: 700,
    };

    try {
      const failure = await errorResponse(() =>
        commands.create(
          actor,
          { ...base, beginTime: "09:00" },
          {
            idempotencyKey: failedKey,
            requestId: `request-failed-${randomUUID()}`,
          },
        ),
      );
      expect(failure).toMatchObject({
        code: "LESSON_SERIES_CONSTRAINT_VIOLATIONS",
        failedIndex: 1,
        occurrence: {
          index: 1,
          localDate: "2026-11-02",
          startAt: "2026-11-02T14:00:00.000Z",
          endAt: "2026-11-02T15:00:00.000Z",
          timezone: "America/New_York",
        },
      });
      expect(failure.violations).toEqual([
        {
          code: "TEACHER_OVERLAP",
          resource: { type: "teacher", id: fixture.teacherId },
          conflictingLessonIds: [fixture.conflictingLessonId],
          ruleIds: [],
        },
        {
          code: "CLIENT_OVERLAP",
          resource: { type: "client", id: fixture.studentId },
          conflictingLessonIds: [fixture.conflictingLessonId],
          ruleIds: [],
        },
        {
          code: "ROOM_OVERLAP",
          resource: { type: "room", id: fixture.roomId },
          conflictingLessonIds: [fixture.conflictingLessonId],
          ruleIds: [],
        },
      ]);
      const afterFailure = await pool.query<{ series: string; lessons: string }>(
        `
          select
            (
              select count(*)::text
              from app.schedule_series
              where created_by = $1 and client_id = $2
            ) as series,
            (
              select count(*)::text
              from app.lessons
              where created_by = $1 and series_id is not null
            ) as lessons
        `,
        [fixture.managerId, fixture.studentId],
      );
      expect(afterFailure.rows[0]).toEqual({ series: "0", lessons: "0" });

      const created = await commands.create(
        actor,
        { ...base, beginTime: "11:00" },
        validMetadata,
      );
      createdSeriesId = created.id;
      expect(created).toMatchObject({
        lessonsCreated: 3,
        version: 1,
        replayed: false,
      });
      expect(created.lessonIds).toHaveLength(3);

      const persisted = await pool.query<{
        timezone_name: string;
        occurrence_count: number | string;
        version: number | string;
        starts_at: Date[];
        snapshots: number | string;
      }>(
        `
          select
            series.timezone_name,
            series.occurrence_count,
            series.version,
            array_agg(lesson.scheduled_at order by lesson.series_date) as starts_at,
            count(snapshot.lesson_id)::int as snapshots
          from app.schedule_series series
          join app.lessons lesson on lesson.series_id = series.id
          left join app.lesson_snapshots snapshot on snapshot.lesson_id = lesson.id
          where series.id = $1
          group by series.id
        `,
        [created.id],
      );
      expect(persisted.rows[0]).toMatchObject({
        timezone_name: "America/New_York",
        snapshots: 3,
      });
      expect(Number(persisted.rows[0]!.occurrence_count)).toBe(3);
      expect(Number(persisted.rows[0]!.version)).toBe(1);
      expect(
        persisted.rows[0]!.starts_at.map((value) =>
          new Date(value).toISOString(),
        ),
      ).toEqual([
        "2026-10-26T15:00:00.000Z",
        "2026-11-02T16:00:00.000Z",
        "2026-11-09T16:00:00.000Z",
      ]);

      const replay = await commands.create(
        actor,
        { ...base, beginTime: "11:00" },
        validMetadata,
      );
      expect(replay).toMatchObject({
        id: created.id,
        lessonIds: created.lessonIds,
        lessonsCreated: 3,
        version: 1,
        replayed: true,
      });
      const count = await pool.query<{ count: string }>(
        "select count(*)::text as count from app.lessons where series_id = $1",
        [created.id],
      );
      expect(count.rows[0]!.count).toBe("3");
    } finally {
      await cleanupFixture(pool, fixture, createdSeriesId);
    }
  });

  it("keeps randomized weekly series on the requested wall clock across DST", async () => {
    const random = seededRandom(0x44_04_01);
    const zones = [
      "America/New_York",
      "Europe/Berlin",
      "Europe/Moscow",
      "Australia/Sydney",
    ];
    for (let sample = 0; sample < 64; sample += 1) {
      const timezone = zones[Math.floor(random() * zones.length)]!;
      const month = 1 + Math.floor(random() * 11);
      const day = 1 + Math.floor(random() * 20);
      const weekday = 1 + Math.floor(random() * 7);
      const hour = 8 + Math.floor(random() * 10);
      const minute = Math.floor(random() * 4) * 15;
      const validFrom = `2026-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
      const beginTime = `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
      const occurrences = await pool.query<{
        local_date: string;
        local_time: string;
        starts_at: Date;
      }>(
        `
          select
            generated.local_date::text as local_date,
            to_char(
              timezone($1, generated.starts_at),
              'HH24:MI'
            ) as local_time,
            generated.starts_at
          from (
            select
              day::date as local_date,
              (day::date + $5::time) at time zone $1 as starts_at
            from generate_series(
              $2::date,
              $2::date + interval '70 days',
              interval '1 day'
            ) day
            where extract(isodow from day) = $3::int
          ) generated
          order by generated.local_date
          limit $4
        `,
        [timezone, validFrom, weekday, 10, beginTime],
      );
      expect(occurrences.rows).toHaveLength(10);
      expect(
        occurrences.rows.every((row) => row.local_time === beginTime),
      ).toBe(true);
      for (let index = 1; index < occurrences.rows.length; index += 1) {
        const previous = new Date(
          occurrences.rows[index - 1]!.starts_at,
        ).getTime();
        const current = new Date(occurrences.rows[index]!.starts_at).getTime();
        const elapsedHours = (current - previous) / 3_600_000;
        expect([167, 168, 169]).toContain(elapsedHours);
      }
    }
  });
});

function seededRandom(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (Math.imul(state, 1_103_515_245) + 12_345) >>> 0;
    return state / 0x1_0000_0000;
  };
}

async function errorResponse(work: () => Promise<unknown>) {
  try {
    await work();
    throw new Error("Expected series constraint violation.");
  } catch (error) {
    if (!(error instanceof HttpException)) throw error;
    return error.getResponse() as {
      code?: string;
      failedIndex?: number;
      occurrence?: unknown;
      violations?: unknown[];
    };
  }
}

async function createFixture(pool: Pool) {
  const branch = await pool.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'America/New_York')
      returning id
    `,
    [`Atomic series ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  await pool.query(
    `
      insert into app.branch_hours (branch_id, weekday, open_local, close_local)
      values ($1, 1, '08:00', '18:00')
    `,
    [branchId],
  );
  const room = await pool.query<{ id: string }>(
    `
      insert into app.rooms (branch_id, name)
      values ($1, $2)
      returning id
    `,
    [branchId, `Atomic room ${randomUUID()}`],
  );
  const users = await pool.query<{ id: string; role: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'manager', now()),
        ($2, 'teacher', now()),
        ($3, 'client', now())
      returning id, role::text as role
    `,
    [
      `atomic-manager-${randomUUID()}@example.test`,
      `atomic-teacher-${randomUUID()}@example.test`,
      `atomic-client-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values
        ($1, 'Atomic', 'Teacher'),
        ($2, 'Atomic', 'Student')
      returning id, user_id
    `,
    [teacherUserId, clientUserId],
  );
  const teacherProfileId = profiles.rows.find(
    (row) => row.user_id === teacherUserId,
  )!.id;
  const studentProfileId = profiles.rows.find(
    (row) => row.user_id === clientUserId,
  )!.id;
  const teacher = await pool.query<{ id: string }>(
    "insert into app.teachers (profile_id) values ($1) returning id",
    [teacherProfileId],
  );
  const teacherId = teacher.rows[0]!.id;
  await pool.query(
    `
      insert into app.teacher_branches (
        teacher_id, branch_id, active_from, active_until
      )
      values ($1, $2, '2026-01-01', '2026-12-31')
    `,
    [teacherId, branchId],
  );
  await pool.query(
    `
      insert into app.teacher_availability_rules (
        teacher_id, kind, available, timezone_name, weekday,
        local_start, local_end, valid_from, valid_until
      )
      values (
        $1, 'recurring', true, 'America/New_York', 1,
        '08:00', '18:00', '2026-01-01', '2026-12-31'
      )
    `,
    [teacherId],
  );
  const student = await pool.query<{ id: string }>(
    `
      insert into app.students (profile_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [studentProfileId, branchId],
  );
  const conflictingLesson = await pool.query<{ id: string }>(
    `
      insert into app.lessons (
        student_id, teacher_id, branch_id, room_id,
        scheduled_at, duration_minutes, created_by
      )
      values ($1, $2, $3, $4, '2026-11-02T14:00:00.000Z', 60, $5)
      returning id
    `,
    [
      student.rows[0]!.id,
      teacherId,
      branchId,
      room.rows[0]!.id,
      managerId,
    ],
  );
  return {
    branchId,
    roomId: room.rows[0]!.id,
    teacherId,
    studentId: student.rows[0]!.id,
    managerId,
    teacherUserId,
    clientUserId,
    profileIds: profiles.rows.map((row) => row.id),
    conflictingLessonId: conflictingLesson.rows[0]!.id,
  };
}

async function cleanupFixture(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
  seriesId?: string,
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
      "delete from app.platform_outbox_events where aggregate_type = 'schedule:lesson-series' and aggregate_id = $1",
      [seriesId ?? null],
    );
    await client.query(
      "delete from app.audit_events where actor_user_id = $1",
      [fixture.managerId],
    );
    await client.query(
      "delete from app.aggregate_versions where aggregate_type in ('schedule:lesson-series', 'schedule:lesson') and (aggregate_id = $1 or aggregate_id = $2)",
      [seriesId ?? null, fixture.conflictingLessonId],
    );
    if (seriesId) {
      await client.query(
        "delete from app.lesson_snapshots where lesson_id in (select id from app.lessons where series_id = $1)",
        [seriesId],
      );
      await client.query("delete from app.lessons where series_id = $1", [
        seriesId,
      ]);
      await client.query("delete from app.schedule_series where id = $1", [
        seriesId,
      ]);
    }
    await client.query("delete from app.lessons where id = $1", [
      fixture.conflictingLessonId,
    ]);
    await client.query("delete from app.students where id = $1", [
      fixture.studentId,
    ]);
    await client.query(
      "delete from app.teacher_availability_rules where teacher_id = $1",
      [fixture.teacherId],
    );
    await client.query(
      "delete from app.teacher_branches where teacher_id = $1",
      [fixture.teacherId],
    );
    await client.query("delete from app.teachers where id = $1", [
      fixture.teacherId,
    ]);
    await client.query("delete from app.rooms where id = $1", [
      fixture.roomId,
    ]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query(
      "delete from app.users where id = any($1::uuid[])",
      [[fixture.managerId, fixture.teacherUserId, fixture.clientUserId]],
    );
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
