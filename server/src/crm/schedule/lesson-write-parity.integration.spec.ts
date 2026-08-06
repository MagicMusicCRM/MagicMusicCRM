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
import { LessonCommandService } from "./lesson-command.service";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";
import { LessonRequiredFieldValidator } from "./lesson-required-field.validator";
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
  throw new Error("Lesson write parity tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Unified lesson create/edit/drag writes (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let commands: LessonCommandService;

  beforeAll(async () => {
    pool = new Pool({ connectionString: testDatabaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const availability = new AvailabilityRepository(database);
    commands = new LessonCommandService(
      database,
      new PlatformIntegrityService(database, new PlatformIntegrityRepository()),
      new CrmPolicy(),
      new ClientReferenceService(database),
      new LessonRequiredFieldValidator(),
      new ScheduleConstraintEngine(
        new ConstraintEngineRepository(database, availability),
      ),
      new LessonLifecycleRepository(database),
      new SubscriptionReservationService(database, {
        emitCrmChanged: jest.fn(),
        emitFinanceChanged: jest.fn(),
      } as unknown as RealtimeBus),
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("returns identical violations for create/edit/drag and replays a create once", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const keys: string[] = [];
    const key = (name: string) => {
      const value = `lesson-${name}-${randomUUID()}`;
      keys.push(value);
      return {
        idempotencyKey: value,
        requestId: `request-${name}-${randomUUID()}`,
      };
    };
    const base = {
      clientRef: { type: "student" as const, id: fixture.studentId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      durationMinutes: 60,
      isTrial: false,
      completionType: "standard.success",
      clientChargeType: "none" as const,
      clientChargeValue: 0,
      teacherCompensationType: "fixed" as const,
      teacherCompensationValue: 700,
    };
    const createdIds: string[] = [];
    try {
      const seed = await commands.create(
        actor,
        { ...base, scheduledAt: "2026-07-27T07:00:00.000Z" },
        key("seed"),
      );
      createdIds.push(seed.id);
      const editable = await commands.create(
        actor,
        { ...base, scheduledAt: "2026-07-27T09:00:00.000Z" },
        key("editable"),
      );
      createdIds.push(editable.id);

      const invalidCreate = await violationResponse(() =>
        commands.create(
          actor,
          { ...base, scheduledAt: "2026-07-27T07:30:00.000Z" },
          key("invalid-create"),
        ),
      );
      const preview = await commands.previewConstraints(actor, {
        clientRef: base.clientRef,
        teacherId: base.teacherId,
        branchId: base.branchId,
        roomId: base.roomId,
        scheduledAt: "2026-07-27T07:30:00.000Z",
        durationMinutes: base.durationMinutes,
      });
      const invalidEdit = await violationResponse(() =>
        commands.update(
          actor,
          editable.id,
          {
            ...base,
            expectedVersion: editable.version,
            scheduledAt: "2026-07-27T07:30:00.000Z",
          },
          key("invalid-edit"),
        ),
      );
      const invalidDrag = await violationResponse(() =>
        commands.update(
          actor,
          editable.id,
          {
            expectedVersion: editable.version,
            scheduledAt: "2026-07-27T07:30:00.000Z",
          },
          key("invalid-drag"),
        ),
      );
      expect(invalidCreate).toEqual(invalidEdit);
      expect(invalidEdit).toEqual(invalidDrag);
      expect(preview.violations).toEqual(invalidCreate.violations);
      expect(invalidCreate).toEqual({
        code: "LESSON_CONSTRAINT_VIOLATIONS",
        violations: [
          {
            code: "TEACHER_OVERLAP",
            resource: { type: "teacher", id: fixture.teacherId },
            conflictingLessonIds: [seed.id],
            ruleIds: [],
          },
          {
            code: "CLIENT_OVERLAP",
            resource: { type: "client", id: fixture.studentId },
            conflictingLessonIds: [seed.id],
            ruleIds: [],
          },
          {
            code: "ROOM_OVERLAP",
            resource: { type: "room", id: fixture.roomId },
            conflictingLessonIds: [seed.id],
            ruleIds: [],
          },
        ],
      });

      const createMetadata = key("replay");
      const replayDto = {
        ...base,
        scheduledAt: "2026-07-27T10:00:00.000Z",
      };
      const first = await commands.create(actor, replayDto, createMetadata);
      const replay = await commands.create(actor, replayDto, createMetadata);
      createdIds.push(first.id);
      expect(replay).toMatchObject({
        id: first.id,
        version: first.version,
        replayed: true,
      });
      const count = await pool.query<{ count: string }>(
        "select count(*)::text as count from app.lessons where id = $1",
        [first.id],
      );
      expect(count.rows[0]!.count).toBe("1");

      const moved = await commands.update(
        actor,
        editable.id,
        {
          expectedVersion: editable.version,
          scheduledAt: "2026-07-27T11:00:00.000Z",
        },
        key("valid-drag"),
      );
      expect(moved).toMatchObject({
        id: editable.id,
        version: editable.version + 1,
        replayed: false,
        scheduledAt: new Date("2026-07-27T11:00:00.000Z"),
      });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds: createdIds,
      });
    }
  });

  it("returns 403 and preserves the Lesson on a direct Teacher mutation", async () => {
    const fixture = await createFixture(pool);
    const manager = { userId: fixture.managerId, role: "manager" as const };
    const teacher = {
      userId: fixture.teacherUserId,
      role: "teacher" as const,
    };
    const lessonIds: string[] = [];
    const metadata = (name: string) => ({
      idempotencyKey: `teacher-read-only-${name}-${randomUUID()}`,
      requestId: `teacher-read-only-request-${name}-${randomUUID()}`,
    });
    try {
      const lesson = await commands.create(
        manager,
        {
          clientRef: { type: "student", id: fixture.studentId },
          teacherId: fixture.teacherId,
          branchId: fixture.branchId,
          roomId: fixture.roomId,
          scheduledAt: "2026-07-27T07:00:00.000Z",
          durationMinutes: 60,
          isTrial: false,
          completionType: "standard.success",
          clientChargeType: "none",
          clientChargeValue: 0,
          teacherCompensationType: "fixed",
          teacherCompensationValue: 700,
        },
        metadata("create"),
      );
      lessonIds.push(lesson.id);

      let status: number | null = null;
      try {
        await commands.update(
          teacher,
          lesson.id,
          {
            expectedVersion: lesson.version,
            notes: "Teacher must not mutate the Lesson",
          },
          metadata("patch"),
        );
      } catch (error) {
        if (error instanceof HttpException) status = error.getStatus();
        else throw error;
      }
      expect(status).toBe(403);

      const persisted = await pool.query<{
        version: string;
        notes: string | null;
      }>(
        "select version::text as version, notes from app.lessons where id = $1",
        [lesson.id],
      );
      expect(persisted.rows[0]).toEqual({
        version: String(lesson.version),
        notes: null,
      });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds,
      });
    }
  });

  it("serializes parallel create and drag races into one accepted interval", async () => {
    const fixture = await createFixture(pool);
    const actor = { userId: fixture.managerId, role: "manager" as const };
    const lessonIds: string[] = [];
    const metadata = (name: string) => ({
      idempotencyKey: `schedule-race-${name}-${randomUUID()}`,
      requestId: `schedule-race-request-${name}-${randomUUID()}`,
    });
    const base = {
      clientRef: { type: "student" as const, id: fixture.studentId },
      teacherId: fixture.teacherId,
      branchId: fixture.branchId,
      roomId: fixture.roomId,
      durationMinutes: 60,
      isTrial: false,
      completionType: "standard.success",
      clientChargeType: "none" as const,
      clientChargeValue: 0,
      teacherCompensationType: "fixed" as const,
      teacherCompensationValue: 700,
    };
    try {
      const concurrentCreates = await Promise.allSettled([
        commands.create(
          actor,
          { ...base, scheduledAt: "2026-07-27T07:00:00.000Z" },
          metadata("create-left"),
        ),
        commands.create(
          actor,
          { ...base, scheduledAt: "2026-07-27T07:00:00.000Z" },
          metadata("create-right"),
        ),
      ]);
      const acceptedCreate = concurrentCreates.filter(
        (
          result,
        ): result is PromiseFulfilledResult<
          Awaited<ReturnType<LessonCommandService["create"]>>
        > => result.status === "fulfilled",
      );
      const rejectedCreate = concurrentCreates.filter(
        (result): result is PromiseRejectedResult =>
          result.status === "rejected",
      );
      expect(acceptedCreate).toHaveLength(1);
      expect(rejectedCreate).toHaveLength(1);
      expect(rejectedCreate[0]!.reason).toMatchObject({ status: 422 });
      lessonIds.push(acceptedCreate[0]!.value.id);

      const left = await commands.create(
        actor,
        { ...base, scheduledAt: "2026-07-27T09:00:00.000Z" },
        metadata("drag-source-left"),
      );
      const right = await commands.create(
        actor,
        { ...base, scheduledAt: "2026-07-27T11:00:00.000Z" },
        metadata("drag-source-right"),
      );
      lessonIds.push(left.id, right.id);

      const concurrentDrags = await Promise.allSettled([
        commands.update(
          actor,
          left.id,
          {
            expectedVersion: left.version,
            scheduledAt: "2026-07-27T13:00:00.000Z",
          },
          metadata("drag-left"),
        ),
        commands.update(
          actor,
          right.id,
          {
            expectedVersion: right.version,
            scheduledAt: "2026-07-27T13:00:00.000Z",
          },
          metadata("drag-right"),
        ),
      ]);
      expect(
        concurrentDrags.filter((result) => result.status === "fulfilled"),
      ).toHaveLength(1);
      const rejectedDrag = concurrentDrags.filter(
        (result): result is PromiseRejectedResult =>
          result.status === "rejected",
      );
      expect(rejectedDrag).toHaveLength(1);
      expect(rejectedDrag[0]!.reason).toMatchObject({ status: 422 });

      const persisted = await pool.query<{
        at_target: string;
        at_sources: string;
      }>(
        `
          select
            count(*) filter (
              where scheduled_at = '2026-07-27T13:00:00.000Z'
            )::text as at_target,
            count(*) filter (
              where scheduled_at in (
                '2026-07-27T09:00:00.000Z',
                '2026-07-27T11:00:00.000Z'
              )
            )::text as at_sources
          from app.lessons
          where id = any($1::uuid[])
        `,
        [[left.id, right.id]],
      );
      expect(persisted.rows[0]).toEqual({
        at_target: "1",
        at_sources: "1",
      });
    } finally {
      await cleanupFixture(pool, {
        ...fixture,
        actorKey: `user:${fixture.managerId}`,
        lessonIds,
      });
    }
  });
});

