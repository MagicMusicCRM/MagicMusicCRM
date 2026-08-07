import {
  ConflictException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ActualPaymentService } from "./actual-payment.service";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import { PaymentLifecycleRepository } from "./payment-lifecycle.repository";
import { PaymentLifecycleService } from "./payment-lifecycle.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionIssueService } from "./subscription-issue.service";
import { SubscriptionLifecycleRepository } from "./subscription-lifecycle.repository";
import { SubscriptionLifecycleService } from "./subscription-lifecycle.service";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Subscription cancel tests require local PostgreSQL.");
}

const marker = `v4-subscription-cancel-${randomUUID()}`;
const previewSecret = "cancel-preview-test-secret-at-least-32-bytes";

jest.setTimeout(120_000);

describe("Subscription cancellation preview/confirm", () => {
  let pool: Pool;
  let database: DatabaseService;
  let issueService: SubscriptionIssueService;
  let paymentService: ActualPaymentService;
  let lifecycleService: SubscriptionLifecycleService;
  let fixture: Awaited<ReturnType<typeof createFixture>>;
  let actor: ActorContext;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    const issueRepository = new SubscriptionIssueRepository(database);
    const policy = new CrmPolicy();
    const integrity = new PlatformIntegrityService(
      database,
      new PlatformIntegrityRepository(),
    );
    const reservations = new SubscriptionReservationService(
      database,
      {
        emitCrmChanged: jest.fn(),
        emitFinanceChanged: jest.fn(),
      } as unknown as RealtimeBus,
    );
    issueService = new SubscriptionIssueService(
      issueRepository,
      policy,
      integrity,
      reservations,
      new SubscriptionPreviewTokenService({
        get: (key: string, fallback?: string) =>
          key === "COMMERCE_PREVIEW_SECRET" ? previewSecret : fallback,
      } as unknown as ConfigService),
    );
    const commerceRepository = new CommerceProjectionRepository(database);
    paymentService = new ActualPaymentService(
      issueRepository,
      policy,
      integrity,
      commerceRepository,
      new PaymentLifecycleService(
        new PaymentLifecycleRepository(
          database,
          new PlatformIntegrityRepository(),
        ),
        issueRepository,
        policy,
        integrity,
        commerceRepository,
        reservations,
      ),
    );
    lifecycleService = new SubscriptionLifecycleService(
      new SubscriptionLifecycleRepository(database),
      policy,
      integrity,
      new SubscriptionPreviewTokenService({
        get: (key: string, fallback?: string) =>
          key === "COMMERCE_PREVIEW_SECRET" ? previewSecret : fallback,
      } as unknown as ConfigService),
      reservations,
    );
    fixture = await createFixture(pool);
    actor = fixture.actor;
  });

  afterAll(async () => {
    if (pool && fixture) await cleanupFixture(pool, fixture);
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("previews immutable payments/writeoffs/balance and future lessons", async () => {
    const issued = await issue("preview-source");
    await paymentService.record(
      actor,
      fixture.studentId,
      {
        issuedSubscriptionId: issued.subscription.id,
        amountMinor: "500000",
        method: "cashless",
        occurredAt: "2026-08-10T10:00:00.000Z",
      },
      metadata("preview-payment"),
    );
    await seedConsumedUnits(
      pool,
      fixture.studentId,
      issued.subscription.id,
      "2",
    );
    await seedFutureLessons(
      pool,
      fixture.studentId,
      issued.subscription.id,
      [
        { units: "1.5", reserved: true },
        { units: "1.5", reserved: true },
        { units: "1", reserved: false },
      ],
    );

    const preview = await lifecycleService.previewCancellation(
      actor,
      fixture.studentId,
      issued.subscription.id,
    );
    expect(preview).toMatchObject({
      issuedSubscriptionId: issued.subscription.id,
      expectedVersion: 1,
      package: {
        id: fixture.sourcePackageId,
        name: `${marker}-source`,
        unitCount: "10",
      },
      usage: { usedUnits: "2" },
      financial: {
        currencyCode: "RUB",
        finalMinor: "800000",
        actualPaidMinor: "500000",
        writeoffMinor: "0",
        balanceMinor: "-300000",
      },
      future: {
        lessonCount: 3,
        reservedLessonCount: 2,
        reservedUnits: "3",
      },
    });
    expect(preview.future.lessons).toHaveLength(3);
    expect(
      preview.future.lessons.filter((lesson) => lesson.reserved),
    ).toHaveLength(2);
    expect(preview.previewToken).toMatch(/^v1\./);
    expect(new Date(preview.expiresAt).getTime()).toBeGreaterThan(Date.now());
  });

  it("cancels lifecycle-only, releases reservations and preserves every finance/lesson fact", async () => {
    const issued = await issue("confirm-source");
    await paymentService.record(
      actor,
      fixture.studentId,
      {
        issuedSubscriptionId: issued.subscription.id,
        amountMinor: "600000",
        method: "cash",
        occurredAt: "2026-08-11T10:00:00.000Z",
      },
      metadata("confirm-payment"),
    );
    await seedConsumedUnits(
      pool,
      fixture.studentId,
      issued.subscription.id,
      "1",
    );
    await seedFutureLessons(
      pool,
      fixture.studentId,
      issued.subscription.id,
      [
        { units: "2", reserved: true },
        { units: "1", reserved: false },
      ],
    );
    const preview = await lifecycleService.previewCancellation(
      actor,
      fixture.studentId,
      issued.subscription.id,
    );
    const command = {
      expectedVersion: preview.expectedVersion,
      previewToken: preview.previewToken,
      confirm: true as const,
      reason: "issued.by.mistake",
    };
    const financeBefore = await immutableState(
      pool,
      fixture.studentId,
      issued.subscription.id,
    );

    await expect(
      lifecycleService.cancel(
        actor,
        fixture.otherStudentId,
        issued.subscription.id,
        command,
        metadata("cross-student"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(
      await lifecycleState(pool, issued.subscription.id),
    ).toMatchObject({
      status: "active",
      version: 1,
      cancelEvents: 0,
    });

    const first = await lifecycleService.cancel(
      actor,
      fixture.studentId,
      issued.subscription.id,
      command,
      metadata("confirm-cancel"),
    );
    const replay = await lifecycleService.cancel(
      actor,
      fixture.studentId,
      issued.subscription.id,
      command,
      metadata("confirm-cancel"),
    );
    expect(replay).toEqual({ ...first, replayed: true });
    expect(first.cancellation).toEqual({
      issuedSubscriptionId: issued.subscription.id,
      version: 2,
      status: "cancelled",
      releasedReservationCount: 1,
      releasedReservationUnits: "2",
      futureLessonCount: 2,
    });
    expect(await immutableState(
      pool,
      fixture.studentId,
      issued.subscription.id,
    )).toEqual(financeBefore);
    expect(
      await lifecycleState(pool, issued.subscription.id),
    ).toEqual({
      status: "cancelled",
      version: 2,
      cancelEvents: 1,
      reserved: 0,
      released: 1,
      lessons: financeBefore.lessonCount,
      auditEvents: 1,
      outboxEvents: 1,
    });
  });

  it("serializes cancel versus replace to one winner and stably replays it", async () => {
    const issued = await issue("race-source");
    const cancelPreview = await lifecycleService.previewCancellation(
      actor,
      fixture.studentId,
      issued.subscription.id,
    );
    const replacePreview = await lifecycleService.previewReplacement(
      actor,
      fixture.studentId,
      issued.subscription.id,
      { newPackageId: fixture.replacementPackageId },
    );
    const cancelMetadata = metadata("race-cancel");
    const replaceMetadata = metadata("race-replace");
    const cancelCommand = {
      expectedVersion: cancelPreview.expectedVersion,
      previewToken: cancelPreview.previewToken,
      confirm: true as const,
      reason: "race.cancel",
    };
    const replaceCommand = {
      expectedVersion: replacePreview.expectedVersion,
      previewToken: replacePreview.previewToken,
      confirm: true as const,
      reason: "race.replace",
    };
    const outcomes = await Promise.allSettled([
      lifecycleService.cancel(
        actor,
        fixture.studentId,
        issued.subscription.id,
        cancelCommand,
        cancelMetadata,
      ),
      lifecycleService.replace(
        actor,
        fixture.studentId,
        issued.subscription.id,
        replaceCommand,
        replaceMetadata,
      ),
    ]);
    expect(
      outcomes.filter((outcome) => outcome.status === "fulfilled"),
    ).toHaveLength(1);
    expect(outcomes.find((outcome) => outcome.status === "rejected")).toMatchObject({
      status: "rejected",
      reason: expect.any(ConflictException),
    });

    if (outcomes[0]!.status === "fulfilled") {
      const replay = await lifecycleService.cancel(
        actor,
        fixture.studentId,
        issued.subscription.id,
        cancelCommand,
        cancelMetadata,
      );
      expect(replay).toEqual({ ...outcomes[0].value, replayed: true });
    } else {
      const replaceWinner = outcomes[1]!;
      if (replaceWinner.status !== "fulfilled") {
        throw new Error("Expected replacement to win the race.");
      }
      const replay = await lifecycleService.replace(
        actor,
        fixture.studentId,
        issued.subscription.id,
        replaceCommand,
        replaceMetadata,
      );
      expect(replay).toEqual({ ...replaceWinner.value, replayed: true });
    }
    const race = await pool.query<{
      lifecycle_count: string;
      aggregate_version: string;
    }>(
      `
        select
          (
            select count(*)
            from app.subscription_lifecycle_events event
            where event.event_type in ('replace', 'cancel')
              and (
                event.before_issued_subscription_id = $1
                or event.issued_subscription_id = $1
              )
          )::text as lifecycle_count,
          (
            select version
            from app.aggregate_versions
            where aggregate_type = 'commerce:issued-subscription'
              and aggregate_id = $1::text
          )::text as aggregate_version
      `,
      [issued.subscription.id],
    );
    expect(race.rows[0]).toEqual({
      lifecycle_count: "1",
      aggregate_version: "2",
    });
  });

  async function issue(suffix: string) {
    return issueService.issue(
      actor,
      fixture.studentId,
      { packageId: fixture.sourcePackageId },
      metadata(suffix),
    );
  }

  function metadata(suffix: string) {
    return {
      idempotencyKey: `${marker}:${suffix}`,
      requestId: `${marker}:${suffix}:request`,
    };
  }
});

async function seedConsumedUnits(
  pool: Pool,
  studentId: string,
  subscriptionId: string,
  units: string,
): Promise<void> {
  const lesson = await pool.query<{ id: string }>(
    `
      insert into app.lessons (
        student_id, scheduled_at, duration_minutes, status
      )
      values ($1, now() - interval '1 day', 60, 'completed')
      returning id
    `,
    [studentId],
  );
  await insertSnapshot(
    pool,
    lesson.rows[0]!.id,
    studentId,
    subscriptionId,
    units,
  );
  await pool.query(
    `
      insert into app.lesson_client_charge_facts (
        lesson_id,
        client_type,
        client_id,
        charge_type,
        snapshot_value,
        subscription_id,
        amount_minor,
        units
      )
      values (
        $1, 'student', $2, 'subscription', $3::numeric, $4, 0, $3::numeric
      )
    `,
    [lesson.rows[0]!.id, studentId, units, subscriptionId],
  );
}

async function seedFutureLessons(
  pool: Pool,
  studentId: string,
  subscriptionId: string,
  lessons: { units: string; reserved: boolean }[],
): Promise<void> {
  for (let index = 0; index < lessons.length; index += 1) {
    const lesson = await pool.query<{ id: string }>(
      `
        insert into app.lessons (
          student_id, scheduled_at, duration_minutes, status
        )
        values (
          $1,
          now() + make_interval(days => $2::integer),
          60,
          'scheduled'
        )
        returning id
      `,
      [studentId, index + 1],
    );
    await insertSnapshot(
      pool,
      lesson.rows[0]!.id,
      studentId,
      subscriptionId,
      lessons[index]!.units,
    );
    if (lessons[index]!.reserved) {
      await pool.query(
        `
          insert into app.lesson_reservations (
            lesson_id, subscription_id, units
          )
          values ($1, $2, $3::numeric)
        `,
        [
          lesson.rows[0]!.id,
          subscriptionId,
          lessons[index]!.units,
        ],
      );
    }
  }
}

async function insertSnapshot(
  pool: Pool,
  lessonId: string,
  studentId: string,
  subscriptionId: string,
  units: string,
): Promise<void> {
  await pool.query(
    `
      insert into app.lesson_snapshots (
        lesson_id,
        client_type,
        client_id,
        completion_type,
        client_charge_type,
        client_charge_value,
        teacher_compensation_type,
        teacher_compensation_value,
        subscription_id
      )
      values (
        $1, 'student', $2, 'standard.success', 'subscription', $3::numeric,
        'none', 0, $4
      )
    `,
    [lessonId, studentId, units, subscriptionId],
  );
}

async function immutableState(
  pool: Pool,
  studentId: string,
  subscriptionId: string,
) {
  const result = await pool.query<{
    payment_count: string;
    payment_minor: string;
    obligation_count: string;
    obligation_debit_minor: string;
    obligation_credit_minor: string;
    writeoff_count: string;
    writeoff_minor: string;
    writeoff_units: string;
    lesson_count: string;
  }>(
    `
      select
        (
          select count(*) from app.payments
          where student_id = $1
        )::text as payment_count,
        (
          select coalesce(sum(amount_minor), 0) from app.payments
          where student_id = $1
        )::text as payment_minor,
        (
          select count(*) from app.subscription_obligation_facts
          where student_id = $1
        )::text as obligation_count,
        (
          select coalesce(sum(amount_minor), 0)
          from app.subscription_obligation_facts
          where student_id = $1 and direction = 'debit'
        )::text as obligation_debit_minor,
        (
          select coalesce(sum(amount_minor), 0)
          from app.subscription_obligation_facts
          where student_id = $1 and direction = 'credit'
        )::text as obligation_credit_minor,
        (
          select count(*) from app.lesson_client_charge_facts
          where client_type = 'student' and client_id = $1
        )::text as writeoff_count,
        (
          select coalesce(sum(amount_minor), 0)
          from app.lesson_client_charge_facts
          where client_type = 'student' and client_id = $1
        )::text as writeoff_minor,
        (
          select coalesce(sum(units), 0)
          from app.lesson_client_charge_facts
          where client_type = 'student' and client_id = $1
        )::text as writeoff_units,
        (
          select count(*) from app.lesson_snapshots
          where subscription_id = $2
        )::text as lesson_count
    `,
    [studentId, subscriptionId],
  );
  const row = result.rows[0]!;
  return {
    paymentCount: row.payment_count,
    paymentMinor: row.payment_minor,
    obligationCount: row.obligation_count,
    obligationDebitMinor: row.obligation_debit_minor,
    obligationCreditMinor: row.obligation_credit_minor,
    writeoffCount: row.writeoff_count,
    writeoffMinor: row.writeoff_minor,
    writeoffUnits: row.writeoff_units,
    lessonCount: Number(row.lesson_count),
  };
}

async function lifecycleState(pool: Pool, subscriptionId: string) {
  const result = await pool.query<{
    status: string;
    version: string;
    cancel_events: string;
    reserved: string;
    released: string;
    lessons: string;
    audit_events: string;
    outbox_events: string;
  }>(
    `
      select
        subscription.status,
        subscription.version::text,
        (
          select count(*) from app.subscription_lifecycle_events
          where issued_subscription_id = $1 and event_type = 'cancel'
        )::text as cancel_events,
        (
          select count(*) from app.lesson_reservations
          where subscription_id = $1 and state = 'reserved'
        )::text as reserved,
        (
          select count(*) from app.lesson_reservations
          where subscription_id = $1 and state = 'released'
        )::text as released,
        (
          select count(*) from app.lesson_snapshots
          where subscription_id = $1
        )::text as lessons,
        (
          select count(*) from app.audit_events
          where entity_id = $1::text
            and action = 'crm.subscription_cancelled'
        )::text as audit_events,
        (
          select count(*) from app.platform_outbox_events
          where aggregate_id = $1::text
            and event_type = 'commerce.subscription.changed'
            and payload ->> 'state' = 'cancelled'
        )::text as outbox_events
      from app.subscriptions subscription
      where subscription.id = $1
    `,
    [subscriptionId],
  );
  const row = result.rows[0]!;
  const compact = {
    status: row.status,
    version: Number(row.version),
    cancelEvents: Number(row.cancel_events),
  };
  if (compact.status === "active") return compact;
  return {
    ...compact,
    reserved: Number(row.reserved),
    released: Number(row.released),
    lessons: Number(row.lessons),
    auditEvents: Number(row.audit_events),
    outboxEvents: Number(row.outbox_events),
  };
}

async function createFixture(pool: Pool) {
  const client = await pool.connect();
  await client.query("begin");
  try {
    const director = await insertUser(client, "director", "director");
    const studentUser = await insertUser(client, "student", "client");
    const otherUser = await insertUser(client, "other-student", "client");
    const studentProfile = await insertProfile(client, studentUser);
    const otherProfile = await insertProfile(client, otherUser);
    const branch = await client.query<{ id: string }>(
      `insert into app.branches (name, timezone_name)
       values ($1, 'Europe/Moscow') returning id`,
      [`${marker}-branch`],
    );
    const studentId = await insertStudent(
      client,
      studentProfile,
      branch.rows[0]!.id,
    );
    const otherStudentId = await insertStudent(client, otherProfile);
    const sourcePackageId = await insertPackage(
      client,
      "source",
      10,
      "800000",
    );
    const replacementPackageId = await insertPackage(
      client,
      "replacement",
      10,
      "900000",
    );
    await client.query("commit");
    return {
      actor: { userId: director, role: "director" } as ActorContext,
      userIds: [director, studentUser, otherUser],
      profileIds: [studentProfile, otherProfile],
      studentId,
      otherStudentId,
      sourcePackageId,
      replacementPackageId,
      packageIds: [sourcePackageId, replacementPackageId],
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function insertUser(
  client: PoolClient,
  suffix: string,
  role: string,
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `
      insert into app.users (email, role, email_verified_at)
      values ($1, $2, now())
      returning id
    `,
    [`${marker}-${suffix}@example.test`, role],
  );
  return result.rows[0]!.id;
}

async function insertProfile(
  client: PoolClient,
  userId: string,
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `
      insert into app.profiles (user_id, first_name, last_name)
      values ($1, 'Cancel', 'Client')
      returning id
    `,
    [userId],
  );
  return result.rows[0]!.id;
}

async function insertStudent(
  client: PoolClient,
  profileId: string,
  branchId?: string,
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `
      insert into app.students (profile_id, status, branch_id)
      values ($1, 'active', $2)
      returning id
    `,
    [profileId, branchId ?? null],
  );
  return result.rows[0]!.id;
}

async function insertPackage(
  client: PoolClient,
  suffix: string,
  units: number,
  priceMinor: string,
): Promise<string> {
  const result = await client.query<{ id: string }>(
    `
      insert into app.subscription_packages (
        name,
        lessons_total,
        base_price_minor,
        currency_code,
        validity_days,
        is_active,
        version
      )
      values ($1, $2, $3::bigint, 'RUB', 90, true, 1)
      returning id
    `,
    [`${marker}-${suffix}`, units, priceMinor],
  );
  return result.rows[0]!.id;
}

async function cleanupFixture(
  pool: Pool,
  fixture: Awaited<ReturnType<typeof createFixture>>,
): Promise<void> {
  const client = await pool.connect();
  await client.query("begin");
  try {
    await client.query("set local session_replication_role = replica");
    const subscriptions = await client.query<{ id: string }>(
      "select id from app.subscriptions where package_id = any($1::uuid[])",
      [fixture.packageIds],
    );
    const subscriptionIds = subscriptions.rows.map((row) => row.id);
    const lessons = await client.query<{ id: string }>(
      "select id from app.lessons where student_id = any($1::uuid[])",
      [[fixture.studentId, fixture.otherStudentId]],
    );
    const lessonIds = lessons.rows.map((row) => row.id);
    const payments = await client.query<{ id: string }>(
      "select id from app.payments where student_id = any($1::uuid[])",
      [[fixture.studentId, fixture.otherStudentId]],
    );
    const paymentIds = payments.rows.map((row) => row.id);
    const paymentRecords = await client.query<{ id: string }>(
      "select id from app.client_payment_records where student_id = any($1::uuid[])",
      [[fixture.studentId, fixture.otherStudentId]],
    );
    const paymentRecordIds = paymentRecords.rows.map((row) => row.id);
    await deleteByIds(
      client,
      "app.idempotency_records",
      "actor_key",
      [fixture.actor.userId],
      "text",
    );
    await deleteByIds(
      client,
      "app.platform_outbox_events",
      "aggregate_id",
      [...subscriptionIds, ...paymentIds, ...paymentRecordIds],
      "text",
    );
    await client.query("delete from app.audit_events where actor_user_id = $1", [
      fixture.actor.userId,
    ]);
    await deleteByIds(
      client,
      "app.aggregate_versions",
      "aggregate_id",
      [...subscriptionIds, ...paymentIds, ...paymentRecordIds],
      "text",
    );
    for (const table of [
      "app.lesson_reservations",
      "app.lesson_client_charge_facts",
      "app.lesson_snapshots",
    ]) {
      await deleteByIds(client, table, "lesson_id", lessonIds, "uuid");
    }
    await deleteByIds(client, "app.lessons", "id", lessonIds, "uuid");
    for (const table of [
      "app.subscription_lifecycle_events",
      "app.subscription_obligation_facts",
      "app.subscription_installments",
    ]) {
      await deleteByIds(
        client,
        table,
        "issued_subscription_id",
        subscriptionIds,
        "uuid",
      );
    }
    await deleteByIds(
      client,
      "app.client_payment_status_events",
      "payment_record_id",
      paymentRecordIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.client_payment_records",
      "id",
      paymentRecordIds,
      "uuid",
    );
    await deleteByIds(client, "app.payments", "id", paymentIds, "uuid");
    await deleteByIds(
      client,
      "app.subscriptions",
      "id",
      subscriptionIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscription_package_versions",
      "package_id",
      fixture.packageIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscription_packages",
      "id",
      fixture.packageIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.students",
      "id",
      [fixture.studentId, fixture.otherStudentId],
      "uuid",
    );
    await deleteByIds(
      client,
      "app.profiles",
      "id",
      fixture.profileIds,
      "uuid",
    );
    await deleteByIds(client, "app.users", "id", fixture.userIds, "uuid");
    await client.query("delete from app.branches where name = $1", [
      `${marker}-branch`,
    ]);
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function deleteByIds(
  client: PoolClient,
  table: string,
  column: string,
  ids: string[],
  cast: "uuid" | "text",
): Promise<void> {
  if (ids.length === 0) return;
  await client.query(
    `delete from ${table} where ${column} = any($1::${cast}[])`,
    [ids],
  );
}
