import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient, QueryResultRow } from "pg";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { CrmPolicy } from "../crm.policy";
import { RoomsService } from "../rooms.service";
import { ScheduleReadService } from "./schedule-read.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Schedule branch-scope tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("schedule read branch scope (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let schedule: ScheduleReadService;
  let rooms: RoomsService;
  let assignedBranchId: string;
  let outsideBranchId: string;
  let assignedRoomId: string;
  let outsideRoomId: string;
  let assignedLessonId: string;
  let assignedStudentUserId: string;
  let assignedStudentId: string;
  let manager: ActorContext;
  let admin: ActorContext;
  let unassignedAdmin: ActorContext;
  let director: ActorContext;
  let systemAdmin: ActorContext;
  let teacher: ActorContext;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");

    const database = {
      query: <T extends QueryResultRow>(text: string, values?: unknown[]) =>
        client.query<T>(text, values),
    } as unknown as DatabaseService;
    const policy = new CrmPolicy();
    schedule = new ScheduleReadService(database, policy);
    rooms = new RoomsService(
      database,
      { record: jest.fn() } as unknown as AuditService,
      policy,
    );

    const fixture = await createFixture(client);
    assignedBranchId = fixture.assignedBranchId;
    outsideBranchId = fixture.outsideBranchId;
    assignedRoomId = fixture.assignedRoomId;
    outsideRoomId = fixture.outsideRoomId;
    assignedLessonId = fixture.assignedLessonId;
    assignedStudentUserId = fixture.assignedStudentUserId;
    assignedStudentId = fixture.assignedStudentId;
    manager = fixture.manager;
    admin = fixture.admin;
    unassignedAdmin = fixture.unassignedAdmin;
    director = fixture.director;
    systemAdmin = fixture.systemAdmin;
    teacher = fixture.teacher;
  });

  afterAll(async () => {
    if (client) {
      await client.query("rollback");
      client.release();
    }
    if (pool) await pool.end();
  });

  it.each([
    ["manager", () => manager],
    ["admin", () => admin],
  ])(
    "keeps %s omitted and explicit filters inside assigned branches",
    async (_, actor) => {
      const current = actor();

      await expect(matrix(current)).resolves.toMatchObject({
        items: [expect.objectContaining({ branchId: assignedBranchId })],
      });
      await expect(month(current)).resolves.toMatchObject({
        items: [expect.objectContaining({ count: 1 })],
      });
      await expect(
        schedule.listLessons(current, { limit: 20 }),
      ).resolves.toMatchObject({
        items: [expect.objectContaining({ branchId: assignedBranchId })],
      });
      await expect(availability(current)).resolves.toMatchObject({
        items: [expect.objectContaining({ branchId: assignedBranchId })],
      });

      await expect(matrix(current, outsideBranchId)).resolves.toMatchObject({
        items: [],
      });
      await expect(
        availability(current, outsideBranchId),
      ).resolves.toMatchObject({
        items: [],
      });
    },
  );

  it.each([
    ["director", () => director],
    ["system_admin", () => systemAdmin],
  ])("preserves school-wide reads for %s", async (_, actor) => {
    const current = actor();
    await expect(matrix(current)).resolves.toMatchObject({
      items: [
        expect.objectContaining({ branchId: assignedBranchId }),
        expect.objectContaining({ branchId: outsideBranchId }),
      ],
    });
    await expect(availability(current)).resolves.toMatchObject({
      items: [
        expect.objectContaining({ roomId: assignedRoomId }),
        expect.objectContaining({ roomId: outsideRoomId }),
      ],
    });
  });

  it("fails closed for an admin without branch assignments", async () => {
    await expect(matrix(unassignedAdmin)).resolves.toMatchObject({ items: [] });
    await expect(month(unassignedAdmin)).resolves.toMatchObject({ items: [] });
    await expect(
      schedule.listLessons(unassignedAdmin, { limit: 20 }),
    ).resolves.toMatchObject({ items: [] });
    await expect(availability(unassignedAdmin)).resolves.toMatchObject({
      items: [],
    });
  });

  it("uses the current database role instead of a stale wider token role", async () => {
    const staleDirectorToken = {
      userId: manager.userId,
      role: "director" as const,
    };

    await expect(matrix(staleDirectorToken)).resolves.toMatchObject({
      items: [expect.objectContaining({ branchId: assignedBranchId })],
    });
    await expect(availability(staleDirectorToken)).resolves.toMatchObject({
      items: [expect.objectContaining({ branchId: assignedBranchId })],
    });
  });

  it("uses the current database role for lesson finance projections", async () => {
    const staleManagerTeacher = {
      userId: teacher.userId,
      role: "manager" as const,
    };
    const staleManagerClient = {
      userId: assignedStudentUserId,
      role: "manager" as const,
    };

    await expect(
      schedule.listLessons(staleManagerTeacher, { lessonId: assignedLessonId }),
    ).resolves.toMatchObject({
      items: [
        expect.objectContaining({
          teacherRate: null,
          appliedTeacherRate: null,
          paidAmount: null,
          clientChargeType: null,
          clientChargeValue: null,
          teacherCompensationType: null,
          teacherCompensationValue: null,
          settlementFailureCode: null,
        }),
      ],
    });

    await expect(
      schedule.listLessons(staleManagerClient, { lessonId: assignedLessonId }),
    ).resolves.toMatchObject({
      items: [
        expect.objectContaining({
          teacherRate: null,
          appliedTeacherRate: null,
          clientChargeType: "personal_account",
          clientChargeValue: 700,
          teacherCompensationType: null,
          teacherCompensationValue: null,
          settlementFailureCode: null,
        }),
      ],
    });

    await expect(
      schedule.listLessons(manager, { lessonId: assignedLessonId }),
    ).resolves.toMatchObject({
      items: [
        expect.objectContaining({
          teacherRate: 777,
          appliedTeacherRate: 777,
          clientChargeValue: 700,
          teacherCompensationValue: 500,
        }),
      ],
    });
  });

  it("uses IANA timezone days for DST and legacy room-scoped lessons", async () => {
    const marker = randomUUID();
    const branch = await client.query<{ id: string }>(
      `insert into app.branches (name, timezone_name, utc_offset_minutes)
       values ($1, 'America/New_York', -300) returning id`,
      [`New York ${marker}`],
    );
    const branchId = branch.rows[0]!.id;
    const room = await client.query<{ id: string }>(
      `insert into app.rooms (branch_id, name)
       values ($1, $2) returning id`,
      [branchId, `NY room ${marker}`],
    );
    await client.query(
      `insert into app.lessons (
         student_id, branch_id, room_id, scheduled_at, duration_minutes, created_by
       ) values
         ($1, null, $2, '2026-03-08T05:30:00.000Z', 60, $3),
         ($1, null, $2, '2026-11-01T04:30:00.000Z', 60, $3),
         ($1, null, $2, '2026-11-02T04:30:00.000Z', 60, $3)`,
      [assignedStudentId, room.rows[0]!.id, director.userId],
    );

    await expect(
      schedule.getScheduleMonthSummary(director, {
        branchId,
        from: "2026-03-07T00:00:00.000Z",
        to: "2026-03-10T00:00:00.000Z",
      }),
    ).resolves.toMatchObject({ items: [{ day: "2026-03-08", count: 1 }] });
    await expect(
      schedule.getScheduleMonthSummary(director, {
        branchId,
        from: "2026-10-31T00:00:00.000Z",
        to: "2026-11-03T00:00:00.000Z",
      }),
    ).resolves.toMatchObject({ items: [{ day: "2026-11-01", count: 2 }] });

    await expect(
      rooms.listRoomAvailability(director, {
        branchId,
        date: "2026-03-08",
        slotFromMinutes: 360,
        slotToMinutes: 1380,
        limit: 20,
      } as never),
    ).resolves.toMatchObject({
      dateFrom: "2026-03-08T05:00:00.000Z",
      dateTo: "2026-03-09T04:00:00.000Z",
      slotFrom: "2026-03-08T10:00:00.000Z",
      slotTo: "2026-03-09T03:00:00.000Z",
    });
    await expect(
      rooms.listRoomAvailability(director, {
        branchId,
        date: "2026-11-01",
        slotFromMinutes: 360,
        slotToMinutes: 1380,
        limit: 20,
      } as never),
    ).resolves.toMatchObject({
      dateFrom: "2026-11-01T04:00:00.000Z",
      dateTo: "2026-11-02T05:00:00.000Z",
      slotFrom: "2026-11-01T11:00:00.000Z",
      slotTo: "2026-11-02T04:00:00.000Z",
    });
  });

  function matrix(actor: ActorContext, branchId?: string) {
    return schedule.getScheduleMatrix(actor, {
      from: "2026-08-30T00:00:00.000Z",
      to: "2026-08-31T00:00:00.000Z",
      branchId,
      limit: 20,
    });
  }

  function month(actor: ActorContext) {
    return schedule.getScheduleMonthSummary(actor, {
      from: "2026-08-01T00:00:00.000Z",
      to: "2026-09-01T00:00:00.000Z",
    });
  }

  function availability(actor: ActorContext, branchId?: string) {
    return rooms.listRoomAvailability(actor, {
      branchId,
      dayFrom: "2026-08-30T00:00:00.000Z",
      dayTo: "2026-08-31T00:00:00.000Z",
      from: "2026-08-30T00:00:00.000Z",
      to: "2026-08-31T00:00:00.000Z",
      limit: 20,
    });
  }
});

