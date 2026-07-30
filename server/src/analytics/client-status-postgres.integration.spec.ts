import { ForbiddenException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CapabilityRequestAuthorizer } from "../access-control/capability-request-authorizer";
import { ClientStatusReadService } from "./client-status-read.service";
import { ClientStatusFilterQuery } from "./dto/client-status-filter.query";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const parsedDatabaseUrl = new URL(databaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    parsedDatabaseUrl.hostname,
  )
) {
  throw new Error("Client status tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("ClientStatusReadService (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: ClientStatusReadService;
  let authorizer: CapabilityRequestAuthorizer;
  let fixture: Awaited<ReturnType<typeof createFixture>>;

  beforeAll(async () => {
    database = new DatabaseService(
      new ConfigService({ DATABASE_URL: databaseUrl }),
    );
    service = new ClientStatusReadService(database);
    authorizer = new CapabilityRequestAuthorizer(database);
    await cleanupStaleFixtures(database);
    fixture = await createFixture(database);
  });

  afterAll(async () => {
    if (fixture) await cleanupFixture(database, fixture);
    await database.onModuleDestroy();
  });

  it("uses one scoped filter for summary and drilldown totals", async () => {
    const managerSummary = await service.summary(
      fixture.manager,
      new ClientStatusFilterQuery(),
    );
    expect(managerSummary.total).toBe(2);
    expect(managerSummary.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          clientType: "lead",
          status: "new",
          count: 1,
        }),
        expect.objectContaining({
          clientType: "student",
          status: "active",
          count: 1,
        }),
      ]),
    );

    for (const item of managerSummary.items) {
      const filter = item.drilldown.optionalFocus!.filter;
      const list = await service.list(fixture.manager, {
        ...new ClientStatusFilterQuery(),
        clientType: filter.clientType,
        status: filter.status,
      });
      expect(list.total).toBe(item.count);
      expect(list.filter).toEqual(filter);
      expect(list.items).toHaveLength(item.count);
    }

    const director = await service.list(
      fixture.director,
      new ClientStatusFilterQuery(),
    );
    expect(director.total).toBe(4);
    expect(
      director.items.filter((item) => item.branchId === fixture.otherBranchId),
    ).toHaveLength(2);
  });

  it("fails closed for admin and for a Director-disabled Manager override", async () => {
    await expect(
      service.summary(fixture.admin, new ClientStatusFilterQuery()),
    ).rejects.toBeInstanceOf(ForbiddenException);

    await database.query(
      `
        insert into app.user_capability_overrides (
          user_id,
          capability_key,
          capability_version,
          effect,
          reason_code,
          actor_user_id
        )
        values ($1, 'report.status.read', 1, 'deny', 'test.disabled', $2)
      `,
      [fixture.manager.userId, fixture.director.userId],
    );
    await expect(
      authorizer.authorize(
        fixture.manager,
        "GET",
        "/analytics/v4/client-status/summary",
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });
});

async function createFixture(database: DatabaseService) {
  const marker = `v4-report-status-${randomUUID()}`;
  const users = await database.query<{ id: string; role: ActorContext["role"] }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'manager', now()),
        ($2, 'director', now()),
        ($3, 'admin', now()),
        ($4, 'client', now()),
        ($5, 'client', now())
      returning id, role::text as role
    `,
    [
      `${marker}-manager@example.test`,
      `${marker}-director@example.test`,
      `${marker}-admin@example.test`,
      `${marker}-student-a@example.test`,
      `${marker}-student-b@example.test`,
    ],
  );
  const [managerUser, directorUser, adminUser, studentUserA, studentUserB] =
    users.rows;
  const branches = await database.query<{ id: string }>(
    `
      insert into app.branches (name)
      values ($1), ($2)
      returning id
    `,
    [`${marker}-assigned`, `${marker}-other`],
  );
  const [assignedBranch, otherBranch] = branches.rows;
  const managerProfile = await database.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name)
      values ($1, $2)
      returning id
    `,
    [managerUser!.id, marker],
  );
  const managerStaff = await database.query<{ id: string }>(
    `
      insert into app.staff_members (profile_id, role)
      values ($1, 'manager')
      returning id
    `,
    [managerProfile.rows[0]!.id],
  );
  await database.query(
    `
      insert into app.staff_branch_assignments (staff_member_id, branch_id)
      values ($1, $2)
    `,
    [managerStaff.rows[0]!.id, assignedBranch!.id],
  );

  const studentProfiles = await database.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values ($1, $3, 'Ученик'), ($2, $4, 'Ученик')
      returning id
    `,
    [
      studentUserA!.id,
      studentUserB!.id,
      `${marker}-assigned`,
      `${marker}-other`,
    ],
  );
  const students = await database.query<{ id: string }>(
    `
      insert into app.students (profile_id, status, branch_id)
      values ($1, 'active', $3), ($2, 'active', $4)
      returning id
    `,
    [
      studentProfiles.rows[0]!.id,
      studentProfiles.rows[1]!.id,
      assignedBranch!.id,
      otherBranch!.id,
    ],
  );
  const leads = await database.query<{ id: string }>(
    `
      insert into app.leads (first_name, last_name, phone, branch_id)
      values
        ($1, 'Лид', '+79990000001', $3),
        ($2, 'Лид', '+79990000002', $4)
      returning id
    `,
    [`${marker}-assigned`, `${marker}-other`, assignedBranch!.id, otherBranch!.id],
  );

  return {
    manager: { userId: managerUser!.id, role: "manager" } as ActorContext,
    director: { userId: directorUser!.id, role: "director" } as ActorContext,
    admin: { userId: adminUser!.id, role: "admin" } as ActorContext,
    userIds: users.rows.map((row) => row.id),
    profileIds: [
      managerProfile.rows[0]!.id,
      ...studentProfiles.rows.map((row) => row.id),
    ],
    staffId: managerStaff.rows[0]!.id,
    branchIds: branches.rows.map((row) => row.id),
    otherBranchId: otherBranch!.id,
    studentIds: students.rows.map((row) => row.id),
    leadIds: leads.rows.map((row) => row.id),
  };
}

async function cleanupStaleFixtures(database: DatabaseService) {
  const staleUsers = await database.query<{ id: string }>(
    "select id from app.users where email like 'v4-report-status-%@example.test'",
  );
  const userIds = staleUsers.rows.map((row) => row.id);
  if (userIds.length === 0) return;
  await database.transaction(async (client) => {
    await client.query("set local session_replication_role = replica");
    const profiles = await client.query<{ id: string }>(
      "select id from app.profiles where user_id = any($1::uuid[])",
      [userIds],
    );
    const profileIds = profiles.rows.map((row) => row.id);
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
      "delete from app.branches where name like 'v4-report-status-%'",
    );
  });
}

async function cleanupFixture(
  database: DatabaseService,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  await database.transaction(async (client) => {
    await client.query("set local session_replication_role = replica");
    await client.query(
      "delete from app.user_capability_overrides where user_id = any($1::uuid[]) or actor_user_id = any($1::uuid[])",
      [fixture.userIds],
    );
    await client.query("delete from app.leads where id = any($1::uuid[])", [
      fixture.leadIds,
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
