import { ForbiddenException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { ActorContext } from "../common/security/actor-context";
import { CrmPolicy } from "../crm/crm.policy";
import { DatabaseService } from "../db/database.service";
import { ReportingReadService } from "./reporting-read.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const parsedDatabaseUrl = new URL(databaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    parsedDatabaseUrl.hostname,
  )
) {
  throw new Error("Reporting scope tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("ReportingReadService hard scopes (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: ReportingReadService;
  let fixture: Awaited<ReturnType<typeof createFixture>>;
  const range = {
    from: "2026-07-01T00:00:00.000Z",
    to: "2026-08-01T00:00:00.000Z",
  };

  beforeAll(async () => {
    database = new DatabaseService(
      new ConfigService({ DATABASE_URL: databaseUrl }),
    );
    await cleanupStaleFixtures(database);
    service = new ReportingReadService(database, new CrmPolicy());
    fixture = await createFixture(database);
  });

  afterAll(async () => {
    if (fixture) await cleanupFixture(database, fixture);
    await database.onModuleDestroy();
  });

  it("derives lesson success only from terminal lifecycle with branch scope", async () => {
    const manager = await service.lessonSuccess(fixture.manager, range);
    expect(manager).toMatchObject({
      totalLessons: 2,
      successfulLessons: 1,
      successRate: 0.5,
    });
    expect(manager.drilldown.optionalFocus?.filter).toMatchObject({
      version: 1,
      status: "successfully_completed",
    });

    const director = await service.lessonSuccess(fixture.director, range);
    expect(director).toMatchObject({
      totalLessons: 3,
      successfulLessons: 2,
    });
    await expect(service.lessonSuccess(fixture.admin, range)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it("allows school finance only to Director/root and counts ActualPayment only", async () => {
    await expect(service.schoolFinance(fixture.admin, range)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    await expect(
      service.schoolFinance(fixture.manager, range),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const director = await service.schoolFinance(fixture.director, {
      ...range,
      branchId: fixture.assignedBranchId,
    });
    expect(director.revenueMinor).toBe("800000");
    expect(director.rows).toEqual([
      expect.objectContaining({
        monthStart: "2026-07-01",
        totalLessons: 2,
        successfulLessons: 1,
        revenueMinor: "800000",
        link: expect.objectContaining({
          entityType: "school_finance_month",
        }),
      }),
    ]);

    const root = await service.schoolFinance(fixture.systemAdmin, {
      ...range,
      branchId: fixture.otherBranchId,
    });
    expect(root.revenueMinor).toBe("400000");
    expect(root.revenueMinor).not.toBe("11100000");
  });
});

async function createFixture(database: DatabaseService) {
  const marker = `v4-report-scope-${randomUUID()}`;
  const users = await database.query<{ id: string; role: ActorContext["role"] }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'admin', now()),
        ($2, 'manager', now()),
        ($3, 'director', now()),
        ($4, 'system_admin', now()),
        ($5, 'client', now()),
        ($6, 'client', now())
      returning id, role::text as role
    `,
    [
      `${marker}-admin@example.test`,
      `${marker}-manager@example.test`,
      `${marker}-director@example.test`,
      `${marker}-root@example.test`,
      `${marker}-student-a@example.test`,
      `${marker}-student-b@example.test`,
    ],
  );
  const [admin, manager, director, systemAdmin, clientA, clientB] = users.rows;
  const branches = await database.query<{ id: string }>(
    `
      insert into app.branches (name)
      values ($1), ($2)
      returning id
    `,
    [`${marker}-assigned`, `${marker}-other`],
  );
  const [assignedBranch, otherBranch] = branches.rows;
  const profiles = await database.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name)
      values
        ($1, 'Manager'),
        ($2, 'Student A'),
        ($3, 'Student B')
      returning id
    `,
    [manager!.id, clientA!.id, clientB!.id],
  );
  const staff = await database.query<{ id: string }>(
    `
      insert into app.staff_members (profile_id, role)
      values ($1, 'manager')
      returning id
    `,
    [profiles.rows[0]!.id],
  );
  await database.query(
    `
      insert into app.staff_branch_assignments (staff_member_id, branch_id)
      values ($1, $2)
    `,
    [staff.rows[0]!.id, assignedBranch!.id],
  );
  const students = await database.query<{ id: string }>(
    `
      insert into app.students (profile_id, status, branch_id)
      values ($1, 'active', $3), ($2, 'active', $4)
      returning id
    `,
    [
      profiles.rows[1]!.id,
      profiles.rows[2]!.id,
      assignedBranch!.id,
      otherBranch!.id,
    ],
  );
  const lessons = await database.query<{ id: string }>(
    `
      insert into app.lessons (
        student_id, branch_id, scheduled_at, status, created_by
      )
      values
        ($1, $3, '2026-07-10T10:00:00Z', 'completed', $5),
        ($1, $3, '2026-07-11T10:00:00Z', 'cancelled', $5),
        ($2, $4, '2026-07-12T10:00:00Z', 'completed', $5)
      returning id
    `,
    [
      students.rows[0]!.id,
      students.rows[1]!.id,
      assignedBranch!.id,
      otherBranch!.id,
      director!.id,
    ],
  );
  const payments = await database.query<{ id: string }>(
    `
      insert into app.payments (
        student_id, branch_id, amount, payment_date, created_by
      )
      values
        ($1, $3, 8000, '2026-07-10T09:00:00Z', $5),
        ($2, $4, 4000, '2026-07-12T09:00:00Z', $5)
      returning id
    `,
    [
      students.rows[0]!.id,
      students.rows[1]!.id,
      assignedBranch!.id,
      otherBranch!.id,
      director!.id,
    ],
  );
  const expectedPayment = await database.query<{ id: string }>(
    `
      insert into app.expected_payments (
        student_id, amount, due_date, status, description
      )
      values ($1, 99000, '2026-07-20', 'pending', 'Not actual revenue')
      returning id
    `,
    [students.rows[0]!.id],
  );

  return {
    admin: { userId: admin!.id, role: "admin" } as ActorContext,
    manager: { userId: manager!.id, role: "manager" } as ActorContext,
    director: { userId: director!.id, role: "director" } as ActorContext,
    systemAdmin: {
      userId: systemAdmin!.id,
      role: "system_admin",
    } as ActorContext,
    userIds: users.rows.map((row) => row.id),
    branchIds: branches.rows.map((row) => row.id),
    assignedBranchId: assignedBranch!.id,
    otherBranchId: otherBranch!.id,
    profileIds: profiles.rows.map((row) => row.id),
    staffId: staff.rows[0]!.id,
    studentIds: students.rows.map((row) => row.id),
    lessonIds: lessons.rows.map((row) => row.id),
    paymentIds: payments.rows.map((row) => row.id),
    expectedPaymentId: expectedPayment.rows[0]!.id,
  };
}

async function cleanupStaleFixtures(database: DatabaseService) {
  const users = await database.query<{ id: string }>(
    "select id from app.users where email like 'v4-report-scope-%@example.test'",
  );
  const userIds = users.rows.map((row) => row.id);
  if (userIds.length === 0) return;
  await database.transaction(async (client) => {
    await client.query("set local session_replication_role = replica");
    const profiles = await client.query<{ id: string }>(
      "select id from app.profiles where user_id = any($1::uuid[])",
      [userIds],
    );
    const profileIds = profiles.rows.map((row) => row.id);
    const students = await client.query<{ id: string }>(
      "select id from app.students where profile_id = any($1::uuid[])",
      [profileIds],
    );
    const studentIds = students.rows.map((row) => row.id);
    await client.query(
      "delete from app.expected_payments where student_id = any($1::uuid[])",
      [studentIds],
    );
    await client.query(
      "delete from app.payments where student_id = any($1::uuid[])",
      [studentIds],
    );
    await client.query(
      "delete from app.lessons where student_id = any($1::uuid[])",
      [studentIds],
    );
    await client.query(
      "delete from app.students where id = any($1::uuid[])",
      [studentIds],
    );
    const staff = await client.query<{ id: string }>(
      "select id from app.staff_members where profile_id = any($1::uuid[])",
      [profileIds],
    );
    const staffIds = staff.rows.map((row) => row.id);
    await client.query(
      "delete from app.staff_branch_assignments where staff_member_id = any($1::uuid[])",
      [staffIds],
    );
    await client.query(
      "delete from app.staff_members where id = any($1::uuid[])",
      [staffIds],
    );
    await client.query(
      "delete from app.profiles where id = any($1::uuid[])",
      [profileIds],
    );
    await client.query("delete from app.users where id = any($1::uuid[])", [
      userIds,
    ]);
    await client.query(
      "delete from app.branches where name like 'v4-report-scope-%'",
    );
  });
}

async function cleanupFixture(
  database: DatabaseService,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  await database.transaction(async (client) => {
    await client.query("set local session_replication_role = replica");
    await client.query("delete from app.expected_payments where id = $1", [
      fixture.expectedPaymentId,
    ]);
    await client.query("delete from app.payments where id = any($1::uuid[])", [
      fixture.paymentIds,
    ]);
    await client.query("delete from app.lessons where id = any($1::uuid[])", [
      fixture.lessonIds,
    ]);
    await client.query("delete from app.students where id = any($1::uuid[])", [
      fixture.studentIds,
    ]);
    await client.query(
      "delete from app.staff_branch_assignments where staff_member_id = $1",
      [fixture.staffId],
    );
    await client.query("delete from app.staff_members where id = $1", [
      fixture.staffId,
    ]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.branches where id = any($1::uuid[])", [
      fixture.branchIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
    ]);
  });
}
