import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { AvailabilityRepository } from "./availability.repository";
import { ConstraintEngineRepository } from "./constraint-engine.repository";
import { ScheduleConstraintEngine } from "./constraint-engine.service";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(testDatabaseUrl).hostname,
  )
) {
  throw new Error("Constraint engine tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Schedule constraint engine (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let engine: ScheduleConstraintEngine;

  beforeAll(async () => {
    pool = new Pool({ connectionString: testDatabaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    const availability = new AvailabilityRepository(database);
    engine = new ScheduleConstraintEngine(
      new ConstraintEngineRepository(database, availability),
    );
  });

  afterAll(async () => {
    await database.onModuleDestroy();
    await pool.end();
  });

  it("allows adjacency and blocks all overlaps with refs, excludeLessonId and cross-branch mismatch", async () => {
    const client = await pool.connect();
    await client.query("begin");
    try {
      const fixture = await createFixture(client);
      const baseDraft = {
        clientRef: { type: "student" as const, id: fixture.studentId },
        teacherId: fixture.teacherId,
        branchId: fixture.branchId,
        roomId: fixture.roomId,
      };

      const adjacent = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T08:00:00.000Z",
          endAt: "2026-07-27T09:00:00.000Z",
        },
        client,
      );
      expect(adjacent).toEqual({ valid: true, violations: [] });

      const overlapping = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T07:30:00.000Z",
          endAt: "2026-07-27T08:30:00.000Z",
        },
        client,
      );
      expect(overlapping.valid).toBe(false);
      expect(overlapping.violations).toEqual([
        {
          code: "TEACHER_OVERLAP",
          resource: { type: "teacher", id: fixture.teacherId },
          conflictingLessonIds: [fixture.lessonId],
          ruleIds: [],
        },
        {
          code: "CLIENT_OVERLAP",
          resource: { type: "client", id: fixture.studentId },
          conflictingLessonIds: [fixture.lessonId],
          ruleIds: [],
        },
        {
          code: "ROOM_OVERLAP",
          resource: { type: "room", id: fixture.roomId },
          conflictingLessonIds: [fixture.lessonId],
          ruleIds: [],
        },
      ]);

      const editingSameLesson = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T07:30:00.000Z",
          endAt: "2026-07-27T08:30:00.000Z",
          excludeLessonId: fixture.lessonId,
        },
        client,
      );
      expect(editingSameLesson).toEqual({ valid: true, violations: [] });

      const series = await client.query<{ id: string }>(
        `insert into app.schedule_series (
           student_id, teacher_id, room_id, branch_id, weekday, begin_time,
           duration_minutes, valid_from
         ) values ($1,$2,$3,$4,1,'10:00',60,'2026-01-01') returning id`,
        [
          fixture.studentId,
          fixture.teacherId,
          fixture.roomId,
          fixture.branchId,
        ],
      );
      const seriesId = series.rows[0]!.id;
      await client.query(
        "update app.lessons set series_id = $2 where id = $1",
        [fixture.lessonId, seriesId],
      );
      const replacingPlanSeries = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T07:30:00.000Z",
          endAt: "2026-07-27T08:30:00.000Z",
          excludeScheduleSeriesIds: [seriesId],
        },
        client,
      );
      expect(replacingPlanSeries).toEqual({ valid: true, violations: [] });

      await client.query("savepoint hard_overlap_guard");
      await expect(
        client.query(
          `insert into app.lessons (
             student_id, teacher_id, branch_id, room_id,
             scheduled_at, duration_minutes
           ) values ($1,$2,$3,$4,'2026-07-27T07:45:00.000Z',30)`,
          [
            fixture.studentId,
            fixture.teacherId,
            fixture.branchId,
            fixture.roomId,
          ],
        ),
      ).rejects.toMatchObject({ constraint: "lesson_resource_bookings_no_overlap" });
      await client.query("rollback to savepoint hard_overlap_guard");

      await client.query(
        `update app.lessons
         set original_scheduled_at = scheduled_at - interval '1 hour'
         where id = $1`,
        [fixture.lessonId],
      );
      const preservedRescheduledLesson = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T07:30:00.000Z",
          endAt: "2026-07-27T08:30:00.000Z",
          excludeScheduleSeriesIds: [seriesId],
        },
        client,
      );
      expect(preservedRescheduledLesson.violations).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            code: "CLIENT_OVERLAP",
            conflictingLessonIds: [fixture.lessonId],
          }),
        ]),
      );

      const crossBranch = await engine.validate(
        {
          ...baseDraft,
          branchId: fixture.otherBranchId,
          roomId: fixture.otherRoomId,
          startAt: "2026-07-27T09:00:00.000Z",
          endAt: "2026-07-27T10:00:00.000Z",
        },
        client,
      );
      expect(crossBranch).toEqual({
        valid: false,
        violations: [
          {
            code: "TEACHER_BRANCH_MISMATCH",
            resource: { type: "teacher", id: fixture.teacherId },
            conflictingLessonIds: [],
            ruleIds: [],
          },
        ],
      });

      const wrongRoomBranch = await engine.validate(
        {
          ...baseDraft,
          roomId: fixture.otherRoomId,
          startAt: "2026-07-27T09:00:00.000Z",
          endAt: "2026-07-27T10:00:00.000Z",
        },
        client,
      );
      expect(wrongRoomBranch.violations).toEqual([
        {
          code: "ROOM_BRANCH_MISMATCH",
          resource: { type: "room", id: fixture.otherRoomId },
          conflictingLessonIds: [],
          ruleIds: [],
        },
      ]);

      const outsideHours = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T15:00:00.000Z",
          endAt: "2026-07-27T16:00:00.000Z",
        },
        client,
      );
      expect(outsideHours.violations).toEqual([
        expect.objectContaining({ code: "OUTSIDE_BRANCH_HOURS" }),
      ]);

      const breakRule = await client.query<{ id: string }>(
        `insert into app.teacher_availability_rules (
           teacher_id, kind, available, timezone_name, weekday,
           local_start, local_end, valid_from, valid_until
         ) values ($1, 'recurring', false, 'Europe/Moscow', 1,
           '12:00', '13:00', '2026-01-01', '2026-12-31') returning id`,
        [fixture.teacherId],
      );
      const unavailable = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T09:00:00.000Z",
          endAt: "2026-07-27T10:00:00.000Z",
        },
        client,
      );
      expect(unavailable.violations).toEqual([
        {
          code: "TEACHER_UNAVAILABLE",
          resource: { type: "teacher", id: fixture.teacherId },
          conflictingLessonIds: [],
          ruleIds: [breakRule.rows[0]!.id],
        },
      ]);

      await client.query(
        "delete from app.teacher_availability_rules where id = $1",
        [breakRule.rows[0]!.id],
      );
      await client.query(
        "update app.lessons set lifecycle_state = 'successfully_completed' where id = $1",
        [fixture.lessonId],
      );
      const terminalDoesNotBlock = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T07:30:00.000Z",
          endAt: "2026-07-27T08:30:00.000Z",
        },
        client,
      );
      expect(terminalDoesNotBlock).toEqual({ valid: true, violations: [] });

      const group = await client.query<{ id: string }>(
        `insert into app.groups (name, branch_id) values ($1, $2) returning id`,
        [`Constraint group ${randomUUID()}`, fixture.branchId],
      );
      await client.query(
        `insert into app.group_students (group_id, student_id) values ($1, $2)`,
        [group.rows[0]!.id, fixture.studentId],
      );
      const groupLesson = await client.query<{ id: string }>(
        `insert into app.lessons (
           group_id, teacher_id, branch_id, room_id,
           scheduled_at, duration_minutes
         ) values ($1,$2,$3,$4,'2026-07-27T10:00:00.000Z',60)
         returning id`,
        [
          group.rows[0]!.id,
          fixture.teacherId,
          fixture.branchId,
          fixture.roomId,
        ],
      );
      const groupParticipantOverlap = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T10:30:00.000Z",
          endAt: "2026-07-27T11:30:00.000Z",
        },
        client,
      );
      expect(groupParticipantOverlap.violations).toEqual(expect.arrayContaining([
        expect.objectContaining({
          code: "CLIENT_OVERLAP",
          conflictingLessonIds: [groupLesson.rows[0]!.id],
        }),
      ]));

      await client.query(
        `insert into app.lesson_snapshots (
           lesson_id, group_id, completion_type,
           client_charge_type, client_charge_value,
           teacher_compensation_type, teacher_compensation_value,
           trial, duration_minutes
         ) values ($1, $2, 'standard.success', 'none', 0, 'none', 0, false, 60)`,
        [groupLesson.rows[0]!.id, group.rows[0]!.id],
      );
      await client.query(
        `insert into app.lesson_snapshot_participants (
           lesson_id, student_id, charge_type, charge_value
         ) values ($1, $2, 'none', 0)`,
        [groupLesson.rows[0]!.id, fixture.studentId],
      );
      await client.query(
        `update app.group_students set left_at = now()
         where group_id = $1 and student_id = $2`,
        [group.rows[0]!.id, fixture.studentId],
      );

      const snapshotParticipantOverlap = await engine.validate(
        {
          ...baseDraft,
          startAt: "2026-07-27T10:30:00.000Z",
          endAt: "2026-07-27T11:30:00.000Z",
        },
        client,
      );
      expect(snapshotParticipantOverlap.violations).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            code: "CLIENT_OVERLAP",
            conflictingLessonIds: [groupLesson.rows[0]!.id],
          }),
        ]),
      );
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});

