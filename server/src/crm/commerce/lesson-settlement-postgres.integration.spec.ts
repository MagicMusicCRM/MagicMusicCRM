import { ConflictException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { LessonLifecycleRepository } from "../schedule/lesson-lifecycle.repository";
import { LessonSettlementRepository } from "./lesson-settlement.repository";
import { LessonSettlementService } from "./lesson-settlement.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Lesson settlement tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Idempotent Lesson settlement (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let service: LessonSettlementService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    service = new LessonSettlementService(
      database,
      new LessonSettlementRepository(),
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("creates one stable pair under concurrency and supports fixed/hourly/none", async () => {
    const fixture = await createFixture(pool, database);
    try {
      const parallel = await Promise.all(
        Array.from({ length: 12 }, () =>
          service.settleStandalone(fixture.fixedLessonId),
        ),
      );
      for (const result of parallel) expect(result).toEqual(parallel[0]);
      expect(parallel[0]).toMatchObject({
        lessonId: fixture.fixedLessonId,
        clientFact: {
          clientType: "student",
          clientId: fixture.studentId,
          chargeType: "personal_account",
          snapshotValue: "1234.56",
          subscriptionId: null,
          amountMinor: "123456",
          units: "0.00",
          currencyCode: "RUB",
        },
        teacherFact: {
          teacherId: fixture.teacherId,
          compensationType: "fixed",
          snapshotRate: "700.00",
          rateMinor: "70000",
          durationMinutes: 60,
          amountMinor: "70000",
          currencyCode: "RUB",
        },
      });
      const counts = await pool.query<{
        client_count: number;
        teacher_count: number;
      }>(
        `
          select
            (
              select count(*)::int
              from app.lesson_client_charge_facts
              where lesson_id = $1
            ) as client_count,
            (
              select count(*)::int
              from app.lesson_teacher_compensation_facts
              where lesson_id = $1
            ) as teacher_count
        `,
        [fixture.fixedLessonId],
      );
      expect(counts.rows[0]).toEqual({
        client_count: 1,
        teacher_count: 1,
      });

      const hourly = await service.settleStandalone(fixture.hourlyLessonId);
      expect(hourly.teacherFact).toMatchObject({
        compensationType: "hourly",
        snapshotRate: "1000.01",
        rateMinor: "100001",
        durationMinutes: 45,
        amountMinor: "75001",
      });
      expect(hourly.clientFact).toMatchObject({
        chargeType: "none",
        amountMinor: "0",
        units: "0.00",
      });

      const none = await service.settleStandalone(fixture.noneLessonId);
      expect(none.teacherFact).toMatchObject({
        compensationType: "none",
        snapshotRate: "0.00",
        rateMinor: "0",
        durationMinutes: 90,
        amountMinor: "0",
      });
      expect(none.clientFact).toMatchObject({
        chargeType: "none",
        snapshotValue: "0.00",
        amountMinor: "0",
        units: "0.00",
      });

      await expect(
        pool.query(
          `
            update app.lesson_teacher_compensation_facts
            set amount_minor = amount_minor + 1
            where lesson_id = $1
          `,
          [fixture.fixedLessonId],
        ),
      ).rejects.toMatchObject({ code: "23514" });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("rejects non-completed Lessons without creating a partial fact", async () => {
    const fixture = await createFixture(pool, database, true);
    try {
      await expect(
        service.settleStandalone(fixture.fixedLessonId),
      ).rejects.toBeInstanceOf(ConflictException);
      const counts = await pool.query<{ count: number }>(
        `
          select (
            select count(*) from app.lesson_client_charge_facts
            where lesson_id = $1
          ) + (
            select count(*) from app.lesson_teacher_compensation_facts
            where lesson_id = $1
          ) as count
        `,
        [fixture.fixedLessonId],
      );
      expect(Number(counts.rows[0]?.count)).toBe(0);
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });
});

async function createFixture(
  pool: Pool,
  database: DatabaseService,
  scheduled = false,
) {
  const branch = await pool.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'Europe/Moscow')
      returning id
    `,
    [`Settlement ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
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
      `settlement-manager-${randomUUID()}@example.test`,
      `settlement-teacher-${randomUUID()}@example.test`,
      `settlement-client-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values
        ($1, 'Settlement', 'Teacher'),
        ($2, 'Settlement', 'Student')
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
  const student = await pool.query<{ id: string }>(
    `
      insert into app.students (profile_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [studentProfileId, branchId],
  );
  const studentId = student.rows[0]!.id;
  const lessons = await pool.query<{ id: string; duration_minutes: number }>(
    `
      insert into app.lessons (
        student_id, teacher_id, branch_id, scheduled_at, duration_minutes,
        status, created_by
      )
      values
        ($1, $2, $3, '2026-07-29T07:00:00Z', 60, $4, $5),
        ($1, $2, $3, '2026-07-29T09:00:00Z', 45, 'completed', $5),
        ($1, $2, $3, '2026-07-29T11:00:00Z', 90, 'completed', $5)
      returning id, duration_minutes
    `,
    [
      studentId,
      teacherId,
      branchId,
      scheduled ? "scheduled" : "completed",
      managerId,
    ],
  );
  const fixedLessonId = lessons.rows[0]!.id;
  const hourlyLessonId = lessons.rows[1]!.id;
  const noneLessonId = lessons.rows[2]!.id;
  const lifecycle = new LessonLifecycleRepository(database);
  await database.transaction(async (client) => {
    await lifecycle.createSnapshot(client, {
      lessonId: fixedLessonId,
      clientType: "student",
      clientId: studentId,
      completionType: "standard.success",
      clientChargeType: "personal_account",
      clientChargeValue: 1234.56,
      teacherCompensationType: "fixed",
      teacherCompensationValue: 700,
      trial: false,
    });
    await lifecycle.createSnapshot(client, {
      lessonId: hourlyLessonId,
      clientType: "student",
      clientId: studentId,
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 0,
      teacherCompensationType: "hourly",
      teacherCompensationValue: 1000.01,
      trial: false,
    });
    await lifecycle.createSnapshot(client, {
      lessonId: noneLessonId,
      clientType: "student",
      clientId: studentId,
      completionType: "standard.success",
      clientChargeType: "none",
      clientChargeValue: 250,
      teacherCompensationType: "none",
      teacherCompensationValue: 500,
      trial: false,
    });
  });

  // Settlement must use the immutable snapshot duration, not a later mutable
  // Lesson projection.
  await pool.query(
    "update app.lessons set duration_minutes = 120 where id = $1",
    [hourlyLessonId],
  );

  return {
    branchId,
    teacherId,
    studentId,
    managerId,
    userIds: [managerId, teacherUserId, clientUserId],
    profileIds: profiles.rows.map((row) => row.id),
    lessonIds: lessons.rows.map((row) => row.id),
    fixedLessonId,
    hourlyLessonId,
    noneLessonId,
  };
}

async function cleanupFixture(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query(
      "delete from app.lesson_teacher_compensation_facts where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_client_charge_facts where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_snapshots where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.aggregate_versions where aggregate_type = 'schedule:lesson' and aggregate_id = any($1::text[])",
      [fixture.lessonIds],
    );
    await client.query("delete from app.lessons where id = any($1::uuid[])", [
      fixture.lessonIds,
    ]);
    await client.query("delete from app.students where id = $1", [
      fixture.studentId,
    ]);
    await client.query("delete from app.teachers where id = $1", [
      fixture.teacherId,
    ]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
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
