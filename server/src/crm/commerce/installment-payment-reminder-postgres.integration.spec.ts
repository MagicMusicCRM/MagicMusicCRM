import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { NotificationsService } from "../../notifications/notifications.service";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { InstallmentDueWorker } from "./installment-due.worker";
import { PaymentLifecycleRepository } from "./payment-lifecycle.repository";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Installment reminder tests require local PostgreSQL.");
}

const marker = `installment-reminder-${randomUUID()}`;

jest.setTimeout(120_000);

describe("Effective installment payment reminders (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let repository: PaymentLifecycleRepository;
  let reservations: SubscriptionReservationService;
  let fixture: Awaited<ReturnType<typeof createFixture>>;
  let notifyUser: jest.Mock;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    repository = new PaymentLifecycleRepository(
      database,
      new PlatformIntegrityRepository(),
    );
    reservations = new SubscriptionReservationService(database, {
      emitCrmChanged: jest.fn(),
      emitFinanceChanged: jest.fn(),
    } as unknown as RealtimeBus);
    fixture = await createFixture(pool);
    notifyUser = jest.fn().mockResolvedValue({ notificationId: "test" });
  });

  afterAll(async () => {
    if (fixture) await cleanupFixture(pool, fixture);
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  function createWorker() {
    return new InstallmentDueWorker(
      repository,
      reservations,
      { notifyUser } as unknown as NotificationsService,
    );
  }

  it("uses the branch override, targets the payer and deduplicates concurrent ticks", async () => {
    const beforeWindow = await createWorker().runReminderOnce(
      new Date("2030-01-04T08:59:59.000Z"),
      { limit: 20 },
    );
    expect(beforeWindow).toMatchObject({ materialized: 0, claimed: 0 });

    const [first, concurrent] = await Promise.all([
      createWorker().runReminderOnce(new Date("2030-01-05T09:00:00.000Z"), {
        limit: 20,
      }),
      createWorker().runReminderOnce(new Date("2030-01-05T09:00:00.000Z"), {
        limit: 20,
      }),
    ]);
    expect(first.delivered + concurrent.delivered).toBe(1);
    expect(first.materialized + concurrent.materialized).toBe(1);
    expect(notifyUser).toHaveBeenCalledTimes(1);
    expect(notifyUser).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: fixture.payerUserId,
        title: "Напоминание об оплате",
        channels: ["in_app", "push"],
        data: {
          entityType: "subscription",
          entityId: fixture.subscriptionId,
        },
      }),
    );

    const persisted = await pool.query<{
      status: string;
      attempts: number;
      reminder_days: number;
      recipient_user_ids: string[];
    }>(
      `select status, attempts, reminder_days, recipient_user_ids
       from app.installment_payment_reminders
       where installment_id = $1`,
      [fixture.installmentId],
    );
    expect(persisted.rows).toEqual([
      {
        status: "delivered",
        attempts: 1,
        reminder_days: 5,
        recipient_user_ids: [fixture.payerUserId],
      },
    ]);

    await createWorker().runReminderOnce(
      new Date("2030-01-06T09:00:00.000Z"),
      { limit: 20 },
    );
    expect(notifyUser).toHaveBeenCalledTimes(1);
  });

  it("retries with the same notification identity and then marks delivered", async () => {
    const second = await pool.query<{ id: string }>(
      `insert into app.subscription_installments (
         issued_subscription_id, installment_number, due_at,
         amount_minor, currency_code
       ) values ($1, 2, '2030-02-10T09:00:00.000Z', 250000, 'RUB')
       returning id`,
      [fixture.subscriptionId],
    );
    fixture.extraInstallmentIds.push(second.rows[0]!.id);
    notifyUser.mockRejectedValueOnce(new Error("provider unavailable"));
    const worker = createWorker();
    const failed = await worker.runReminderOnce(
      new Date("2030-02-05T09:00:00.000Z"),
      {
        limit: 20,
        maxAttempts: 3,
        backoffBaseSeconds: 0,
        backoffCapSeconds: 0,
      },
    );
    expect(failed).toMatchObject({ materialized: 1, retried: 1, delivered: 0 });
    const firstNotificationId = notifyUser.mock.calls.at(-1)?.[0]
      ?.notificationId as string;

    const recovered = await worker.runReminderOnce(
      new Date("2030-02-05T09:00:01.000Z"),
      {
        limit: 20,
        maxAttempts: 3,
        backoffBaseSeconds: 0,
        backoffCapSeconds: 0,
      },
    );
    expect(recovered).toMatchObject({ materialized: 0, delivered: 1 });
    expect(notifyUser.mock.calls.at(-1)?.[0]?.notificationId).toBe(
      firstNotificationId,
    );
    await expect(
      pool.query(
        `select status, attempts, last_error
         from app.installment_payment_reminders
         where installment_id = $1`,
        [second.rows[0]!.id],
      ),
    ).resolves.toMatchObject({
      rows: [{ status: "delivered", attempts: 2, last_error: null }],
    });
  });
});