async function violationResponse(work: () => Promise<unknown>) {
  try {
    await work();
    throw new Error("Expected lesson constraint violation.");
  } catch (error) {
    if (!(error instanceof HttpException)) throw error;
    const response = error.getResponse() as {
      code?: string;
      violations?: unknown[];
    };
    return {
      code: response.code,
      violations: response.violations,
    };
  }
}

async function createFixture(pool: Pool) {
  const branch = await pool.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'Europe/Moscow')
      returning id
    `,
    [`Write parity ${randomUUID()}`],
  );
  const branchId = branch.rows[0]!.id;
  await pool.query(
    `
      insert into app.branch_hours (branch_id, weekday, open_local, close_local)
      values ($1, 1, '09:00', '18:00')
    `,
    [branchId],
  );
  const room = await pool.query<{ id: string }>(
    `
      insert into app.rooms (branch_id, name)
      values ($1, $2)
      returning id
    `,
    [branchId, `Parity room ${randomUUID()}`],
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
      `parity-manager-${randomUUID()}@example.test`,
      `parity-teacher-${randomUUID()}@example.test`,
      `parity-client-${randomUUID()}@example.test`,
    ],
  );
  const managerId = users.rows.find((row) => row.role === "manager")!.id;
  const teacherUserId = users.rows.find((row) => row.role === "teacher")!.id;
  const clientUserId = users.rows.find((row) => row.role === "client")!.id;
  const profiles = await pool.query<{ id: string; user_id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values
        ($1, 'Parity', 'Teacher'),
        ($2, 'Parity', 'Student')
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
        $1, 'recurring', true, 'Europe/Moscow', 1,
        '09:00', '18:00', '2026-01-01', '2026-12-31'
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
  return {
    branchId,
    roomId: room.rows[0]!.id,
    teacherId,
    studentId: student.rows[0]!.id,
    managerId,
    teacherUserId,
    clientUserId,
    profileIds: profiles.rows.map((row) => row.id),
  };
}

async function cleanupFixture(
  pool: Pool,
  fixture: {
    branchId: string;
    roomId: string;
    teacherId: string;
    studentId: string;
    managerId: string;
    teacherUserId: string;
    clientUserId: string;
    profileIds: string[];
    actorKey: string;
    lessonIds: string[];
  },
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    await client.query(
      "delete from app.idempotency_records where actor_key = $1",
      [fixture.actorKey],
    );
    await client.query(
      `
        delete from app.platform_outbox_events
        where aggregate_type = 'schedule:lesson'
          and aggregate_id = any($1::text[])
      `,
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.audit_events where actor_user_id = $1",
      [fixture.managerId],
    );
    await client.query(
      "delete from app.aggregate_versions where aggregate_type = 'schedule:lesson' and aggregate_id = any($1::text[])",
      [fixture.lessonIds],
    );
    await client.query(
      "delete from app.lesson_snapshots where lesson_id = any($1::uuid[])",
      [fixture.lessonIds],
    );
    await client.query("delete from app.lessons where id = any($1::uuid[])", [
      fixture.lessonIds,
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
    await client.query("delete from app.rooms where id = $1", [fixture.roomId]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      [fixture.managerId, fixture.teacherUserId, fixture.clientUserId],
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
