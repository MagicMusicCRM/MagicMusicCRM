import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { NotificationsService } from "../../notifications/notifications.service";
import { NotificationsPolicy } from "../../notifications/notifications.policy";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { SharedTaskReminderWorker } from "./shared-task-reminder.worker";
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
  throw new Error("Task reminder tests require local PostgreSQL.");
}

jest.setTimeout(120_000);

describe("Shared task reminders and realtime close (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let fixture: Awaited<ReturnType<typeof createFixture>>;
  let repository: SharedTaskRepository;
  let tasks: SharedTaskService;
  let worker: SharedTaskReminderWorker;
  let notifyUser: jest.Mock;
  let emitCrmChanged: jest.Mock;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    fixture = await createFixture(pool);
    repository = new SharedTaskRepository(database);
    notifyUser = jest.fn();
    emitCrmChanged = jest.fn();
    tasks = new SharedTaskService(
      repository,
      new CrmPolicy(),
      new PlatformIntegrityService(database, new PlatformIntegrityRepository()),
      { emitCrmChanged } as unknown as RealtimeBus,
    );
    worker = new SharedTaskReminderWorker(repository, {
      notifyUser,
    } as unknown as NotificationsService);
  });

  afterAll(async () => {
    if (fixture) await cleanupFixture(pool, fixture);
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("retries a total provider outage, falls back to in-app and removes pending reminders on close", async () => {
    const task = await tasks.create(
      fixture.director,
      {
        title: "Reminder resilience",
        allDay: false,
        startAt: "2026-08-03T10:00:00.000Z",
        endAt: "2026-08-03T11:00:00.000Z",
        audiences: [
          { type: "user", targetId: fixture.admin.userId },
          { type: "user", targetId: fixture.manager.userId },
        ],
        reminders: [
          { dueAt: "2020-01-01T00:00:00.000Z", channel: "email" },
          { dueAt: "2030-01-01T00:00:00.000Z", channel: "in_app" },
        ],
      },
      {
        idempotencyKey: `create-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      },
    );

    notifyUser.mockRejectedValue(new Error("providers unavailable"));
    const failed = await worker.dispatchDue("worker-a", {
      backoffBaseSeconds: 1,
      backoffCapSeconds: 1,
    });
    expect(failed).toMatchObject({ claimed: 1, delivered: 0, retried: 1 });
    const pending = await pool.query<{ status: string; attempts: number }>(
      `
        update app.shared_task_reminders
        set next_attempt_at = now() - interval '1 second'
        where task_id = $1 and due_at < now()
        returning status, attempts
      `,
      [task.id],
    );
    expect(pending.rows[0]).toMatchObject({ status: "pending", attempts: 1 });

    notifyUser.mockImplementation((input: { channels?: string[] }) =>
      input.channels?.[0] === "email"
        ? Promise.reject(new Error("email provider unavailable"))
        : Promise.resolve({ notificationId: randomUUID() }),
    );
    const [winner, overlapping] = await Promise.all([
      worker.dispatchDue("worker-b"),
      worker.dispatchDue("worker-c"),
    ]);
    expect(winner.claimed + overlapping.claimed).toBe(1);
    expect(winner.delivered + overlapping.delivered).toBe(1);
    expect(notifyUser).toHaveBeenCalledWith(
      expect.objectContaining({ channels: ["in_app"] }),
    );

    const closeStartedAt = Date.now();
    await tasks.close(
      fixture.manager,
      task.id,
      { expectedVersion: task.version },
      {
        idempotencyKey: `close-${randomUUID()}`,
        requestId: `close-request-${randomUUID()}`,
      },
    );
    expect(Date.now() - closeStartedAt).toBeLessThan(2000);
    expect(emitCrmChanged).toHaveBeenLastCalledWith(
      expect.objectContaining({
        entity: "task",
        action: "deleted",
        id: task.id,
      }),
    );
    const reminderStates = await pool.query<{ status: string; count: number }>(
      `
        select status, count(*)::int count
        from app.shared_task_reminders
        where task_id = $1
        group by status
        order by status
      `,
      [task.id],
    );
    expect(reminderStates.rows).toEqual([
      { status: "cancelled", count: 1 },
      { status: "delivered", count: 1 },
    ]);
  });

  it("deduplicates a partially retried reminder, opens its task and persists read state", async () => {
    const createNotifications = () =>
      new NotificationsService(
        database,
        { record: jest.fn().mockResolvedValue(undefined) } as never,
        new NotificationsPolicy(),
        {
          dispatchPendingEmails: jest
            .fn()
            .mockResolvedValue({ processed: 0, failed: 0 }),
          dispatchPendingPush: jest
            .fn()
            .mockResolvedValue({ processed: 0, failed: 0 }),
        } as never,
        {} as never,
        { emitCrmChanged: jest.fn() } as never,
      );
    const notifications = createNotifications();
    let deliveryCall = 0;
    const retryingWorker = new SharedTaskReminderWorker(repository, {
      notifyUser: async (
        input: Parameters<NotificationsService["notifyUser"]>[0],
      ) => {
        deliveryCall += 1;
        if (deliveryCall === 2) throw new Error("recipient provider outage");
        return notifications.notifyUser(input);
      },
    } as unknown as NotificationsService);
    const task = await tasks.create(
      fixture.manager,
      {
        title: "UAT-102 exact reminder recipients",
        allDay: false,
        startAt: "2026-08-13T10:00:00.000Z",
        endAt: "2026-08-13T11:00:00.000Z",
        audiences: [
          { type: "user", targetId: fixture.admin.userId },
          { type: "user", targetId: fixture.manager.userId },
        ],
        reminders: [{ dueAt: "2020-01-01T00:00:00.000Z", channel: "in_app" }],
      },
      {
        idempotencyKey: `create-${randomUUID()}`,
        requestId: `request-${randomUUID()}`,
      },
    );

    await expect(
      retryingWorker.dispatchDue("partial-worker", {
        backoffBaseSeconds: 1,
        backoffCapSeconds: 1,
      }),
    ).resolves.toMatchObject({ claimed: 1, delivered: 0, retried: 1 });
    await pool.query(
      `
        update app.shared_task_reminders
        set next_attempt_at = now() - interval '1 second'
        where task_id = $1
      `,
      [task.id],
    );
    await expect(
      retryingWorker.dispatchDue("retry-worker"),
    ).resolves.toMatchObject({ claimed: 1, delivered: 1, retried: 0 });

    const facts = await pool.query<{
      notifications: number;
      recipients: number;
      distinct_recipients: number;
      routed_notifications: number;
    }>(
      `
        select
          count(distinct notification.id)::int as notifications,
          count(recipient.id)::int as recipients,
          count(distinct recipient.user_id)::int as distinct_recipients,
          count(distinct notification.id) filter (
            where notification.data->>'entityType' = 'task'
              and notification.data->>'entityId' = $1::text
          )::int as routed_notifications
        from app.notifications notification
        join app.notification_recipients recipient
          on recipient.notification_id = notification.id
        where notification.data->>'entityId' = $1::text
      `,
      [task.id],
    );
    expect(facts.rows[0]).toEqual({
      notifications: 2,
      recipients: 2,
      distinct_recipients: 2,
      routed_notifications: 2,
    });

    const adminList = await notifications.list(fixture.admin, { limit: 50 });
    const adminNotification = adminList.items.find(
      (item) => item.data?.entityId === task.id,
    );
    expect(adminNotification).toMatchObject({
      isRead: false,
      data: { entityType: "task", entityId: task.id },
    });
    await notifications.markRead(fixture.admin, adminNotification!.id);
    const afterRestart = await createNotifications().list(fixture.admin, {
      limit: 50,
    });
    expect(
      afterRestart.items.find((item) => item.id === adminNotification!.id),
    ).toMatchObject({ isRead: true });
  });
});

async function createFixture(pool: Pool) {
  const marker = `task-reminders-${randomUUID()}`;
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
  return {
    userIds: users.rows.map((row) => row.id),
    director: {
      userId: users.rows[0]!.id,
      role: "director",
    } as ActorContext,
    admin: {
      userId: users.rows[1]!.id,
      role: "admin",
    } as ActorContext,
    manager: {
      userId: users.rows[2]!.id,
      role: "manager",
    } as ActorContext,
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
      `
        delete from app.notifications
        where data->>'entityType' = 'task'
          and data->>'entityId' = any($1::text[])
      `,
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
