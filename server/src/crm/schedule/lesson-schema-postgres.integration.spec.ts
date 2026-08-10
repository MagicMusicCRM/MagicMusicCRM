import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Lesson lifecycle schema tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

async function expectConstraint(
  client: PoolClient,
  work: () => Promise<unknown>,
  expectedCode: "23505" | "23514",
) {
  const savepoint = `sp_${randomUUID().replace(/-/g, "")}`;
  await client.query(`savepoint ${savepoint}`);
  try {
    await work();
    throw new Error(`Expected PostgreSQL constraint ${expectedCode}.`);
  } catch (error) {
    expect((error as { code?: string }).code).toBe(expectedCode);
    await client.query(`rollback to savepoint ${savepoint}`);
  } finally {
    await client.query(`release savepoint ${savepoint}`);
  }
}

describe("Lesson lifecycle schema (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let repository: LessonLifecycleRepository;

  beforeAll(async () => {
    pool = new Pool({ connectionString: testDatabaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    repository = new LessonLifecycleRepository(database);
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("rolls the empty v7 schedule/note schema down and up", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const migrationRoot = resolve(process.cwd(), "db/migrations");
      await client.query(
        readFileSync(
          resolve(
            migrationRoot,
            "0116_v7_canonical_commerce_projections.down.sql",
          ),
          "utf8",
        ),
      );
      await client.query(`
        drop view if exists app.lesson_teacher_compensation_facts_effective;
        drop view if exists app.lesson_client_charge_facts_effective;
      `);
      await client.query(
        readFileSync(
          resolve(migrationRoot, "0104_v7_schedule_plans_notes.down.sql"),
          "utf8",
        ),
      );
      expect(
        (await client.query("select to_regclass('app.schedule_plans') as value"))
          .rows[0]?.value,
      ).toBeNull();
      await client.query(
        readFileSync(
          resolve(migrationRoot, "0104_v7_schedule_plans_notes.up.sql"),
          "utf8",
        ),
      );
      await client.query(`
        create view app.lesson_client_charge_facts_effective as
        select fact.*
        from app.lesson_client_charge_facts fact
        where not exists (
          select 1 from app.lesson_client_charge_facts newer
          where newer.supersedes_fact_id = fact.id
        );
        create view app.lesson_teacher_compensation_facts_effective as
        select fact.*
        from app.lesson_teacher_compensation_facts fact
        where not exists (
          select 1 from app.lesson_teacher_compensation_facts newer
          where newer.supersedes_fact_id = fact.id
        );
      `);
      await client.query(
        readFileSync(
          resolve(
            migrationRoot,
            "0116_v7_canonical_commerce_projections.up.sql",
          ),
          "utf8",
        ),
      );
      expect(
        (await client.query("select to_regclass('app.schedule_plans') as value"))
          .rows[0]?.value,
      ).toBe("app.schedule_plans");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("rejects mixed plan, settlement snapshot and note lineage shapes", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const branch = await client.query<{ id: string }>(
        "insert into app.branches (name) values ($1) returning id",
        [`V7 foundation ${randomUUID()}`],
      );
      const users = await client.query<{ id: string; role: string }>(
        `
          insert into app.users (email, role, email_verified_at)
          values ($1, 'manager', now()), ($2, 'client', now())
          returning id, role::text as role
        `,
        [
          `v7-foundation-manager-${randomUUID()}@example.test`,
          `v7-foundation-client-${randomUUID()}@example.test`,
        ],
      );
      const managerId = users.rows.find((row) => row.role === "manager")!.id;
      const clientId = users.rows.find((row) => row.role === "client")!.id;
      const profile = await client.query<{ id: string }>(
        `
          insert into app.profiles (user_id, first_name, last_name)
          values ($1, 'V7', 'Foundation') returning id
        `,
        [clientId],
      );
      const student = await client.query<{ id: string }>(
        `
          insert into app.students (profile_id, branch_id)
          values ($1, $2) returning id
        `,
        [profile.rows[0]!.id, branch.rows[0]!.id],
      );
      const studentId = student.rows[0]!.id;
      const subscription = await client.query<{ id: string }>(
        `
          insert into app.subscriptions (
            student_id, lessons_total, lessons_used, status
          ) values ($1, 12, 0, 'active') returning id
        `,
        [studentId],
      );
      await client.query(
        `
          insert into app.schedule_plans (
            kind, title, student_id, subscription_id, active_from, created_by
          ) values ('individual', 'Фортепиано', $1, $2, current_date, $3)
        `,
        [studentId, subscription.rows[0]!.id, managerId],
      );
      await expectConstraint(
        client,
        () =>
          client.query(
            `
              insert into app.schedule_plans (
                kind, title, active_from, created_by
              ) values ('individual', 'Без клиента', current_date, $1)
            `,
            [managerId],
          ),
        "23514",
      );
      await expectConstraint(
        client,
        () =>
          client.query(
            "insert into app.client_internal_notes (body, updated_by) values ('x', $1)",
            [managerId],
          ),
        "23514",
      );
      const lesson = await client.query<{ id: string }>(
        `
          insert into app.lessons (
            student_id, branch_id, scheduled_at, created_by
          ) values ($1, $2, now() + interval '1 day', $3) returning id
        `,
        [studentId, branch.rows[0]!.id, managerId],
      );
      await expectConstraint(
        client,
        () =>
          client.query(
            `
              insert into app.lesson_client_charge_facts (
                lesson_id, client_type, client_id, charge_type,
                snapshot_value, amount_minor, units, currency_code,
                settlement_type_key
              ) values ($1, 'student', $2, 'none', 0, 0, 0, 'RUB', 'free')
            `,
            [lesson.rows[0]!.id, studentId],
          ),
        "23514",
      );
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("maps legacy state and enforces immutable facts, terminal transitions and unique reservations", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const branch = await client.query<{ id: string }>(
        "insert into app.branches (name) values ($1) returning id",
        [`Lifecycle ${randomUUID()}`],
      );
      const users = await client.query<{ id: string; role: string }>(
        `
          insert into app.users (email, role, email_verified_at)
          values
            ($1, 'manager', now()),
            ($2, 'client', now())
          returning id, role::text as role
        `,
        [
          `lifecycle-manager-${randomUUID()}@example.test`,
          `lifecycle-client-${randomUUID()}@example.test`,
        ],
      );
      const managerId = users.rows.find((row) => row.role === "manager")!.id;
      const clientUserId = users.rows.find((row) => row.role === "client")!.id;
      const profile = await client.query<{ id: string }>(
        `
          insert into app.profiles (user_id, first_name, last_name)
          values ($1, 'Схема', 'Урока')
          returning id
        `,
        [clientUserId],
      );
      const student = await client.query<{ id: string }>(
        `
          insert into app.students (profile_id, branch_id)
          values ($1, $2)
          returning id
        `,
        [profile.rows[0]!.id, branch.rows[0]!.id],
      );
      const studentId = student.rows[0]!.id;
      const subscription = await client.query<{ id: string }>(
        `
          insert into app.subscriptions (
            student_id, lessons_total, lessons_used, status
          )
          values ($1, 10, 0, 'active')
          returning id
        `,
        [studentId],
      );
      const subscriptionId = subscription.rows[0]!.id;

      const legacy = await client.query<{
        id: string;
        status: string;
        lifecycle_state: string;
        version: number | string;
      }>(
        `
          insert into app.lessons (
            student_id, branch_id, scheduled_at, status, created_by
          )
          values ($1, $2, now() - interval '2 hours', 'completed', $3)
          returning id, status, lifecycle_state, version
        `,
        [studentId, branch.rows[0]!.id, managerId],
      );
      expect(legacy.rows[0]).toMatchObject({
        status: "completed",
        lifecycle_state: "successfully_completed",
      });
      expect(Number(legacy.rows[0]!.version)).toBe(1);
      await expectConstraint(
        client,
        () =>
          client.query(
            "update app.lessons set status = 'scheduled' where id = $1",
            [legacy.rows[0]!.id],
          ),
        "23514",
      );

      const scheduled = await client.query<{ id: string }>(
        `
          insert into app.lessons (
            student_id, branch_id, scheduled_at, status, created_by
          )
          values ($1, $2, now() + interval '1 day', 'scheduled', $3)
          returning id
        `,
        [studentId, branch.rows[0]!.id, managerId],
      );
      const lessonId = scheduled.rows[0]!.id;
      await repository.createSnapshot(client, {
        lessonId,
        clientType: "student",
        clientId: studentId,
        completionType: "standard.success",
        clientChargeType: "subscription",
        clientChargeValue: 1,
        teacherCompensationType: "fixed",
        teacherCompensationValue: 700,
        subscriptionId,
        trial: false,
      });
      const snapshot = await client.query<{
        origin: string;
        validation_state: string;
      }>(
        `
          select origin, validation_state
          from app.lesson_snapshots
          where lesson_id = $1
        `,
        [lessonId],
      );
      expect(snapshot.rows[0]).toEqual({
        origin: "runtime",
        validation_state: "valid",
      });
      await expectConstraint(
        client,
        () =>
          client.query(
            `
              update app.lesson_snapshots
              set client_charge_value = 2
              where lesson_id = $1
            `,
            [lessonId],
          ),
        "23514",
      );
      await expectConstraint(
        client,
        () =>
          repository.createSnapshot(client, {
            lessonId,
            clientType: "student",
            clientId: studentId,
            completionType: "standard.success",
            clientChargeType: "subscription",
            clientChargeValue: 1,
            teacherCompensationType: "fixed",
            teacherCompensationValue: 700,
            subscriptionId,
            trial: false,
          }),
        "23505",
      );

      const reservation = await repository.createReservation(client, {
        lessonId,
        subscriptionId,
        units: 1,
      });
      const reservationId = String(reservation.rows[0]!.id);
      await expectConstraint(
        client,
        () =>
          repository.createReservation(client, {
            lessonId,
            subscriptionId,
            units: 1,
          }),
        "23505",
      );
      const released = await client.query<{
        state: string;
        version: number | string;
        terminal_at: Date | string | null;
      }>(
        `
          update app.lesson_reservations
          set state = 'released'
          where id = $1
          returning state, version, terminal_at
        `,
        [reservationId],
      );
      expect({
        state: released.rows[0]!.state,
        version: Number(released.rows[0]!.version),
        hasTerminalAt: released.rows[0]!.terminal_at !== null,
      }).toEqual({
        state: "released",
        version: 2,
        hasTerminalAt: true,
      });
      await expectConstraint(
        client,
        () =>
          client.query(
            `
              update app.lesson_reservations
              set state = 'reserved'
              where id = $1
            `,
            [reservationId],
          ),
        "23514",
      );

      const clientFactId = randomUUID();
      const teacherFactId = randomUUID();
      await repository.appendTransition(client, {
        lessonId,
        toState: "cancelled",
        reasonCode: "test.cancel",
        actorUserId: managerId,
        financialDecision: { client: "preserve", teacher: "none" },
        clientFinancialFactId: clientFactId,
        teacherFinancialFactId: teacherFactId,
      });
      const terminal = await client.query<{
        status: string;
        lifecycle_state: string;
        version: number | string;
      }>(
        `
          update app.lessons
          set lifecycle_state = 'cancelled'
          where id = $1 and version = 1
          returning status, lifecycle_state, version
        `,
        [lessonId],
      );
      expect(terminal.rows[0]).toMatchObject({
        status: "cancelled",
        lifecycle_state: "cancelled",
      });
      expect(Number(terminal.rows[0]!.version)).toBe(2);
      await expectConstraint(
        client,
        () =>
          repository.appendTransition(client, {
            lessonId,
            toState: "successfully_completed",
            reasonCode: "test.duplicate-terminal",
          }),
        "23505",
      );
      await expectConstraint(
        client,
        () =>
          client.query(
            `
              update app.lessons
              set lifecycle_state = 'scheduled'
              where id = $1
            `,
            [lessonId],
          ),
        "23514",
      );

      const otherLesson = await client.query<{ id: string }>(
        `
          insert into app.lessons (
            student_id, branch_id, scheduled_at, created_by
          )
          values ($1, $2, now() + interval '2 days', $3)
          returning id
        `,
        [studentId, branch.rows[0]!.id, managerId],
      );
      await expectConstraint(
        client,
        () =>
          repository.appendTransition(client, {
            lessonId: otherLesson.rows[0]!.id,
            toState: "cancelled",
            reasonCode: "test.duplicate-financial-fact",
            clientFinancialFactId: clientFactId,
          }),
        "23505",
      );

      const predecessor = await client.query<{ id: string }>(
        `
          insert into app.lessons (
            student_id, branch_id, scheduled_at, created_by
          )
          values ($1, $2, now() + interval '3 days', $3)
          returning id
        `,
        [studentId, branch.rows[0]!.id, managerId],
      );
      await client.query(
        `
          insert into app.lessons (
            student_id, branch_id, scheduled_at, created_by, predecessor_id
          )
          values ($1, $2, now() + interval '4 days', $3, $4)
        `,
        [studentId, branch.rows[0]!.id, managerId, predecessor.rows[0]!.id],
      );
      await expectConstraint(
        client,
        () =>
          client.query(
            `
              insert into app.lessons (
                student_id, branch_id, scheduled_at, created_by, predecessor_id
              )
              values ($1, $2, now() + interval '5 days', $3, $4)
            `,
            [
              studentId,
              branch.rows[0]!.id,
              managerId,
              predecessor.rows[0]!.id,
            ],
          ),
        "23505",
      );

      const aggregate = await client.query<{ version: number | string }>(
        `
          select version
          from app.aggregate_versions
          where aggregate_type = 'schedule:lesson' and aggregate_id = $1
        `,
        [lessonId],
      );
      expect(Number(aggregate.rows[0]!.version)).toBe(2);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