async function createFixture(client: PoolClient) {
  const branches = await client.query<{ id: string }>(
    `
      insert into app.branches (name, timezone_name)
      values ($1, 'Europe/Moscow'), ($2, 'Europe/Moscow')
      returning id
    `,
    [`Constraint ${randomUUID()}`, `Other ${randomUUID()}`],
  );
  const branchId = branches.rows[0]!.id;
  const otherBranchId = branches.rows[1]!.id;
  await client.query(
    `
      insert into app.branch_hours (branch_id, weekday, open_local, close_local)
      values
        ($1, 1, '09:00', '18:00'),
        ($2, 1, '09:00', '18:00')
    `,
    [branchId, otherBranchId],
  );
  const rooms = await client.query<{ id: string }>(
    `
      insert into app.rooms (branch_id, name)
      values ($1, $3), ($2, $4)
      returning id
    `,
    [branchId, otherBranchId, `Room ${randomUUID()}`, `Room ${randomUUID()}`],
  );
  const user = await client.query<{ id: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values ($1, 'teacher', now())
      returning id
    `,
    [`constraint-${randomUUID()}@example.test`],
  );
  const teacherProfile = await client.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values ($1, 'Constraint', 'Teacher')
      returning id
    `,
    [user.rows[0]!.id],
  );
  const teacher = await client.query<{ id: string }>(
    `
      insert into app.teachers (profile_id)
      values ($1)
      returning id
    `,
    [teacherProfile.rows[0]!.id],
  );
  const teacherId = teacher.rows[0]!.id;
  await client.query(
    `
      insert into app.teacher_branches (
        teacher_id, branch_id, active_from, active_until
      )
      values ($1, $2, '2026-01-01', '2026-12-31')
    `,
    [teacherId, branchId],
  );
  await client.query(
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
  const studentUser = await client.query<{ id: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values ($1, 'client', now())
      returning id
    `,
    [`constraint-student-${randomUUID()}@example.test`],
  );
  const studentProfile = await client.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values ($1, 'Constraint', 'Student')
      returning id
    `,
    [studentUser.rows[0]!.id],
  );
  const student = await client.query<{ id: string }>(
    `
      insert into app.students (profile_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [studentProfile.rows[0]!.id, branchId],
  );
  const lesson = await client.query<{ id: string }>(
    `
      insert into app.lessons (
        student_id, teacher_id, branch_id, room_id,
        scheduled_at, duration_minutes
      )
      values ($1, $2, $3, $4, '2026-07-27T07:00:00.000Z', 60)
      returning id
    `,
    [student.rows[0]!.id, teacherId, branchId, rooms.rows[0]!.id],
  );
  return {
    branchId,
    otherBranchId,
    teacherId,
    studentId: student.rows[0]!.id,
    roomId: rooms.rows[0]!.id,
    otherRoomId: rooms.rows[1]!.id,
    lessonId: lesson.rows[0]!.id,
  };
}
