import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
import { LessonTransitionFinancialService } from "./lesson-transition-financial.service";
import { LessonTransitionService } from "./lesson-transition.service";

const url =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (!["127.0.0.1", "localhost", "[::1]"].includes(new URL(url).hostname)) {
  throw new Error("Reschedule tests require local PostgreSQL.");
}
jest.setTimeout(60_000);

describe("Atomic lesson reschedule/cancel (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let service: LessonTransitionService;
  let failingService: LessonTransitionService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: url });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => url,
    } as unknown as ConfigService);
    const repository = new ConstraintEngineRepository(
      database,
      new AvailabilityRepository(database),
    );
    const dependencies = [
      database,
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new CrmPolicy(),
      new LessonRequiredFieldValidator(),
      new ScheduleConstraintEngine(repository),
      new LessonLifecycleRepository(database),
    ] as const;
    service = new LessonTransitionService(
      ...dependencies,
      new LessonTransitionFinancialService(),
    );
    failingService = new LessonTransitionService(
      ...dependencies,
      {
        apply: async () => {
          throw new Error("injected commerce failure");
        },
      } as LessonTransitionFinancialService,
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("keeps source unchanged on conflict/failure and commits one linked transition", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const financialDecision = {
      chargeClient: false,
      compensateTeacher: true,
    };
    const dto = (scheduledAt: string) => ({
      expectedVersion: 1,
      reasonCode: "client.requested",
      reasonText: "Requested another time",
      financialDecision,
      successor: { scheduledAt },
    });
    const metadata = (label: string) => ({
      idempotencyKey: `${label}-${randomUUID()}`,
      requestId: `request-${label}-${randomUUID()}`,
    });
    try {
      const preview = await service.previewReschedule(
        actor,
        fixture.sourceId,
        dto("2026-07-27T09:00:00.000Z"),
      );
      expect(preview).toMatchObject({
        canConfirm: false,
        confirmRequired: true,
        violations: expect.arrayContaining([
          expect.objectContaining({ code: "TEACHER_OVERLAP" }),
          expect.objectContaining({ code: "CLIENT_OVERLAP" }),
          expect.objectContaining({ code: "ROOM_OVERLAP" }),
        ]),
      });
      await expect(
        service.reschedule(
          actor,
          fixture.sourceId,
          { ...dto("2026-07-27T09:00:00.000Z"), confirm: true as const },
          metadata("conflict"),
        ),
      ).rejects.toMatchObject({ status: 422 });
      await expect(
        failingService.reschedule(
          actor,
          fixture.sourceId,
          { ...dto("2026-07-27T11:00:00.000Z"), confirm: true as const },
          metadata("failure"),
        ),
      ).rejects.toThrow("injected commerce failure");
      await expectSourceUnchanged(pool, fixture.sourceId);

      const result = await service.reschedule(
        actor,
        fixture.sourceId,
        { ...dto("2026-07-27T11:00:00.000Z"), confirm: true as const },
        metadata("success"),
      );
      expect(result).toMatchObject({
        source: { id: fixture.sourceId, state: "rescheduled", version: 2 },
        successor: { state: "scheduled", version: 1 },
        financialDecision,
        replayed: false,
      });
      const persisted = await pool.query<{
        source_state: string;
        successor_id: string;
        predecessor_id: string;
        transition_count: number;
        audit_count: number;
      }>(
        `
          select source.lifecycle_state as source_state,
            source.successor_id,
            successor.predecessor_id,
            (select count(*)::int from app.lesson_transitions
              where lesson_id = source.id) as transition_count,
            (select count(*)::int from app.audit_events
              where action = 'crm.lesson_rescheduled'
                and entity_id = source.id::text) as audit_count
          from app.lessons source
          join app.lessons successor on successor.id = source.successor_id
          where source.id = $1
        `,
        [fixture.sourceId],
      );
      expect(persisted.rows[0]).toEqual({
        source_state: "rescheduled",
        successor_id: result.successor!.id,
        predecessor_id: fixture.sourceId,
        transition_count: 1,
        audit_count: 1,
      });

      const cancelPreview = await service.previewCancel(
        actor,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          financialDecision,
        },
      );
      expect(cancelPreview).toMatchObject({ canConfirm: true });
      const cancelled = await service.cancel(
        actor,
        fixture.cancelId,
        {
          expectedVersion: 1,
          reasonCode: "school.cancelled",
          financialDecision,
          confirm: true,
        },
        metadata("cancel"),
      );
      expect(cancelled.source).toEqual({
        id: fixture.cancelId,
        state: "cancelled",
        version: 2,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });

  it("allows exactly one winner in a parallel reschedule race", async () => {
    const fixture = await createFixture(
      pool,
      new LessonLifecycleRepository(database),
    );
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const command = (scheduledAt: string) => ({
      expectedVersion: 1,
      reasonCode: "schedule.concurrent",
      financialDecision: {
        chargeClient: false,
        compensateTeacher: false,
      },
      successor: { scheduledAt },
      confirm: true as const,
    });
    const metadata = (label: string) => ({
      idempotencyKey: `reschedule-race-${label}-${randomUUID()}`,
      requestId: `reschedule-race-request-${label}-${randomUUID()}`,
    });
    try {
      const results = await Promise.allSettled([
        service.reschedule(
          actor,
          fixture.sourceId,
          command("2026-07-27T11:00:00.000Z"),
          metadata("left"),
        ),
        service.reschedule(
          actor,
          fixture.sourceId,
          command("2026-07-27T12:00:00.000Z"),
          metadata("right"),
        ),
      ]);
      expect(
        results.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      const rejected = results.filter(
        (result): result is PromiseRejectedResult =>
          result.status === "rejected",
      );
      expect(rejected).toHaveLength(1);
      expect(rejected[0]!.reason).toMatchObject({ status: 409 });

      const persisted = await pool.query<{
        source_state: string;
        source_version: number | string;
        successors: number;
        transitions: number;
        audits: number;
      }>(
        `
          select
            source.lifecycle_state as source_state,
            source.version as source_version,
            (
              select count(*)::int
              from app.lessons
              where predecessor_id = source.id
            ) as successors,
            (
              select count(*)::int
              from app.lesson_transitions
              where lesson_id = source.id
            ) as transitions,
            (
              select count(*)::int
              from app.audit_events
              where action = 'crm.lesson_rescheduled'
                and entity_id = source.id::text
            ) as audits
          from app.lessons source
          where source.id = $1
        `,
        [fixture.sourceId],
      );
      expect({
        ...persisted.rows[0],
        source_version: Number(persisted.rows[0]!.source_version),
      }).toEqual({
        source_state: "rescheduled",
        source_version: 2,
        successors: 1,
        transitions: 1,
        audits: 1,
      });
    } finally {
      await cleanup(pool, fixture);
    }
  });
});

async function expectSourceUnchanged(pool: Pool, lessonId: string) {
  const result = await pool.query<{
    lifecycle_state: string;
    version: number | string;
    successor_id: string | null;
    successors: number;
    transitions: number;
  }>(
    `
      select source.lifecycle_state, source.version, source.successor_id,
        (select count(*)::int from app.lessons where predecessor_id = source.id)
          as successors,
        (select count(*)::int from app.lesson_transitions
          where lesson_id = source.id) as transitions
      from app.lessons source where source.id = $1
    `,
    [lessonId],
  );
  expect({
    ...result.rows[0],
    version: Number(result.rows[0]!.version),
  }).toEqual({
    lifecycle_state: "scheduled",
    version: 1,
    successor_id: null,
    successors: 0,
    transitions: 0,
  });
}

async function createFixture(
  pool: Pool,
  lifecycle: LessonLifecycleRepository,
) {
  const branch = await pool.query<{ id: string }>(
    "insert into app.branches (name, timezone_name) values ($1, 'Europe/Moscow') returning id",
    [`Transition ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  await pool.query(
    "insert into app.branch_hours (branch_id, weekday, open_local, close_local) values ($1, 1, '09:00', '18:00')",
    [branchId],
  );
  const room = await pool.query<{ id: string }>(
    "insert into app.rooms (branch_id, name) values ($1, $2) returning id",
    [branchId, `Transition room ${randomUUID()}`],
  );
  const users = await pool.query<{ id: string; role: string }>(
    `insert into app.users (email, role, email_verified_at) values
      ($1, 'manager', now()), ($2, 'teacher', now()), ($3, 'client', now())
      returning id, role::text as role`,
    [
      `transition-manager-${randomUUID()}@test.local`,
      `transition-teacher-${randomUUID()}@test.local`,
      `transition-client-${randomUUID()}@test.local`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `insert into app.profiles (user_id, first_name, last_name) values
      ($1, 'Transition', 'Teacher'), ($2, 'Transition', 'Student')
      returning id, user_id`,
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
    `insert into app.teacher_branches (teacher_id, branch_id, active_from)
      values ($1, $2, '2026-01-01')`,
    [teacherId, branchId],
  );
  await pool.query(
    `insert into app.teacher_availability_rules (
      teacher_id, kind, available, timezone_name, weekday, local_start,
      local_end, valid_from, valid_until
    ) values ($1, 'recurring', true, 'Europe/Moscow', 1, '09:00', '18:00',
      '2026-01-01', '2026-12-31')`,
    [teacherId],
  );
  const student = await pool.query<{ id: string }>(
    "insert into app.students (profile_id, branch_id) values ($1, $2) returning id",
    [studentProfileId, branchId],
  );
  const studentId = student.rows[0]!.id;
  const lessons = await pool.query<{ id: string; scheduled_at: Date }>(
    `insert into app.lessons (
      student_id, teacher_id, branch_id, room_id, scheduled_at,
      duration_minutes, created_by
    ) values
      ($1, $2, $3, $4, '2026-07-27T07:00:00Z', 60, $5),
      ($1, $2, $3, $4, '2026-07-28T07:00:00Z', 60, $5),
      ($1, $2, $3, $4, '2026-07-27T09:00:00Z', 60, $5)
    returning id, scheduled_at`,
    [studentId, teacherId, branchId, room.rows[0]!.id, managerId],
  );
  const sourceId = lessons.rows[0]!.id;
  const cancelId = lessons.rows[1]!.id;
  for (const lessonId of [sourceId, cancelId]) {
    const client = await pool.connect();
    try {
      await lifecycle.createSnapshot(client, {
        lessonId,
        clientType: "student",
        clientId: studentId,
        completionType: "standard.success",
        clientChargeType: "none",
        clientChargeValue: 0,
        teacherCompensationType: "fixed",
        teacherCompensationValue: 700,
        trial: false,
      });
    } finally {
      client.release();
    }
  }
  return {
    branchId,
    roomId: room.rows[0]!.id,
    teacherId,
    studentId,
    managerId,
    userIds: [managerId, teacherUserId, clientUserId],
    profileIds: profiles.rows.map((row) => row.id),
    sourceId,
    cancelId,
  };
}

async function cleanup(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query("delete from app.idempotency_records where actor_key = $1", [
      `user:${fixture.managerId}`,
    ]);
    await client.query(
      `
        delete from app.platform_outbox_events
        where aggregate_type = 'schedule:lesson'
          and aggregate_id in (
            select id::text from app.lessons where created_by = $1
          )
      `,
      [fixture.managerId],
    );
    await client.query("delete from app.audit_events where actor_user_id = $1", [
      fixture.managerId,
    ]);
    await client.query(
      "delete from app.aggregate_versions where aggregate_type = 'schedule:lesson' and aggregate_id in (select id::text from app.lessons where created_by = $1)",
      [fixture.managerId],
    );
    await client.query(
      "delete from app.lesson_snapshots where lesson_id in (select id from app.lessons where created_by = $1)",
      [fixture.managerId],
    );
    await client.query(
      "delete from app.lesson_transitions where lesson_id in (select id from app.lessons where created_by = $1)",
      [fixture.managerId],
    );
    await client.query("delete from app.lessons where created_by = $1", [
      fixture.managerId,
    ]);
    await client.query("delete from app.students where id = $1", [fixture.studentId]);
    await client.query("delete from app.teacher_availability_rules where teacher_id = $1", [fixture.teacherId]);
    await client.query("delete from app.teacher_branches where teacher_id = $1", [fixture.teacherId]);
    await client.query("delete from app.teachers where id = $1", [fixture.teacherId]);
    await client.query("delete from app.rooms where id = $1", [fixture.roomId]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [fixture.profileIds]);
    await client.query("delete from app.users where id = any($1::uuid[])", [fixture.userIds]);
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
