import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { SharedTaskRepository } from "./shared-task.repository";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("SharedTask migration tests require local PostgreSQL.");
}

jest.setTimeout(120_000);

describe("SharedTask conservative migration (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let runner: MigrationRunner;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    runner = new MigrationRunner(pool);
    await runner.up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
  });

  afterAll(async () => {
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("merges only proven exact copies and preserves ambiguous rows separately", async () => {
    await cleanupStaleRuntimeFixtures(pool);
    await rollbackThrough(runner, "0092_shared_tasks_audience_schema");
    let migrationApplied = false;
    const fixture = await createLegacyFixture(pool);
    try {
      await runner.up();
      migrationApplied = true;

      const evidence = await new SharedTaskRepository(database).migrationEvidence(
        fixture.taskIds,
      );
      expect(evidence.rows).toHaveLength(4);
      const exact = evidence.rows.filter((row) =>
        fixture.exactTaskIds.includes(row.legacy_task_id),
      );
      const ambiguous = evidence.rows.filter((row) =>
        fixture.ambiguousTaskIds.includes(row.legacy_task_id),
      );
      expect(exact.map((row) => row.merge_proof)).toEqual([
        "exact_common_origin",
        "exact_common_origin",
      ]);
      expect(new Set(exact.map((row) => row.shared_task_id)).size).toBe(1);
      expect(ambiguous.map((row) => row.merge_proof)).toEqual([
        "separate_ambiguous",
        "separate_ambiguous",
      ]);
      expect(new Set(ambiguous.map((row) => row.shared_task_id)).size).toBe(2);

      const counts = await pool.query<{
        shared_tasks: number;
        audiences: number;
        legacy_links: number;
      }>(
        `
          select
            (
              select count(*)::int
              from app.shared_tasks
              where id = any($1::uuid[])
            ) as shared_tasks,
            (
              select count(*)::int
              from app.task_audiences
              where task_id = any($1::uuid[])
            ) as audiences,
            (
              select count(*)::int
              from app.shared_task_legacy_links
              where legacy_task_id = any($2::uuid[])
            ) as legacy_links
        `,
        [
          Array.from(new Set(evidence.rows.map((row) => row.shared_task_id))),
          fixture.taskIds,
        ],
      );
      expect(counts.rows[0]).toEqual({
        shared_tasks: 3,
        audiences: 4,
        legacy_links: 4,
      });

      const audit = await pool.query<{ id: string }>(
        `
          insert into app.task_audience_resolution_audits (
            task_id,
            action,
            actor_user_id,
            matched_audience_id,
            matched_selector,
            membership_version,
            membership_at,
            request_id
          )
          select
            audience.task_id,
            'list',
            $1,
            audience.id,
            jsonb_build_object(
              'type', audience.audience_type,
              'targetId', audience.target_id
            ),
            'fixture-v1',
            now(),
            $2
          from app.task_audiences audience
          where audience.task_id = $3
          order by audience.id
          limit 1
          returning id
        `,
        [
          fixture.userIds[0],
          `shared-task-migration-${randomUUID()}`,
          exact[0]!.shared_task_id,
        ],
      );
      await expect(
        pool.query(
          `
            update app.task_audience_resolution_audits
            set membership_version = 'tampered'
            where id = $1
          `,
          [audit.rows[0]!.id],
        ),
      ).rejects.toMatchObject({ code: "23514" });
    } finally {
      if (migrationApplied) {
        await cleanupFixture(pool, fixture);
        await rollbackThrough(runner, "0092_shared_tasks_audience_schema");
      } else {
        await cleanupLegacyFixture(pool, fixture);
      }
      await runner.up();
    }
  });
});

async function rollbackThrough(runner: MigrationRunner, targetId: string) {
  while (true) {
    const reverted = await runner.down();
    if (!reverted) {
      throw new Error(`Migration ${targetId} is not applied.`);
    }
    if (reverted === targetId) return;
  }
}

