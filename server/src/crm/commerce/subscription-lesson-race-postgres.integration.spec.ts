import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { LessonLifecycleRepository } from "../schedule/lesson-lifecycle.repository";
import { LessonSettlementRepository } from "./lesson-settlement.repository";
import { LessonSettlementService } from "./lesson-settlement.service";
import { SubscriptionLifecycleRepository } from "./subscription-lifecycle.repository";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Subscription/Lesson race tests require local PostgreSQL.");
}

jest.setTimeout(120_000);

describe("Subscription reservations and Lesson settlement races", () => {
  let pool: Pool;
  let database: DatabaseService;
  let reservations: SubscriptionReservationService;
  let settlement: LessonSettlementService;
  let lifecycle: SubscriptionLifecycleRepository;
  let realtime: {
    emitCrmChanged: jest.Mock;
    emitFinanceChanged: jest.Mock;
  };

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    realtime = {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    };
    reservations = new SubscriptionReservationService(
      database,
      realtime as unknown as RealtimeBus,
    );
    settlement = new LessonSettlementService(
      database,
      new LessonSettlementRepository(),
    );
    lifecycle = new SubscriptionLifecycleRepository(database);
  });

  afterAll(async () => {
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("serializes cancellation against completion and preserves future lessons", async () => {
    const fixture = await createFixture(pool, database, reservations, "cancel");
    try {
      await Promise.all([
        completeLesson(
          database,
          reservations,
          settlement,
          fixture.dueLessonId,
        ),
        cancelSubscription(database, lifecycle, fixture.oldSubscriptionId),
      ]);

      const evidence = await loadEvidence(
        pool,
        fixture,
        fixture.oldSubscriptionId,
      );
      expect(evidence.subscriptionStatus).toBe("cancelled");
      expect(evidence.lessonCount).toBe(2);
      expect(evidence.clientFacts).toHaveLength(1);
      expect(evidence.teacherFacts).toBe(1);
      expect(evidence.futureReservation).toMatchObject({
        state: "released",
        subscription_id: fixture.oldSubscriptionId,
      });
      expect(["consumed", "released"]).toContain(
        evidence.dueReservation.state,
      );
      if (evidence.dueReservation.state === "consumed") {
        expect(evidence.clientFacts[0]).toMatchObject({
          charge_type: "subscription",
          subscription_id: fixture.oldSubscriptionId,
        });
      } else {
        expect(evidence.clientFacts[0]).toMatchObject({
          charge_type: "none",
          subscription_id: null,
        });
      }
      expect(evidence.activeReservations).toBe(0);

      const started = Date.now();
      await reservations.publishPostCommit({
        studentId: fixture.studentId,
        subscriptionId: fixture.oldSubscriptionId,
      });
      expect(Date.now() - started).toBeLessThan(2_000);
      expect(realtime.emitCrmChanged).toHaveBeenCalledWith(
        expect.objectContaining({
          entity: "lesson",
          action: "updated",
        }),
      );
      expect(realtime.emitFinanceChanged).toHaveBeenCalledWith([
        fixture.clientUserId,
      ]);
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("settles against transferred coverage when replacement races completion", async () => {
    const fixture = await createFixture(pool, database, reservations, "replace");
    try {
      await Promise.all([
        completeLesson(
          database,
          reservations,
          settlement,
          fixture.dueLessonId,
        ),
        replaceSubscription(
          database,
          lifecycle,
          fixture.oldSubscriptionId,
          fixture.newSubscriptionId,
        ),
      ]);

      const evidence = await loadEvidence(
        pool,
        fixture,
        fixture.newSubscriptionId,
      );
      expect(evidence.subscriptionStatus).toBe("active");
      expect(evidence.oldSubscriptionStatus).toBe("replaced");
      expect(evidence.lessonCount).toBe(2);
      expect(evidence.clientFacts).toHaveLength(1);
      expect(evidence.teacherFacts).toBe(1);
      expect(evidence.dueReservation.state).toBe("consumed");
      expect(evidence.clientFacts[0]).toMatchObject({
        charge_type: "subscription",
        subscription_id: evidence.dueReservation.subscription_id,
      });
      expect(evidence.futureReservation).toMatchObject({
        state: "reserved",
        subscription_id: fixture.newSubscriptionId,
      });
      expect(evidence.activeReservations).toBe(1);
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });
});

async function completeLesson(
  database: DatabaseService,
  reservations: SubscriptionReservationService,
  settlement: LessonSettlementService,
  lessonId: string,
) {
  return database.transaction(async (client) => {
    await client.query(
      "select id from app.lessons where id = $1 for update",
      [lessonId],
    );
    await reservations.lockSettlementCoverage(client, lessonId);
    await client.query(
      `
        update app.lessons
        set lifecycle_state = 'successfully_completed',
            updated_at = now()
        where id = $1 and lifecycle_state = 'scheduled'
      `,
      [lessonId],
    );
    const result = await settlement.settle(client, lessonId);
    await reservations.terminalize(client, result);
    return result;
  });
}

async function cancelSubscription(
  database: DatabaseService,
  lifecycle: SubscriptionLifecycleRepository,
  subscriptionId: string,
) {
  return database.transaction(async (client) => {
    await lifecycle.lockIssuedSubscription(client, subscriptionId);
    await lifecycle.lockReservedRows(client, subscriptionId);
    const closed = await lifecycle.closeCancelledSubscription(client, {
      issuedSubscriptionId: subscriptionId,
      expectedVersion: 1,
      nextVersion: 2,
    });
    if (!closed) throw new Error("Cancellation lost its version.");
    return lifecycle.releaseCancellationReservations(client, subscriptionId);
  });
}

async function replaceSubscription(
  database: DatabaseService,
  lifecycle: SubscriptionLifecycleRepository,
  oldSubscriptionId: string,
  newSubscriptionId: string,
) {
  return database.transaction(async (client) => {
    await lifecycle.lockIssuedSubscription(client, oldSubscriptionId);
    await lifecycle.lockReservedRows(client, oldSubscriptionId);
    const rows = await client.query<{ id: string }>(
      `
        select id
        from app.lesson_reservations
        where subscription_id = $1 and state = 'reserved'
        order by id
      `,
      [oldSubscriptionId],
    );
    const closed = await lifecycle.closeReplacedSubscription(client, {
      issuedSubscriptionId: oldSubscriptionId,
      expectedVersion: 1,
      nextVersion: 2,
    });
    if (!closed) throw new Error("Replacement lost its version.");
    return lifecycle.applyReservationPlan(client, {
      oldIssuedSubscriptionId: oldSubscriptionId,
      newIssuedSubscriptionId: newSubscriptionId,
      transferReservationIds: rows.rows.map((row) => row.id),
      releaseReservationIds: [],
    });
  });
}

async function createFixture(
  pool: Pool,
  database: DatabaseService,
  reservations: SubscriptionReservationService,
  suffix: string,
) {
  const marker = `reservation-race-${suffix}-${randomUUID()}`;
  const client = await pool.connect();
  try {
    await client.query("begin");
    const branch = await client.query<{ id: string }>(
      `
        insert into app.branches (name, timezone_name)
        values ($1, 'Europe/Moscow')
        returning id
      `,
      [marker],
    );
    const users = await client.query<{ id: string; role: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values
          ($1, 'manager', now()),
          ($2, 'teacher', now()),
          ($3, 'client', now())
        returning id, role::text as role
      `,
      [
        `${marker}-manager@example.test`,
        `${marker}-teacher@example.test`,
        `${marker}-client@example.test`,
      ],
    );
    const managerId = users.rows.find((row) => row.role === "manager")!.id;
    const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
    const clientUserId = users.rows.find((row) => row.role === "client")!.id;
    const profiles = await client.query<{ id: string; user_id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name)
        values
          ($1, 'Race', 'Teacher'),
          ($2, 'Race', 'Client')
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
    const teacher = await client.query<{ id: string }>(
      "insert into app.teachers (profile_id) values ($1) returning id",
      [teacherProfileId],
    );
    const student = await client.query<{ id: string }>(
      `
        insert into app.students (profile_id, branch_id, status)
        values ($1, $2, 'active')
        returning id
      `,
      [studentProfileId, branch.rows[0]!.id],
    );
    const packageRow = await client.query<{ id: string }>(
      `
        insert into app.subscription_packages (
          name,
          lessons_total,
          base_price_minor,
          currency_code,
          validity_days,
          is_active,
          version
        )
        values ($1, 20, 800000, 'RUB', 90, true, 1)
        returning id
      `,
      [marker],
    );
    const subscriptions = await client.query<{ id: string }>(
      `
        insert into app.subscriptions (
          student_id,
          lessons_total,
          lessons_used,
          starts_at,
          expires_at,
          status,
          package_id,
          commercial_snapshot,
          snapshot_version,
          package_version,
          base_price_minor,
          currency_code,
          final_price_minor,
          version
        )
        values
          (
            $1, 20, 0, current_date, current_date + 90, 'active', $2,
            $3::jsonb, 1, 1, 800000, 'RUB', 800000, 1
          ),
          (
            $1, 20, 0, current_date, current_date + 90, 'active', $2,
            $4::jsonb, 1, 1, 800000, 'RUB', 800000, 1
          )
        returning id
      `,
      [
        student.rows[0]!.id,
        packageRow.rows[0]!.id,
        JSON.stringify({ snapshotVersion: 1, displayName: `${marker}-old` }),
        JSON.stringify({ snapshotVersion: 1, displayName: `${marker}-new` }),
      ],
    );
    const lessons = await client.query<{ id: string; kind: string }>(
      `
        insert into app.lessons (
          student_id,
          teacher_id,
          branch_id,
          scheduled_at,
          duration_minutes,
          status,
          created_by,
          notes
        )
        values
          (
            $1, $2, $3, now() - interval '61 minutes', 60,
            'scheduled', $4, 'race-due'
          ),
          (
            $1, $2, $3, now() + interval '2 days', 60,
            'scheduled', $4, 'race-future'
          )
        returning id, notes as kind
      `,
      [
        student.rows[0]!.id,
        teacher.rows[0]!.id,
        branch.rows[0]!.id,
        managerId,
      ],
    );
    const dueLessonId = lessons.rows.find(
      (row) => row.kind === "race-due",
    )!.id;
    const futureLessonId = lessons.rows.find(
      (row) => row.kind === "race-future",
    )!.id;
    const lessonLifecycle = new LessonLifecycleRepository(database);
    for (const lessonId of [dueLessonId, futureLessonId]) {
      await lessonLifecycle.createSnapshot(client, {
        lessonId,
        clientType: "student",
        clientId: student.rows[0]!.id,
        completionType: "standard.success",
        clientChargeType: "subscription",
        clientChargeValue: 1,
        teacherCompensationType: "fixed",
        teacherCompensationValue: 500,
        subscriptionId: subscriptions.rows[0]!.id,
        trial: false,
      });
      await reservations.allocate(client, {
        lessonId,
        clientType: "student",
        clientId: student.rows[0]!.id,
        chargeType: "subscription",
        subscriptionId: subscriptions.rows[0]!.id,
        units: 1,
      });
    }
    await client.query("commit");
    return {
      branchId: branch.rows[0]!.id,
      userIds: users.rows.map((row) => row.id),
      profileIds: profiles.rows.map((row) => row.id),
      clientUserId,
      teacherId: teacher.rows[0]!.id,
      studentId: student.rows[0]!.id,
      packageId: packageRow.rows[0]!.id,
      oldSubscriptionId: subscriptions.rows[0]!.id,
      newSubscriptionId: subscriptions.rows[1]!.id,
      dueLessonId,
      futureLessonId,
      lessonIds: [dueLessonId, futureLessonId],
      subscriptionIds: subscriptions.rows.map((row) => row.id),
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function loadEvidence(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
  subscriptionId: string,
) {
  const facts = await pool.query<{
    charge_type: string;
    subscription_id: string | null;
  }>(
    `
      select charge_type, subscription_id
      from app.lesson_client_charge_facts
      where lesson_id = $1
    `,
    [fixture.dueLessonId],
  );
  const teacherFacts = await pool.query<{ count: number }>(
    `
      select count(*)::int as count
      from app.lesson_teacher_compensation_facts
      where lesson_id = $1
    `,
    [fixture.dueLessonId],
  );
  const reservationsResult = await pool.query<{
    lesson_id: string;
    subscription_id: string;
    state: string;
  }>(
    `
      select lesson_id, subscription_id, state
      from app.lesson_reservations
      where lesson_id = any($1::uuid[])
      order by lesson_id
    `,
    [fixture.lessonIds],
  );
  const statuses = await pool.query<{ id: string; status: string }>(
    "select id, status from app.subscriptions where id = any($1::uuid[])",
    [fixture.subscriptionIds],
  );
  const lessonCount = await pool.query<{ count: number }>(
    "select count(*)::int as count from app.lessons where id = any($1::uuid[])",
    [fixture.lessonIds],
  );
  const activeReservations = reservationsResult.rows.filter(
    (row) => row.state === "reserved",
  ).length;
  return {
    subscriptionStatus:
      statuses.rows.find((row) => row.id === subscriptionId)?.status,
    oldSubscriptionStatus:
      statuses.rows.find((row) => row.id === fixture.oldSubscriptionId)
        ?.status,
    clientFacts: facts.rows,
    teacherFacts: teacherFacts.rows[0]!.count,
    dueReservation: reservationsResult.rows.find(
      (row) => row.lesson_id === fixture.dueLessonId,
    )!,
    futureReservation: reservationsResult.rows.find(
      (row) => row.lesson_id === fixture.futureLessonId,
    )!,
    lessonCount: lessonCount.rows[0]!.count,
    activeReservations,
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
      "delete from app.lesson_reservations where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_snapshots where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.aggregate_versions where aggregate_id = any($1::text[])",
      [[...fixture.lessonIds, ...fixture.subscriptionIds]],
    );
    await client.query(
      "delete from app.lessons where id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.subscriptions where id = any($1::uuid[])",
      [fixture.subscriptionIds],
    );
    await client.query("delete from app.subscription_packages where id = $1", [
      fixture.packageId,
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
