import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import {
  computeCompletionBackoffSeconds,
  LessonCompletionWorkerRepository,
} from "./completion-worker.repository";
import { LessonCompletionService } from "./lesson-completion.service";
import { LessonCompletionWorker } from "./lesson-completion.worker";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonSettlementRepository } from "../commerce/lesson-settlement.repository";
import { LessonSettlementService } from "../commerce/lesson-settlement.service";
import { SubscriptionReservationService } from "../commerce/subscription-reservation.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { SubscriptionPreviewTokenService } from "../commerce/subscription-preview-token.service";
import { LessonSettlementCorrectionService } from "./lesson-settlement-correction.service";
import { CrmPolicy } from "../crm.policy";

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
  let settlement: LessonSettlementService;
  let correction: LessonSettlementCorrectionService;

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
    settlement = new LessonSettlementService(
      database,
      new LessonSettlementRepository(),
    );
    const reservations = new SubscriptionReservationService(database, {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    } as unknown as RealtimeBus);
    completion = new LessonCompletionService(
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      repository,
      settlement,
      reservations,
      new LessonLifecycleRepository(database),
    );
    correction = new LessonSettlementCorrectionService(
      database,
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new CrmPolicy(),
      settlement,
      new SubscriptionPreviewTokenService({
        get: (key: string) => key === "COMMERCE_PREVIEW_SECRET"
          ? "completion-correction-preview-secret-32-bytes"
          : "",
      } as unknown as ConfigService),
      reservations,
    );
  });

  afterAll(async () => {
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("does not claim legacy lessons without an explicit settlement plan", async () => {
    const fixture = await createFixture(pool, database, settlement, "valid");
    try {
      const client = await pool.connect();
      try {
        await client.query("begin");
        await client.query("set local session_replication_role = replica");
        await client.query(
          "delete from app.lesson_settlement_plan_revisions where lesson_id = $1",
          [fixture.lessonId],
        );
        await client.query(
          "delete from app.lesson_settlement_plans where lesson_id = $1",
          [fixture.lessonId],
        );
        await client.query("commit");
      } catch (error) {
        await client.query("rollback");
        throw error;
      } finally {
        client.release();
      }

      await expect(repository.claimDue("legacy-safe", {
        limit: 1,
        leaseSeconds: 60,
        maxAttempts: 5,
      })).resolves.toHaveLength(0);
      await expect(repository.metrics()).resolves.toMatchObject({ due: 0 });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("lets two workers queue one pending settlement without finance facts within 60 seconds", async () => {
    const fixture = await createFixture(pool, database, settlement, "valid");
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
      expect(evidence.work.client_financial_fact_id).not.toBeNull();
      expect(evidence.work.teacher_financial_fact_id).not.toBeNull();
      expect(evidence.transition).toMatchObject({
        worker_id: "completion-left",
        client_financial_fact_id: evidence.work.client_financial_fact_id,
        teacher_financial_fact_id: evidence.work.teacher_financial_fact_id,
      });

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
    const fixture = await createFixture(pool, database, settlement, "valid");
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
    const fixture = await createFixture(pool, database, settlement, "valid");
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
    const fixture = await createFixture(pool, database, settlement, "valid");
    try {
      const failingCompletion = {
        complete: async () => {
          const error = new Error("injected completion failure");
          error.name = "ConflictException";
          throw error;
        },
        markReviewRequired: completion.markReviewRequired.bind(completion),
      } as unknown as LessonCompletionService;
      const worker = new LessonCompletionWorker(repository, failingCompletion);
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
      expect(metrics.due).toBe(0);
      await expect(worker.health()).resolves.toMatchObject({
        status: "degraded",
        metrics: { poison: expect.any(Number) },
      });
      expect(computeCompletionBackoffSeconds(1, 5, 20)).toBe(5);
      expect(computeCompletionBackoffSeconds(2, 5, 20)).toBe(10);
      expect(computeCompletionBackoffSeconds(8, 5, 20)).toBe(20);

      const counts = await loadEvidence(pool, fixture.lessonId);
      expect(counts.lesson.lifecycle_state).toBe("settlement_pending");
      expect(counts.counts).toEqual({
        transitions: 0,
        client_facts: 0,
        teacher_facts: 0,
        audits: 1,
        outbox: 1,
        idempotency: 1,
      });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });

  it("corrects a completed settlement append-only and keeps one effective result", async () => {
    const fixture = await createFixture(pool, database, settlement, "valid");
    const actor = { userId: fixture.managerId, role: "manager" as const };
    try {
      const worker = new LessonCompletionWorker(repository, completion);
      await expect(worker.runOnce({ workerId: "completion-before-correction" }))
        .resolves.toMatchObject({ completed: 1 });
      const original = await pool.query<{
        client_id: string;
        client_amount_minor: string;
        teacher_id: string;
        teacher_amount_minor: string;
      }>(
        `select client.id as client_id,
           client.amount_minor::text as client_amount_minor,
           teacher.id as teacher_id,
           teacher.amount_minor::text as teacher_amount_minor
         from app.lesson_client_charge_facts_effective client
         join app.lesson_teacher_compensation_facts_effective teacher
           on teacher.lesson_id = client.lesson_id
         where client.lesson_id = $1`,
        [fixture.lessonId],
      );
      const dto = {
        expectedVersion: 2,
        financialDecision: {
          settlementTypeKey: "free_lesson",
          teacherCompensationRuleKey: "none",
        },
        reasonText: "Сотрудник исправил ошибочный расчёт после проверки",
      };
      const preview = await correction.preview(actor, fixture.lessonId, dto);
      expect(preview).toMatchObject({
        canConfirm: true,
        financialPreview: {
          clientFacts: [{ amountMinor: "0", units: "0.00" }],
          teacherFact: { amountMinor: "0" },
        },
      });
      await pool.query(`
        create or replace function app.test_reject_correction_teacher_fact()
        returns trigger language plpgsql as $$
        begin
          if new.correction_id is not null then
            raise exception 'injected correction write failure';
          end if;
          return new;
        end $$;
        drop trigger if exists test_reject_correction_teacher_fact
          on app.lesson_teacher_compensation_facts;
        create trigger test_reject_correction_teacher_fact
        before insert on app.lesson_teacher_compensation_facts
        for each row execute function app.test_reject_correction_teacher_fact();
      `);
      try {
        await expect(correction.commit(
          actor,
          fixture.lessonId,
          { ...dto, previewToken: preview.previewToken, confirm: true },
          {
            idempotencyKey: `settlement-correction-fault-${randomUUID()}`,
            requestId: `settlement-correction-fault-${randomUUID()}`,
          },
        )).rejects.toThrow("injected correction write failure");
      } finally {
        await pool.query(`
          drop trigger if exists test_reject_correction_teacher_fact
            on app.lesson_teacher_compensation_facts;
          drop function if exists app.test_reject_correction_teacher_fact();
        `);
      }
      const afterFault = await pool.query<{
        corrections: number;
        client_facts: number;
        teacher_facts: number;
        version: string;
      }>(
        `select
           (select count(*)::int from app.lesson_settlement_corrections
             where lesson_id = $1) as corrections,
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = $1) as client_facts,
           (select count(*)::int from app.lesson_teacher_compensation_facts
             where lesson_id = $1) as teacher_facts,
           (select version::text from app.lessons where id = $1) as version`,
        [fixture.lessonId],
      );
      expect(afterFault.rows[0]).toEqual({
        corrections: 0,
        client_facts: 1,
        teacher_facts: 1,
        version: "2",
      });
      const leftMetadata = {
        idempotencyKey: `settlement-correction-left-${randomUUID()}`,
        requestId: `settlement-correction-left-${randomUUID()}`,
      };
      const rightMetadata = {
        idempotencyKey: `settlement-correction-right-${randomUUID()}`,
        requestId: `settlement-correction-right-${randomUUID()}`,
      };
      const attempts = await Promise.allSettled([
        correction.commit(
          actor,
          fixture.lessonId,
          { ...dto, previewToken: preview.previewToken, confirm: true },
          leftMetadata,
        ),
        correction.commit(
          actor,
          fixture.lessonId,
          { ...dto, previewToken: preview.previewToken, confirm: true },
          rightMetadata,
        ),
      ]);
      const fulfilled = attempts.filter((item) => item.status === "fulfilled");
      const rejected = attempts.filter(
        (item): item is PromiseRejectedResult => item.status === "rejected",
      );
      if (fulfilled.length !== 1) throw rejected[0]?.reason;
      expect(rejected).toHaveLength(1);
      const winningMetadata = attempts[0]!.status === "fulfilled"
        ? leftMetadata
        : rightMetadata;
      await expect(correction.commit(
        actor,
        fixture.lessonId,
        { ...dto, previewToken: preview.previewToken, confirm: true },
        winningMetadata,
      )).resolves.toMatchObject({ version: 3, replayed: true });

      const facts = await pool.query<{
        raw_client: number;
        raw_teacher: number;
        effective_client: number;
        effective_teacher: number;
        effective_client_amount: string;
        effective_teacher_amount: string;
        corrections: number;
        lesson_version: string;
      }>(
        `select
           (select count(*)::int from app.lesson_client_charge_facts
             where lesson_id = $1) as raw_client,
           (select count(*)::int from app.lesson_teacher_compensation_facts
             where lesson_id = $1) as raw_teacher,
           (select count(*)::int from app.lesson_client_charge_facts_effective
             where lesson_id = $1) as effective_client,
           (select count(*)::int from app.lesson_teacher_compensation_facts_effective
             where lesson_id = $1) as effective_teacher,
           (select amount_minor::text from app.lesson_client_charge_facts_effective
             where lesson_id = $1) as effective_client_amount,
           (select amount_minor::text from app.lesson_teacher_compensation_facts_effective
             where lesson_id = $1) as effective_teacher_amount,
           (select count(*)::int from app.lesson_settlement_corrections
             where lesson_id = $1) as corrections,
           (select version::text from app.lessons where id = $1) as lesson_version`,
        [fixture.lessonId],
      );
      expect(facts.rows[0]).toEqual({
        raw_client: 2,
        raw_teacher: 2,
        effective_client: 1,
        effective_teacher: 1,
        effective_client_amount: "0",
        effective_teacher_amount: "0",
        corrections: 1,
        lesson_version: "3",
      });
      const unchanged = await pool.query<{
        client_amount_minor: string;
        teacher_amount_minor: string;
      }>(
        `select client.amount_minor::text as client_amount_minor,
           teacher.amount_minor::text as teacher_amount_minor
         from app.lesson_client_charge_facts client
         cross join app.lesson_teacher_compensation_facts teacher
         where client.id = $1 and teacher.id = $2`,
        [original.rows[0]!.client_id, original.rows[0]!.teacher_id],
      );
      expect(unchanged.rows[0]).toEqual({
        client_amount_minor: original.rows[0]!.client_amount_minor,
        teacher_amount_minor: original.rows[0]!.teacher_amount_minor,
      });
      const history = await correction.history(actor, fixture.lessonId);
      expect(history.items).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            kind: "correction",
            reason: dto.reasonText,
            effective: true,
          }),
          expect.objectContaining({ kind: "planned", effective: false }),
        ]),
      );
      await expect(
        correction.history(
          { userId: fixture.teacherUserId, role: "teacher" },
          fixture.lessonId,
        ),
      ).rejects.toMatchObject({ status: 403 });
    } finally {
      await cleanupFixture(pool, fixture);
    }
  });
});