async function createFixture(pool: Pool) {
  const client = await pool.connect();
  await client.query("begin");
  try {
    const branch = await client.query<{ id: string }>(
      `insert into app.branches (name, timezone_name)
       values ($1, 'Europe/Moscow') returning id`,
      [`${marker}-branch`],
    );
    const userIds: string[] = [];
    const studentIds: string[] = [];
    const profileIds: string[] = [];
    for (const label of ["recipient", "payer"] as const) {
      const user = await client.query<{ id: string }>(
        `insert into app.users (email, role, email_verified_at, is_app_account)
         values ($1, 'client', now(), true) returning id`,
        [`${marker}-${label}@example.test`],
      );
      const profile = await client.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name)
         values ($1, $2, 'Reminder') returning id`,
        [user.rows[0]!.id, label],
      );
      const student = await client.query<{ id: string }>(
        `insert into app.students (profile_id, status, branch_id)
         values ($1, 'active', $2) returning id`,
        [profile.rows[0]!.id, branch.rows[0]!.id],
      );
      userIds.push(user.rows[0]!.id);
      profileIds.push(profile.rows[0]!.id);
      studentIds.push(student.rows[0]!.id);
    }
    const school = await client.query<{ effective_snapshot: Record<string, unknown> }>(
      `select effective_snapshot from app.crm_configuration_revisions
       where branch_id is null order by version desc limit 1`,
    );
    const schoolSnapshot = school.rows[0]!.effective_snapshot;
    const businessSettings = (
      schoolSnapshot.businessSettings as Array<Record<string, unknown>>
    ).map((setting) =>
      setting.key === "payment_reminder_days"
        ? { ...setting, value: 5 }
        : setting,
    );
    const effectiveSnapshot = { ...schoolSnapshot, businessSettings };
    const branchPatch = {
      businessSettings: businessSettings.filter(
        (setting) => setting.key === "payment_reminder_days",
      ),
    };
    await client.query(
      `insert into app.crm_configuration_revisions (
         branch_id, version, patch, effective_snapshot, impact, reason
       ) values ($1, 1, $2::jsonb, $3::jsonb, '{}'::jsonb, $4)`,
      [
        branch.rows[0]!.id,
        JSON.stringify(branchPatch),
        JSON.stringify(effectiveSnapshot),
        "Payment reminder branch override test",
      ],
    );
    const subscription = await client.query<{ id: string }>(
      `insert into app.subscriptions (
         student_id, lessons_total, status, payer_student_id,
         funding_mode, purchase_reason
       ) values ($1, 10, 'active', $2, 'installment', $3)
       returning id`,
      [studentIds[0], studentIds[1], "Payer differs from recipient"],
    );
    const installment = await client.query<{ id: string }>(
      `insert into app.subscription_installments (
         issued_subscription_id, installment_number, due_at,
         amount_minor, currency_code
       ) values ($1, 1, '2030-01-10T09:00:00.000Z', 100000, 'RUB')
       returning id`,
      [subscription.rows[0]!.id],
    );
    await client.query("commit");
    return {
      branchId: branch.rows[0]!.id,
      userIds,
      profileIds,
      studentIds,
      recipientUserId: userIds[0]!,
      payerUserId: userIds[1]!,
      subscriptionId: subscription.rows[0]!.id,
      installmentId: installment.rows[0]!.id,
      extraInstallmentIds: [] as string[],
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function cleanupFixture(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
) {
  const client = await pool.connect();
  await client.query("begin");
  try {
    await client.query("set local session_replication_role = replica");
    const installmentIds = [
      fixture.installmentId,
      ...fixture.extraInstallmentIds,
    ];
    await client.query(
      `delete from app.installment_payment_reminders
       where installment_id = any($1::uuid[])`,
      [installmentIds],
    );
    await client.query(
      `delete from app.subscription_installments
       where id = any($1::uuid[])`,
      [installmentIds],
    );
    await client.query("delete from app.subscriptions where id = $1", [
      fixture.subscriptionId,
    ]);
    await client.query(
      "delete from app.crm_configuration_revisions where branch_id = $1",
      [fixture.branchId],
    );
    await client.query("delete from app.students where id = any($1::uuid[])", [
      fixture.studentIds,
    ]);
    await client.query("delete from app.profiles where id = any($1::uuid[])", [
      fixture.profileIds,
    ]);
    await client.query("delete from app.users where id = any($1::uuid[])", [
      fixture.userIds,
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