async function cleanupStaleRuntimeFixtures(pool: Pool) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    const users = await client.query<{ id: string }>(
      `
        select id
        from app.users
        where email like 'shared-task-api-%@example.test'
           or email like 'task-reminders-%@example.test'
      `,
    );
    const userIds = users.rows.map((row) => row.id);
    if (userIds.length === 0) {
      await client.query("commit");
      return;
    }
    const tasks = await client.query<{ id: string }>(
      `
        select id
        from app.shared_tasks
        where origin = 'runtime' and created_by = any($1::uuid[])
      `,
      [userIds],
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
        where entity_type = 'shared_task'
          and entity_id = any($1::text[])
      `,
      [taskIds],
    );
    await client.query(
      `
        delete from app.idempotency_records
        where actor_key = any($1::text[])
          and operation like 'workflow.shared-task.%'
      `,
      [userIds],
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
      `
        delete from app.staff_branch_assignments
        where staff_member_id in (
          select staff.id
          from app.staff_members staff
          join app.profiles profile on profile.id = staff.profile_id
          where profile.user_id = any($1::uuid[])
        )
      `,
      [userIds],
    );
    await client.query(
      "delete from app.user_crm_links where user_id = any($1::uuid[])",
      [userIds],
    );
    await client.query(
      `
        delete from app.staff_members
        where profile_id in (
          select id from app.profiles where user_id = any($1::uuid[])
        )
      `,
      [userIds],
    );
    await client.query(
      "delete from app.profiles where user_id = any($1::uuid[])",
      [userIds],
    );
    await client.query(
      `
        delete from app.branches
        where name like 'shared-task-api-%-branch'
      `,
    );
    await client.query("delete from app.users where id = any($1::uuid[])", [
      userIds,
    ]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function createLegacyFixture(pool: Pool) {
  const marker = `shared-task-migration-${randomUUID()}`;
  const users = await pool.query<{ id: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values
        ($1, 'manager', now()),
        ($2, 'admin', now()),
        ($3, 'manager', now()),
        ($4, 'admin', now())
      returning id
    `,
    [
      `${marker}-one@example.test`,
      `${marker}-two@example.test`,
      `${marker}-three@example.test`,
      `${marker}-four@example.test`,
    ],
  );
  const userIds = users.rows.map((row) => row.id);
  const entityId = randomUUID();
  const exact = await pool.query<{ id: string }>(
    `
      insert into app.tasks (
        entity_type,
        entity_id,
        title,
        description,
        status,
        priority,
        due_at,
        due_all_day,
        assigned_to,
        created_by,
        created_at,
        updated_at
      )
      values
        (
          'profile', $1, $2, 'same payload', 'open', 'high',
          '2026-08-01T08:00:00Z', false, $3, $3,
          '2026-07-29T10:00:00.000000Z',
          '2026-07-29T10:00:00.000000Z'
        ),
        (
          'profile', $1, $2, 'same payload', 'open', 'high',
          '2026-08-01T08:00:00Z', false, $4, $3,
          '2026-07-29T10:00:00.000000Z',
          '2026-07-29T10:00:00.000000Z'
        )
      returning id
    `,
    [entityId, `${marker}-exact`, userIds[0], userIds[1]],
  );
  const ambiguous = await pool.query<{ id: string }>(
    `
      insert into app.tasks (
        entity_type,
        entity_id,
        title,
        description,
        status,
        priority,
        due_at,
        due_all_day,
        assigned_to,
        created_by,
        created_at,
        updated_at
      )
      values
        (
          'profile', $1, $2, 'ambiguous payload', 'open', 'medium',
          '2026-08-02T08:00:00Z', false, $3, $3,
          '2026-07-29T11:00:00.000000Z',
          '2026-07-29T11:00:00.000000Z'
        ),
        (
          'profile', $1, $2, 'ambiguous payload', 'open', 'medium',
          '2026-08-02T08:00:00Z', false, $4, $3,
          '2026-07-29T11:00:00.001000Z',
          '2026-07-29T11:00:00.001000Z'
        )
      returning id
    `,
    [entityId, `${marker}-ambiguous`, userIds[2], userIds[3]],
  );
  const exactTaskIds = exact.rows.map((row) => row.id);
  const ambiguousTaskIds = ambiguous.rows.map((row) => row.id);
  return {
    marker,
    userIds,
    exactTaskIds,
    ambiguousTaskIds,
    taskIds: [...exactTaskIds, ...ambiguousTaskIds],
  };
}

async function cleanupFixture(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createLegacyFixture>>,
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local session_replication_role = replica");
    const shared = await client.query<{ id: string }>(
      `
        select shared_task_id as id
        from app.shared_task_legacy_links
        where legacy_task_id = any($1::uuid[])
      `,
      [fixture.taskIds],
    );
    const sharedTaskIds = Array.from(
      new Set(shared.rows.map((row) => row.id)),
    );
    await client.query(
      "delete from app.task_audience_resolution_audits where task_id = any($1::uuid[])",
      [sharedTaskIds],
    );
    await client.query(
      "delete from app.shared_task_legacy_links where legacy_task_id = any($1::uuid[])",
      [fixture.taskIds],
    );
    await client.query(
      "delete from app.task_audiences where task_id = any($1::uuid[])",
      [sharedTaskIds],
    );
    await client.query(
      "delete from app.shared_tasks where id = any($1::uuid[])",
      [sharedTaskIds],
    );
    await client.query("delete from app.tasks where id = any($1::uuid[])", [
      fixture.taskIds,
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

async function cleanupLegacyFixture(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createLegacyFixture>>,
) {
  await pool.query("delete from app.tasks where id = any($1::uuid[])", [
    fixture.taskIds,
  ]);
  await pool.query("delete from app.users where id = any($1::uuid[])", [
    fixture.userIds,
  ]);
}
