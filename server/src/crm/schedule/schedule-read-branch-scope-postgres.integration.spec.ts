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
      items: expect.arrayContaining([
        expect.objectContaining({ branchId: assignedBranchId }),
        expect.objectContaining({ branchId: outsideBranchId }),
      ]),
    });
    await expect(availability(current)).resolves.toMatchObject({
      items: expect.arrayContaining([
        expect.objectContaining({ roomId: assignedRoomId }),
        expect.objectContaining({ roomId: outsideRoomId }),
      ]),
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
          financialDecision: null,
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
          financialDecision: null,
          groupParticipants: [],
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
          financialDecision: {
            settlementTypeKey: "lesson",
            teacherCompensationRuleKey: "fixed",
            teacherCompensationValueMinor: "50000",
            clientDecisions: [{
              clientId: assignedStudentId, payerStudentId: assignedStudentId,
              chargeType: "personal_account", basePriceMinor: "70000",
            }],
          },
        }),
      ],
    });
  });

  it("projects actual reservation state in the matrix without widening role or branch scope", async () => {
    await client.query("savepoint reservation_read");
    try {
      const subscription = await client.query<{ id: string }>(
        `insert into app.subscriptions (student_id, lessons_total, lessons_used, status)
         values ($1, 4, 0, 'active') returning id`,
        [assignedStudentId],
      );
      const subscriptionId = subscription.rows[0]!.id;
      // An active subscription alone must not claim actual coverage.
      expect((await matrix(manager)).items[0].reservationState).toBeNull();

      await client.query(
        `insert into app.lesson_reservations (id, lesson_id, subscription_id, units)
         values ('ffffffff-ffff-4fff-bfff-ffffffff0147', $1, $2, 1)`,
        [assignedLessonId, subscriptionId],
      );
      for (const actor of [manager, teacher, { ...teacher, role: "manager" as const }]) {
        const calendar = await matrix(actor);
        const lesson = calendar.items.find((item) => item.id === assignedLessonId)!;
        expect(lesson).toMatchObject({
          reservationState: "reserved", lifecycleState: "scheduled",
        });
        const groupLesson = calendar.groups.flatMap((group) => group.items)
          .find((item) => item.id === assignedLessonId)!;
        expect(groupLesson.reservationState).toBe("reserved");
        const exact = await schedule.listLessons(actor, { lessonId: assignedLessonId });
        expect(exact.items[0].reservationState).toBe(lesson.reservationState);
        if (actor.userId === teacher.userId) {
          expect(lesson.financialDecision).toBeNull();
          expect(lesson.subscriptionId).toBeNull();
        }
      }
      await expect(matrix(manager, outsideBranchId)).resolves.toMatchObject({ items: [] });
      await expect(matrix(unassignedAdmin)).resolves.toMatchObject({ items: [] });
      const staleDirectorClient = { userId: assignedStudentUserId, role: "director" as const };
      await expect(matrix(staleDirectorClient)).resolves.toMatchObject({ items: [] });

      await client.query(
        `update app.lesson_reservations set state = 'released', terminal_at = now(),
           version = version + 1 where lesson_id = $1`,
        [assignedLessonId],
      );
      expect((await matrix(manager)).items[0].reservationState).toBe("released");
      // Rebooking in the same transaction shares now() with its released row.
      // The current reservation must win regardless of UUID sorting.
      await client.query(
        `insert into app.lesson_reservations (id, lesson_id, subscription_id, units)
         values ('00000000-0000-4000-8000-000000000147', $1, $2, 1)`,
        [assignedLessonId, subscriptionId],
      );
      for (const actor of [manager, teacher]) {
        const calendar = await matrix(actor);
        expect(calendar.items.filter((item) => item.id === assignedLessonId)).toHaveLength(1);
        expect(calendar.items.find((item) => item.id === assignedLessonId)?.reservationState).toBe("reserved");
        const exact = await schedule.listLessons(actor, { lessonId: assignedLessonId });
        expect(exact.items[0].reservationState).toBe("reserved");
      }
    } finally {
      await client.query("rollback to savepoint reservation_read");
    }
  });

  it("returns frozen participants and the latest public decision in both views", async () => {
    const read = async () => {
      const exact = await schedule.listLessons(manager, { lessonId: assignedLessonId });
      const calendar = await matrix(manager);
      return [exact.items[0], calendar.items.find((item) => item.id === assignedLessonId)!];
    };
    for (const item of await read()) {
      expect(item.groupParticipants).toEqual([
        expect.objectContaining({ clientId: assignedStudentId }),
      ]);
      expect(item.financialDecision?.teacherCompensationRuleKey).toBe("fixed");
      expect(JSON.stringify(item.financialDecision)).not.toContain("teacherRateSnapshot");
    }
    const staleManagerTeacher = { userId: teacher.userId, role: "manager" as const };
    expect((await matrix(staleManagerTeacher)).items.every((item) =>
      item.financialDecision === null)).toBe(true);

    await client.query("savepoint financial_read_correction");
    try {
      const payer = await client.query<{ student_id: string }>(
        "select student_id from app.lesson_participant_exclusions where lesson_id = $1",
        [assignedLessonId],
      );
      const actualPayerId = payer.rows[0]!.student_id;
      await client.query(
        `insert into app.lesson_client_charge_facts (
           lesson_id, client_type, client_id, charge_type, snapshot_value,
           amount_minor, units, payer_student_id, pricing_snapshot
         ) values ($1, 'student', $2, 'personal_account', 1800, 180000, 0, $3, $4::jsonb)`,
        [assignedLessonId, assignedStudentId, actualPayerId, JSON.stringify({
          basePriceMinor: "200000", finalPriceMinor: "180000",
          discount: { type: "percent", percentBasisPoints: 1250, reason: "Льгота" },
          surcharge: { type: "fixed", amountMinor: "5000", reason: "Доплата" },
        })],
      );
      await client.query(
        `insert into app.lesson_transitions (
           lesson_id, from_state, to_state, reason_code, actor_user_id, financial_decision
         ) values ($1, 'scheduled', 'successfully_completed', 'test.settle', $2, $3::jsonb)`,
        [assignedLessonId, director.userId, JSON.stringify({
          settlementTypeKey: "lesson", teacherCompensationRuleKey: "fixed",
          teacherCompensationValueMinor: "120000",
          clientDecisions: [{ clientId: assignedStudentId, settlementTypeKey: "lesson" }],
        })],
      );
      for (const item of await read()) {
        expect(item.teacherCompensationValueMinor).toBe("120000");
        expect(item.financialDecision?.clientDecisions).toEqual([{
          clientId: assignedStudentId, payerStudentId: actualPayerId,
          settlementTypeKey: "lesson", chargeType: "personal_account", basePriceMinor: "200000",
          discount: { type: "percent", percent: 12.5, reason: "Льгота" },
          surcharge: { amountMinor: "5000", reason: "Доплата" },
        }]);
      }
      await client.query(
        `insert into app.lesson_settlement_corrections (
           lesson_id, version, decision, settlement_revision_id,
           compensation_revision_id, reason_text, actor_user_id
         ) select lesson_id, 1, $2::jsonb, settlement_revision_id,
           compensation_revision_id, 'Read projection fixture', $3
         from app.lesson_settlement_plans where lesson_id = $1`,
        [assignedLessonId, JSON.stringify({
          settlementTypeKey: "free_lesson", teacherCompensationRuleKey: "none",
          clientDecisions: [{ clientId: assignedStudentId, chargeType: "none", settlementTypeKey: "free_lesson" }],
          teacherRateSnapshot: { type: "hourly", value: "9999" },
        }), director.userId],
      );
      for (const item of await read()) {
        expect(item.financialDecision).toEqual({
          settlementTypeKey: "free_lesson", teacherCompensationRuleKey: "none",
          clientDecisions: [{ clientId: assignedStudentId, chargeType: "none", settlementTypeKey: "free_lesson" }],
        });
        expect(item.settlementTypeKey).toBe("free_lesson");
        expect(item.teacherCompensationRuleKey).toBe("none");
      }
    } finally {
      await client.query("rollback to savepoint financial_read_correction");
    }
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

  const revision = await client.query<{ id: string }>(
    `insert into app.crm_configuration_revisions (
       branch_id, version, patch, effective_snapshot, reason, created_by
     ) values ($1, 1, '{}'::jsonb, '{}'::jsonb, 'Read projection fixture', $2)
     returning id`,
    [assignedBranchId, actors.director.userId],
  );
  await client.query(
    `insert into app.lesson_settlement_plans (
       lesson_id, decision, settlement_revision_id, compensation_revision_id, selected_by
     ) values ($1, $2::jsonb, $3, $3, $4)`,
    [assignedLessonId, JSON.stringify({
      settlementTypeKey: "lesson", teacherCompensationRuleKey: "fixed",
      teacherCompensationValueMinor: "50000",
      teacherRateSnapshot: { type: "hourly", value: "9999" },
      clientDecisions: [{
        clientId: assignedStudentId, payerStudentId: assignedStudentId,
        chargeType: "personal_account", basePriceMinor: "70000",
      }],
    }), revision.rows[0]!.id, actors.director.userId],
  );
  await client.query(
    `insert into app.lesson_snapshot_participants (
       lesson_id, student_id, charge_type, charge_value
     ) values ($1, $2, 'personal_account', 700), ($1, $3, 'none', 0)`,
    [assignedLessonId, assignedStudentId, outsideStudentId],
  );
  await client.query(
    `insert into app.lesson_participant_exclusions (
       lesson_id, student_id, reason_code, actor_user_id
     ) values ($1, $2, 'test.excluded', $3)`,
    [assignedLessonId, outsideStudentId, actors.director.userId],
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