async function createFixture(
  pool: Pool,
  database: DatabaseService,
  settlement: LessonSettlementService,
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
    await database.transaction((client) =>
      settlement.assignPlan(client, {
        lessonId,
        branchId,
        decision: {
          settlementTypeKey: "lesson",
          teacherCompensationRuleKey: "standard",
        },
        selectedBy: managerId,
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
    managerId,
    teacherUserId,
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
          where action in (
            'crm.lesson_settlement_completed',
            'crm.lesson_settlement_review_required'
          )
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
            and operation in (
              'schedule.lesson.complete-settlement',
              'schedule.lesson.settlement-review-required'
            )
            and idempotency_key in (
              'lesson-settlement-complete:' || $1::text,
              'lesson-settlement-review:' || $1::text
            )
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
    transition: transition.rows[0] ?? null,
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
        where (
          actor_key = 'worker:lesson-completion'
          and operation in (
            'schedule.lesson.complete-settlement',
            'schedule.lesson.settlement-review-required'
          )
          and idempotency_key in (
            'lesson-settlement-complete:' || $1::text,
            'lesson-settlement-review:' || $1::text
          )
        ) or (
          actor_key = any($2::text[])
          and operation = 'schedule.lesson.settlement-correction'
        )
      `,
      [fixture.lessonId, fixture.userIds.map((id) => `user:${id}`)],
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
        where action in (
          'crm.lesson_settlement_completed',
          'crm.lesson_settlement_review_required',
          'crm.lesson_settlement_corrected'
        )
          and entity_id = $1::text
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
      "delete from app.lesson_settlement_corrections where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_reservations where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_settlement_plan_revisions where lesson_id = $1",
      [fixture.lessonId],
    );
    await client.query(
      "delete from app.lesson_settlement_plans where lesson_id = $1",
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
