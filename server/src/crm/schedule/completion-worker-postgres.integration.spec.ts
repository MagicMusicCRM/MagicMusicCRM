import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { LessonSettlementRepository } from "../commerce/lesson-settlement.repository";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import {
  computeCompletionBackoffSeconds,
  LessonCompletionWorkerRepository,
} from "./completion-worker.repository";
import { LessonCompletionService } from "./lesson-completion.service";
import { LessonCompletionWorker } from "./lesson-completion.worker";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Lesson completion tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Durable Lesson completion worker (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let repository: LessonCompletionWorkerRepository;
  let completion: LessonCompletionService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await pool.query(`
      do $$
      begin
        if not exists (
          select 1 from pg_roles where rolname = 'magiccrm_app'
        ) then
          create role magiccrm_app;
        end if;
      end $$
    `);
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    repository = new LessonCompletionWorkerRepository(database);
    const settlement = new LessonSettlementService(
      database,
      new LessonSettlementRepository(),
    );
    const reservations = new SubscriptionReservationService(
      database,
      {
        emitCrmChanged: jest.fn(),
        emitFinanceChanged: jest.fn(),
      } as unknown as RealtimeBus,
    );
    completion = new LessonCompletionService(
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      repository,
      new LessonLifecycleRepository(database),
      settlement,
      reservations,
    );
  });

  afterAll(async () => {
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("lets two workers create one terminal state, fact pair, audit and outbox within 60 seconds", async () => {
    const fixture = await createFixture(pool, database, "valid");
    try {
      const left = new LessonCompletionWorker(repository, completion);
      const right = new LessonCompletionWorker(repository, completion);
      const runs = await Promise.all([
        left.runOnce({ workerId: "completion-left", limit: 1 }),
        right.runOnce({ workerId: "completion-right", limit: 1 }),
      ]);
      expect(runs.reduce((sum, run) => sum + run.claimed, 0)).toBe(1);
      expect(runs.reduce((sum, run) => sum + run.completed, 0)).toBe(1);

      const evidence = await loadEvidence(pool, fixture.lessonId);
      expect(evidence.lesson).toMatchObject({
        lifecycle_state: "successfully_completed",
        status: "completed",
      });
      expect(Number(evidence.lesson.version)).toBe(2);
      expect(Number(evidence.lesson.completion_latency_seconds)).toBeLessThanOrEqual(
        60,
      );
      expect(evidence.counts).toEqual({
        transitions: 1,
        client_facts: 1,
        teacher_facts: 1,
        audits: 1,
        outbox: 1,
        idempotency: 1,
      });
      expect(evidence.work).toMatchObject({
        state: "completed",
        attempts: 1,
        terminal_state: "successfully_completed",
      });
      expect(evidence.work.claimed_by).toBeNull();
      expect(evidence.transition.worker_id).toMatch(
        /^completion-(left|right)$/,
      );
      expect(evidence.transition.client_financial_fact_id).toBe(
        evidence.work.client_financial_fact_id,
      );
      expect(evidence.transition.teacher_financial_fact_id).toBe(
        evidence.work.teacher_financial_fact_id,
      );

      const replay = await left.runOnce({
        workerId: "completion-after-terminal",
        limit: 1,
      });
      expect(replay).toMatchObject({ claimed: 0, completed: 0 });
      expect((await loadEvidence(pool, fixture.lessonId)).counts).toEqual(
        evidence.counts,
      );
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("survives kill-after-commit without losing or duplicating committed work", async () => {
    const fixture = await createFixture(pool, database, "valid");
    try {
      const claimed = await repository.claimDue("worker-killed-after-commit", {
        limit: 1,
        leaseSeconds: 1,
        maxAttempts: 5,
      });
      expect(claimed).toHaveLength(1);

      const committed = await completion.complete(claimed[0]!);
      expect(committed.replayed).toBe(false);
      // Simulate process death here: no in-memory acknowledgement follows the
      // committed transaction. A fresh worker starts against PostgreSQL only.
      const restarted = new LessonCompletionWorker(repository, completion);
      const afterRestart = await restarted.runOnce({
        workerId: "worker-after-restart",
        leaseSeconds: 1,
      });
      expect(afterRestart).toMatchObject({ claimed: 0, completed: 0 });

      const evidence = await loadEvidence(pool, fixture.lessonId);
      expect(evidence.counts).toEqual({
        transitions: 1,
        client_facts: 1,
        teacher_facts: 1,
        audits: 1,
        outbox: 1,
        idempotency: 1,
      });
      expect(evidence.work).toMatchObject({
        state: "completed",
        attempts: 1,
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("reclaims an expired lease after a worker dies before commit", async () => {
    const fixture = await createFixture(pool, database, "valid");
    try {
      const abandoned = await repository.claimDue("worker-before-crash", {
        limit: 1,
        leaseSeconds: 1,
        maxAttempts: 5,
      });
      expect(abandoned).toHaveLength(1);
      await pool.query(
        `
          update app.lesson_completion_work
          set claimed_at = now() - interval '2 seconds'
          where lesson_id = $1
        `,
        [fixture.lessonId],
      );

      const reclaimed = await repository.claimDue("worker-after-crash", {
        limit: 1,
        leaseSeconds: 1,
        maxAttempts: 5,
      });
      expect(reclaimed).toHaveLength(1);
      expect(reclaimed[0]).toMatchObject({
        lessonId: fixture.lessonId,
        workerId: "worker-after-crash",
        attempts: 2,
      });
      await completion.complete(reclaimed[0]!);

      const evidence = await loadEvidence(pool, fixture.lessonId);
      expect(evidence.work).toMatchObject({
        state: "completed",
        attempts: 2,
      });
      expect(evidence.counts).toEqual({
        transitions: 1,
        client_facts: 1,
        teacher_facts: 1,
        audits: 1,
        outbox: 1,
        idempotency: 1,
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("retries with bounded backoff and leaves poison work visible", async () => {
    const fixture = await createFixture(pool, database, "legacy-incomplete");
    try {
      const worker = new LessonCompletionWorker(repository, completion);
      const first = await worker.runOnce({
        workerId: "completion-poison",
        maxAttempts: 2,
        backoffBaseSeconds: 1,
        backoffCapSeconds: 2,
      });
      expect(first).toMatchObject({
        claimed: 1,
        completed: 0,
        retry: 1,
        poison: 0,
      });
      await pool.query(
        `
          update app.lesson_completion_work
          set available_at = now()
          where lesson_id = $1 and state = 'retry'
        `,
        [fixture.lessonId],
      );
      const second = await worker.runOnce({
        workerId: "completion-poison",
        maxAttempts: 2,
        backoffBaseSeconds: 1,
        backoffCapSeconds: 2,
      });
      expect(second).toMatchObject({
        claimed: 1,
        completed: 0,
        retry: 0,
        poison: 1,
      });

      const work = await pool.query<{
        state: string;
        attempts: number;
        last_error: string;
        claimed_by: string | null;
      }>(
        `
          select state, attempts, last_error, claimed_by
          from app.lesson_completion_work
          where lesson_id = $1
        `,
        [fixture.lessonId],
      );
      expect(work.rows[0]).toEqual({
        state: "poison",
        attempts: 2,
        last_error: "ConflictException",
        claimed_by: null,
      });
      const metrics = await worker.metrics();
      expect(metrics.poison).toBeGreaterThanOrEqual(1);
      expect(metrics.due).toBeGreaterThanOrEqual(1);
      await expect(worker.health()).resolves.toMatchObject({
        status: "degraded",
        metrics: { poison: expect.any(Number) },
      });
      expect(computeCompletionBackoffSeconds(1, 5, 20)).toBe(5);
      expect(computeCompletionBackoffSeconds(2, 5, 20)).toBe(10);
      expect(computeCompletionBackoffSeconds(8, 5, 20)).toBe(20);

      const counts = await loadEvidence(pool, fixture.lessonId);
      expect(counts.lesson.lifecycle_state).toBe("scheduled");
      expect(counts.counts).toEqual({
        transitions: 0,
        client_facts: 0,
        teacher_facts: 0,
        audits: 0,
        outbox: 0,
        idempotency: 0,
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });
});

async function createFixture(
  pool: Pool,
  database: DatabaseService,
  snapshotState: "valid" | "legacy-incomplete",
) {
  const branch = await pool.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'Europe/Moscow')
      returning id
    `,
    [`Completion ${randomUUID()}`],
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
      `completion-manager-${randomUUID()}@example.test`,
      `completion-teacher-${randomUUID()}@example.test`,
      `completion-client-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find(
    (row) => row.role === "teacher",
  )!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values
        ($1, 'Completion', 'Teacher'),
        ($2, 'Completion', 'Student')
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
  const lesson = await pool.query<{ id: string }>(
    `
      insert into app.lessons (
        student_id,
        teacher_id,
        branch_id,
        scheduled_at,
        duration_minutes,
        status,
        created_by
      )
      values (
        $1,
        $2,
        $3,
        now() - interval '60 minutes 5 seconds',
        60,
        'scheduled',
        $4
      )
      returning id
    `,
    [studentId, teacherId, branchId, managerId],
  );
  const lessonId = lesson.rows[0]!.id;
  const lifecycle = new LessonLifecycleRepository(database);
  if (snapshotState === "valid") {
    await database.transaction((client) =>
      lifecycle.createSnapshot(client, {
        lessonId,
        clientType: "student",
        clientId: studentId,
        completionType: "standard.success",
        clientChargeType: "personal_account",
        clientChargeValue: 800,
        teacherCompensationType: "hourly",
        teacherCompensationValue: 900,
        trial: false,
      }),
    );
  } else {
    await pool.query(
      `
        insert into app.lesson_snapshots (
          lesson_id,
          client_type,
          client_id,
          completion_type,
          client_charge_type,
          client_charge_value,
          teacher_compensation_type,
          teacher_compensation_value,
          trial,
          validation_state,
          origin,
          duration_minutes
        )
        values (
          $1,
          'student',
          $2,
          'legacy.scheduled',
          'none',
          0,
          'none',
          0,
          false,
          'legacy_incomplete',
          'legacy_backfill',
          60
        )
      `,
      [lessonId, studentId],
    );
  }
  return {
    lessonId,
    branchId,
    teacherId,
    studentId,
    userIds: [managerId, teacherUserId, clientUserId],
    profileIds: profiles.rows.map((row) => row.id),
  };
}

async function loadEvidence(pool: Pool, lessonId: string) {
  const lesson = await pool.query<{
    lifecycle_state: string;
    status: string;
    version: number | string;
    completion_latency_seconds: number | string;
  }>(
    `
      select
        lifecycle_state,
        status,
        version,
        extract(epoch from (
          updated_at
          - (scheduled_at + make_interval(mins => duration_minutes))
        )) as completion_latency_seconds
      from app.lessons
      where id = $1
    `,
    [lessonId],
  );
  const counts = await pool.query<{
    transitions: number;
    client_facts: number;
    teacher_facts: number;
    audits: number;
    outbox: number;
    idempotency: number;
  }>(
    `
      select
        (
          select count(*)::int
          from app.lesson_transitions
          where lesson_id = $1
        ) as transitions,
        (
          select count(*)::int
          from app.lesson_client_charge_facts
          where lesson_id = $1
        ) as client_facts,
        (
          select count(*)::int
          from app.lesson_teacher_compensation_facts
          where lesson_id = $1
        ) as teacher_facts,
        (
          select count(*)::int
          from app.audit_events
          where action = 'crm.lesson_completed'
            and entity_id = $1::text
        ) as audits,
        (
          select count(*)::int
          from app.platform_outbox_events
          where aggregate_type = 'schedule:lesson'
            and aggregate_id = $1::text
            and event_type = 'schedule.lesson.changed'
        ) as outbox,
        (
          select count(*)::int
          from app.idempotency_records
          where actor_key = 'worker:lesson-completion'
            and operation = 'schedule.lesson.complete'
            and idempotency_key = 'lesson-completion:' || $1::text
        ) as idempotency
    `,
    [lessonId],
  );
  const work = await pool.query<{
    state: string;
    attempts: number;
    claimed_by: string | null;
    terminal_state: string | null;
    client_financial_fact_id: string | null;
    teacher_financial_fact_id: string | null;
  }>(
    `
      select
        state,
        attempts,
        claimed_by,
        terminal_state,
        client_financial_fact_id,
        teacher_financial_fact_id
      from app.lesson_completion_work
      where lesson_id = $1
    `,
    [lessonId],
  );
  const transition = await pool.query<{
    worker_id: string | null;
    client_financial_fact_id: string | null;
    teacher_financial_fact_id: string | null;
  }>(
    `
      select
        worker_id,
        client_financial_fact_id,
        teacher_financial_fact_id
      from app.lesson_transitions
      where lesson_id = $1
    `,
    [lessonId],
  );
  return {
    lesson: lesson.rows[0]!,
    counts: counts.rows[0]!,
    work: work.rows[0]!,
    transition: transition.rows[0]!,
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
      `
        delete from app.idempotency_records
        where actor_key = 'worker:lesson-completion'
          and operation = 'schedule.lesson.complete'
          and idempotency_key = 'lesson-completion:' || $1::text
      `,
      [fixture.lessonId],
    );
    await client.query(
      `
        delete from app.platform_outbox_events
        where aggregate_type = 'schedule:lesson' and aggregate_id = $1::text
      `,
      [fixture.lessonId],
    );
    await client.query(
      `
        delete from app.audit_events
        where action = 'crm.lesson_completed' and entity_id = $1::text
      `,
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_completion_work where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_transitions where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_teacher_compensation_facts where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_client_charge_facts where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_snapshots where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      `
        delete from app.aggregate_versions
        where aggregate_type = 'schedule:lesson' and aggregate_id = $1::text
      `,
      [fixture.lessonId],
    );
    await client.query("delete from app.lessons where id = $1", [
      fixture.lessonId,
    ]);
    await client.query("delete from app.students where id = $1", [
      fixture.studentId,
    ]);
    await client.query("delete from app.teachers where id = $1", [
      fixture.teacherId,
    ]);
    await client.query(
      "delete from app.profiles where id = any($1::uuid[])",
      [fixture.profileIds],
    );
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