async function createFixture(client: PoolClient) {
  const marker = randomUUID();
  const branches = await client.query<{ id: string }>(
    `insert into app.branches (name, utc_offset_minutes)
     values ($1, 180), ($2, -300) returning id`,
    [`Scope assigned ${marker}`, `Scope outside ${marker}`],
  );
  const assignedBranchId = branches.rows[0]!.id;
  const outsideBranchId = branches.rows[1]!.id;
  const roomRows = await client.query<{ id: string; branch_id: string }>(
    `insert into app.rooms (branch_id, name)
     values ($1, $3), ($2, $4) returning id, branch_id`,
    [
      assignedBranchId,
      outsideBranchId,
      `Assigned room ${marker}`,
      `Outside room ${marker}`,
    ],
  );
  const assignedRoomId = roomRows.rows.find(
    (row) => row.branch_id === assignedBranchId,
  )!.id;
  const outsideRoomId = roomRows.rows.find(
    (row) => row.branch_id === outsideBranchId,
  )!.id;

  const actors = {} as Record<string, ActorContext>;
  for (const role of [
    "manager",
    "admin",
    "admin",
    "director",
    "system_admin",
  ] as const) {
    const key = role === "admin" && actors.admin ? "unassignedAdmin" : role;
    const user = await client.query<{ id: string }>(
      `insert into app.users (email, role, email_verified_at)
       values ($1, $2, now()) returning id`,
      [`${key}-${marker}@example.test`, role],
    );
    const userId = user.rows[0]!.id;
    actors[key] = { userId, role };
    const profile = await client.query<{ id: string }>(
      `insert into app.profiles (user_id, first_name, last_name)
       values ($1, $2, 'Scope') returning id`,
      [userId, key],
    );
    if (role === "manager" || role === "admin") {
      const staff = await client.query<{ id: string }>(
        `insert into app.staff_members (profile_id, role)
         values ($1, $2) returning id`,
        [profile.rows[0]!.id, role],
      );
      await client.query(
        `insert into app.user_crm_links (
           user_id, entity_type, entity_id, link_source, confirmed_at
         ) values ($1, 'staff', $2, 'manual_email', now())`,
        [userId, staff.rows[0]!.id],
      );
      if (key !== "unassignedAdmin") {
        await client.query(
          `insert into app.staff_branch_assignments (staff_member_id, branch_id)
           values ($1, $2)`,
          [staff.rows[0]!.id, assignedBranchId],
        );
      }
    }
  }

  const studentUsers = await client.query<{ id: string }>(
    `insert into app.users (email, role, email_verified_at)
     values ($1, 'client', now()), ($2, 'client', now()) returning id`,
    [
      `assigned-student-${marker}@example.test`,
      `outside-student-${marker}@example.test`,
    ],
  );
  const studentProfiles = await client.query<{ id: string }>(
    `insert into app.profiles (user_id, first_name, last_name)
     values ($1, $3, 'Assigned'), ($2, $3, 'Outside') returning id`,
    [studentUsers.rows[0]!.id, studentUsers.rows[1]!.id, `Student ${marker}`],
  );
  const students = await client.query<{ id: string; branch_id: string }>(
    `insert into app.students (profile_id, branch_id)
     values ($1, $3), ($2, $4) returning id, branch_id`,
    [
      studentProfiles.rows[0]!.id,
      studentProfiles.rows[1]!.id,
      assignedBranchId,
      outsideBranchId,
    ],
  );
  const assignedStudentId = students.rows.find(
    (row) => row.branch_id === assignedBranchId,
  )!.id;
  const outsideStudentId = students.rows.find(
    (row) => row.branch_id === outsideBranchId,
  )!.id;
  const teacherUser = await client.query<{ id: string }>(
    `insert into app.users (email, role, email_verified_at)
     values ($1, 'teacher', now()) returning id`,
    [`teacher-${marker}@example.test`],
  );
  const teacherProfile = await client.query<{ id: string }>(
    `insert into app.profiles (user_id, first_name, last_name)
     values ($1, $2, 'Teacher') returning id`,
    [teacherUser.rows[0]!.id, `Teacher ${marker}`],
  );
  const teacherRow = await client.query<{ id: string }>(
    `insert into app.teachers (profile_id)
     values ($1) returning id`,
    [teacherProfile.rows[0]!.id],
  );
  const lessonRows = await client.query<{ id: string; branch_id: string }>(
    `insert into app.lessons (
       student_id, teacher_id, branch_id, room_id, scheduled_at,
       duration_minutes, teacher_rate, created_by
     ) values
       ($1, $7, $3, $5, '2026-08-30T09:00:00.000Z', 60, 777, $8),
       ($2, $7, $4, $6, '2026-08-30T10:00:00.000Z', 60, 777, $8)
     returning id, branch_id`,
    [
      assignedStudentId,
      outsideStudentId,
      assignedBranchId,
      outsideBranchId,
      assignedRoomId,
      outsideRoomId,
      teacherRow.rows[0]!.id,
      actors.director.userId,
    ],
  );
  const assignedLessonId = lessonRows.rows.find(
    (row) => row.branch_id === assignedBranchId,
  )!.id;
  await client.query(
    `insert into app.lesson_snapshots (
       lesson_id, client_type, client_id, completion_type,
       client_charge_type, client_charge_value,
       teacher_compensation_type, teacher_compensation_value,
       trial, duration_minutes
     ) values (
       $1, 'student', $2, 'standard.success',
       'personal_account', 700, 'fixed', 500, false, 60
     )`,
    [assignedLessonId, assignedStudentId],
  );

  return {
    assignedBranchId,
    outsideBranchId,
    assignedRoomId,
    outsideRoomId,
    assignedLessonId,
    assignedStudentUserId: studentUsers.rows[0]!.id,
    assignedStudentId,
    manager: actors.manager,
    admin: actors.admin,
    unassignedAdmin: actors.unassignedAdmin,
    director: actors.director,
    systemAdmin: actors.system_admin,
    teacher: { userId: teacherUser.rows[0]!.id, role: "teacher" as const },
  };
}
