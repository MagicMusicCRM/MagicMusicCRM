import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { SharedTaskRepository } from "./shared-task.repository";
import { SharedTaskService } from "./shared-task.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("SharedTask tests require local PostgreSQL.");
}

jest.setTimeout(120_000);

describe("SharedTask API domain (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let tasks: SharedTaskService;
  let fixture: Awaited<ReturnType<typeof createFixture>>;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    tasks = new SharedTaskService(
      new SharedTaskRepository(database),
      new CrmPolicy(),
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new RealtimeBus(),
    );
    fixture = await createFixture(pool);
  });

  afterAll(async () => {
    if (fixture) await cleanupFixture(pool, fixture);
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("deduplicates create and resolves branch membership at request time", async () => {
    const metadata = {
      idempotencyKey: `create-${randomUUID()}`,
      requestId: `request-${randomUUID()}`,
    };
    const dto = {
      title: "Branch work",
      allDay: true,
      startAt: "2026-08-01T00:00:00.000Z",
      audiences: [{ type: "branch" as const, targetId: fixture.branchId }],
    };
    const first = await tasks.create(fixture.director, dto, metadata);
    const replay = await tasks.create(fixture.director, dto, metadata);
    expect(replay).toEqual(first);

    const visible = await tasks.list(fixture.admin, { state: "open" });
    expect(visible.items.map((item) => item.id)).toContain(first.id);

    await pool.query(
      `
        update app.staff_branch_assignments
        set deleted_at = now()
        where id = $1
      `,
      [fixture.assignmentId],
    );
    const hidden = await tasks.list(fixture.admin, { state: "open" });
    expect(hidden.items.map((item) => item.id)).not.toContain(first.id);
  });

  it("returns one stable result when two current audience members close concurrently", async () => {
    const created = await tasks.create(
      fixture.director,
      {
        title: "Close together",
        allDay: false,
        startAt: "2026-08-02T10:00:00.000Z",
        endAt: "2026-08-02T11:00:00.000Z",
        audiences: [
          { type: "user", targetId: fixture.admin.userId },
          { type: "user", targetId: fixture.manager.userId },
        ],
      },
      {
        idempotencyKey: `create-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      },
    );
    const [first, second] = await Promise.all([
      tasks.close(
        fixture.admin,
        created.id,
        { expectedVersion: created.version },
        {
          idempotencyKey: `close-${randomUUID()}`,
          requestId: `close-request-${randomUUID()}`,
        },
      ),
      tasks.close(
        fixture.manager,
        created.id,
        { expectedVersion: created.version },
        {
          idempotencyKey: `close-${randomUUID()}`,
          requestId: `close-request-${randomUUID()}`,
        },
      ),
    ]);
    expect(second).toEqual(first);

    const facts = await pool.query<{
      closes: number;
      audits: number;
      outbox: number;
      state: string;
    }>(
      `
        select
          (select count(*)::int from app.task_closes where task_id = $1) closes,
          (
            select count(*)::int from app.audit_events
            where entity_type = 'shared_task'
              and entity_id = $1::text
              and action = 'workflow.shared_task_closed'
          ) audits,
          (
            select count(*)::int from app.platform_outbox_events
            where aggregate_type = 'workflow:shared-task'
              and aggregate_id = $1::text
              and event_type = 'workflow.task.closed'
          ) outbox,
          (select state from app.shared_tasks where id = $1) state
      `,
      [created.id],
    );
    expect(facts.rows[0]).toEqual({
      closes: 1,
      audits: 1,
      outbox: 1,
      state: "closed",
    });
  });
});

async function createFixture(pool: Pool) {
  const marker = `shared-task-api-${randomUUID()}`;
  const users = await pool.query<{ id: string; role: ActorContext["role"] }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'director', now()),
        ($2, 'admin', now()),
        ($3, 'manager', now())
      returning id, role::text as role
    `,
    [
      `${marker}-director@example.test`,
      `${marker}-admin@example.test`,
      `${marker}-manager@example.test`,
    ],
  );
  const [directorRow, adminRow, managerRow] = users.rows;
  const branch = await pool.query<{ id: string }>(
    "insert into app.branches (name) values ($1) returning id",
    [`${marker}-branch`],
  );
  const profile = await pool.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name)
      values ($1, $2)
      returning id
    `,
    [adminRow!.id, marker],
  );
  const staff = await pool.query<{ id: string }>(
    `
      insert into app.staff_members (profile_id, role)
      values ($1, 'admin')
      returning id
    `,
    [profile.rows[0]!.id],
  );
  await pool.query(
    `
      insert into app.user_crm_links (
        user_id, entity_type, entity_id, link_source
      )
      values ($1, 'staff', $2, 'manual_email')
    `,
    [adminRow!.id, staff.rows[0]!.id],
  );
  const assignment = await pool.query<{ id: string }>(
    `
      insert into app.staff_branch_assignments (staff_member_id, branch_id)
      values ($1, $2)
      returning id
    `,
    [staff.rows[0]!.id, branch.rows[0]!.id],
  );
  return {
    marker,
    userIds: users.rows.map((row) => row.id),
    branchId: branch.rows[0]!.id,
    profileId: profile.rows[0]!.id,
    staffId: staff.rows[0]!.id,
    assignmentId: assignment.rows[0]!.id,
    director: { userId: directorRow!.id, role: "director" } as ActorContext,
    admin: { userId: adminRow!.id, role: "admin" } as ActorContext,
    manager: { userId: managerRow!.id, role: "manager" } as ActorContext,
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
    const tasks = await client.query<{ id: string }>(
      "select id from app.shared_tasks where created_by = any($1::uuid[])",
      [fixture.userIds],
    );
    const taskIds = tasks.rows.map((row) => row.id);
    await client.query(
      "delete from app.task_audience_resolution_audits where task_id = any($1::uuid[])",
      [taskIds],
    );
    await client.query(
      "delete from app.shared_task_reminders where task_id = any($1::uuid[])",
      [taskIds],
    );
    await client.query(
      "delete from app.task_closes where task_id = any($1::uuid[])",
      [taskIds],
    );
    await client.query(
      "delete from app.task_audiences where task_id = any($1::uuid[])",
      [taskIds],
    );
    await client.query(
      "delete from app.shared_tasks where id = any($1::uuid[])",
      [taskIds],
    );
    await client.query(
      `
        delete from app.platform_outbox_events
        where aggregate_type = 'workflow:shared-task'
          and aggregate_id = any($1::text[])
      `,
      [taskIds],
    );
    await client.query(
      `
        delete from app.audit_events
        where entity_type = 'shared_task' and entity_id = any($1::text[])
      `,
      [taskIds],
    );
    await client.query(
      `
        delete from app.idempotency_records
        where actor_key = any($1::text[])
          and operation like 'workflow.shared-task.%'
      `,
      [fixture.userIds],
    );
    await client.query(
      `
        delete from app.aggregate_versions
        where aggregate_type = 'workflow:shared-task'
          and aggregate_id = any($1::text[])
      `,
      [taskIds],
    );
    await client.query(
      "delete from app.staff_branch_assignments where staff_member_id = $1",
      [fixture.staffId],
    );
    await client.query(
      "delete from app.user_crm_links where user_id = any($1::uuid[])",
      [fixture.userIds],
    );
    await client.query("delete from app.staff_members where id = $1", [
      fixture.staffId,
    ]);
    await client.query("delete from app.profiles where id = $1", [
      fixture.profileId,
    ]);
    await client.query("delete from app.branches where id = $1", [
      fixture.branchId,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
    ]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}
