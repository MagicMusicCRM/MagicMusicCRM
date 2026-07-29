import {
  ConflictException,
  NotFoundException,
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
  throw new Error("Subscription replace tests require local PostgreSQL.");
}

const marker = `v4-subscription-replace-${randomUUID()}`;
const previewSecret = "replace-preview-test-secret-at-least-32-bytes";

jest.setTimeout(120_000);

describe("Subscription replacement preview/confirm", () => {
  let pool: Pool;
  let database: DatabaseService;
  let issueService: SubscriptionIssueService;
  let paymentService: ActualPaymentService;
  let lifecycleService: SubscriptionLifecycleService;
  let actor: ActorContext;
  let studentId: string;
  let otherStudentId: string;
  let fixture: Awaited<ReturnType<typeof createFixture>>;

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
    );
    paymentService = new ActualPaymentService(
      issueRepository,
      policy,
      integrity,
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
    studentId = fixture.studentId;
    otherStudentId = fixture.otherStudentId;
  });

  afterAll(async () => {
    if (pool && fixture) await cleanupFixture(pool, fixture);
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("replaces with a dearer snapshot, preserves payment and deterministically releases overflow reservations", async () => {
    const issued = await issue("dearer-source");
    await paymentService.record(
      actor,
      studentId,
      {
        issuedSubscriptionId: issued.subscription.id,
        amountMinor: "800000",
        method: "cashless",
        occurredAt: "2026-08-01T10:00:00.000Z",
      },
      metadata("dearer-payment"),
    );
    await seedConsumedUnits(pool, studentId, issued.subscription.id, "3");
    await seedReservedLessons(
      pool,
      studentId,
      issued.subscription.id,
      ["2", "2", "2"],
    );

    const preview = await lifecycleService.previewReplacement(
      actor,
      studentId,
      issued.subscription.id,
      { newPackageId: fixture.dearerPackageId },
    );
    expect(preview.usage).toMatchObject({
      usedUnits: "3",
      reservedLessonCount: 3,
      reservedUnits: "6",
      transferableReservationCount: 2,
      transferableReservationUnits: "4",
      releasedReservationCount: 1,
      releasedReservationUnits: "2",
    });
    expect(preview.financial).toEqual({
      currencyCode: "RUB",
      oldFinalMinor: "800000",
      newFinalMinor: "1000000",
      actualPaidMinor: "800000",
      obligationDeltaMinor: "200000",
      resultingPosition: { kind: "debt", amountMinor: "200000" },
    });

    const command = {
      expectedVersion: preview.expectedVersion,
      previewToken: preview.previewToken,
      confirm: true as const,
      reason: "package.corrected",
    };
    const first = await lifecycleService.replace(
      actor,
      studentId,
      issued.subscription.id,
      command,
      metadata("dearer-confirm"),
    );
    const replay = await lifecycleService.replace(
      actor,
      studentId,
      issued.subscription.id,
      command,
      metadata("dearer-confirm"),
    );
    expect(replay).toEqual({ ...first, replayed: true });
    expect(first.replacement).toMatchObject({
      oldSubscriptionId: issued.subscription.id,
      newPackageId: fixture.dearerPackageId,
      usedUnits: "3",
      transferredReservationCount: 2,
      releasedReservationCount: 1,
      deltaMinor: "200000",
      positionKind: "debt",
      positionMinor: "200000",
      ccy: "RUB",
    });

    const facts = await replacementFacts(
      pool,
      issued.subscription.id,
      first.replacement.newSubscriptionId,
    );
    expect(facts).toEqual({
      oldStatus: "replaced",
      oldVersion: 2,
      newStatus: "active",
      newVersion: 1,
      newUsedUnits: "3",
      paymentCountOld: 1,
      paymentCountNew: 0,
      paymentMinor: "800000",
      obligationCount: 1,
      obligationType: "replacement_debt",
      obligationDirection: "debit",
      obligationMinor: "200000",
      lifecycleCount: 1,
      reservedOnOld: 0,
      reservedOnNew: 2,
      releasedOnOld: 1,
      auditCount: 1,
      outboxCount: 1,
    });
  });

  it("creates a credit differential for a cheaper replacement without copying payments", async () => {
    const issued = await issue("cheaper-source");
    await paymentService.record(
      actor,
      studentId,
      {
        issuedSubscriptionId: issued.subscription.id,
        amountMinor: "800000",
        method: "cash",
        occurredAt: "2026-08-02T10:00:00.000Z",
      },
      metadata("cheaper-payment"),
    );
    const preview = await lifecycleService.previewReplacement(
      actor,
      studentId,
      issued.subscription.id,
      { newPackageId: fixture.cheaperPackageId },
    );
    const result = await lifecycleService.replace(
      actor,
      studentId,
      issued.subscription.id,
      {
        expectedVersion: preview.expectedVersion,
        previewToken: preview.previewToken,
        confirm: true,
        reason: "package.cheaper",
      },
      metadata("cheaper-confirm"),
    );
    expect(result.replacement).toMatchObject({
      deltaMinor: "-200000",
      positionKind: "overpayment",
      positionMinor: "200000",
    });
    const fact = await pool.query<{
      fact_type: string;
      direction: string;
      amount_minor: string;
    }>(
      `
        select fact_type, direction, amount_minor
        from app.subscription_obligation_facts
        where issued_subscription_id = $1
          and source_type = 'subscription.replace'
      `,
      [result.replacement.newSubscriptionId],
    );
    expect(fact.rows).toEqual([
      {
        fact_type: "replacement_overpayment",
        direction: "credit",
        amount_minor: "200000",
      },
    ]);
    expect(
      await scalarCount(
        pool,
        "app.payments",
        "issued_subscription_id = $1",
        [result.replacement.newSubscriptionId],
      ),
    ).toBe(0);
  });

  it("blocks insufficient volume, cross-currency and cross-student paths with persisted=0", async () => {
    const issued = await issue("blocked-source");
    await seedConsumedUnits(pool, studentId, issued.subscription.id, "3");
    const before = await persistedReplacementCount(
      pool,
      issued.subscription.id,
    );
    await expect(
      lifecycleService.previewReplacement(
        actor,
        studentId,
        issued.subscription.id,
        { newPackageId: fixture.smallPackageId },
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      lifecycleService.previewReplacement(
        actor,
        studentId,
        issued.subscription.id,
        { newPackageId: fixture.euroPackageId },
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      lifecycleService.previewReplacement(
        actor,
        otherStudentId,
        issued.subscription.id,
        { newPackageId: fixture.dearerPackageId },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(
      await persistedReplacementCount(pool, issued.subscription.id),
    ).toBe(before);
  });

  it("allows exactly one concurrent replace winner and stably replays it", async () => {
    const issued = await issue("concurrent-source");
    const preview = await lifecycleService.previewReplacement(
      actor,
      studentId,
      issued.subscription.id,
      { newPackageId: fixture.dearerPackageId },
    );
    const command = {
      expectedVersion: preview.expectedVersion,
      previewToken: preview.previewToken,
      confirm: true as const,
      reason: "package.concurrent",
    };
    const keys = [
      metadata("concurrent-a"),
      metadata("concurrent-b"),
    ];
    const outcomes = await Promise.allSettled(
      keys.map((key) =>
        lifecycleService.replace(
          actor,
          studentId,
          issued.subscription.id,
          command,
          key,
        ),
      ),
    );
    const winnerIndex = outcomes.findIndex(
      (outcome) => outcome.status === "fulfilled",
    );
    expect(winnerIndex).toBeGreaterThanOrEqual(0);
    expect(outcomes.filter((outcome) => outcome.status === "fulfilled")).toHaveLength(
      1,
    );
    const loser = outcomes.find((outcome) => outcome.status === "rejected");
    expect(loser).toMatchObject({
      status: "rejected",
      reason: expect.any(ConflictException),
    });
    const winner = (
      outcomes[winnerIndex] as PromiseFulfilledResult<
        Awaited<ReturnType<SubscriptionLifecycleService["replace"]>>
      >
    ).value;
    const replay = await lifecycleService.replace(
      actor,
      studentId,
      issued.subscription.id,
      command,
      keys[winnerIndex]!,
    );
    expect(replay).toEqual({ ...winner, replayed: true });
    expect(
      await persistedReplacementCount(pool, issued.subscription.id),
    ).toBe(1);
  });

  async function issue(suffix: string) {
    return issueService.issue(
      actor,
      studentId,
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
    [lesson.rows[0]!.id, studentId, units, subscriptionId],
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

async function seedReservedLessons(
  pool: Pool,
  studentId: string,
  subscriptionId: string,
  units: string[],
): Promise<void> {
  for (let index = 0; index < units.length; index += 1) {
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
      [lesson.rows[0]!.id, studentId, units[index], subscriptionId],
    );
    await pool.query(
      `
        insert into app.lesson_reservations (
          lesson_id, subscription_id, units
        )
        values ($1, $2, $3::numeric)
      `,
      [lesson.rows[0]!.id, subscriptionId, units[index]],
    );
  }
}

async function replacementFacts(
  pool: Pool,
  oldId: string,
  newId: string,
) {
  const result = await pool.query<{
    old_status: string;
    old_version: string;
    new_status: string;
    new_version: string;
    new_used_units: string;
    payment_count_old: string;
    payment_count_new: string;
    payment_minor: string;
    obligation_count: string;
    obligation_type: string;
    obligation_direction: string;
    obligation_minor: string;
    lifecycle_count: string;
    reserved_on_old: string;
    reserved_on_new: string;
    released_on_old: string;
    audit_count: string;
    outbox_count: string;
  }>(
    `
      select
        old.status as old_status,
        old.version::text as old_version,
        replacement.status as new_status,
        replacement.version::text as new_version,
        replacement.lessons_used::text as new_used_units,
        (
          select count(*) from app.payments
          where issued_subscription_id = $1
        )::text as payment_count_old,
        (
          select count(*) from app.payments
          where issued_subscription_id = $2
        )::text as payment_count_new,
        (
          select coalesce(sum(amount_minor), 0) from app.payments
          where issued_subscription_id = $1
        )::text as payment_minor,
        (
          select count(*) from app.subscription_obligation_facts
          where issued_subscription_id = $2
            and source_type = 'subscription.replace'
        )::text as obligation_count,
        (
          select fact_type from app.subscription_obligation_facts
          where issued_subscription_id = $2
            and source_type = 'subscription.replace'
        ) as obligation_type,
        (
          select direction from app.subscription_obligation_facts
          where issued_subscription_id = $2
            and source_type = 'subscription.replace'
        ) as obligation_direction,
        (
          select amount_minor from app.subscription_obligation_facts
          where issued_subscription_id = $2
            and source_type = 'subscription.replace'
        )::text as obligation_minor,
        (
          select count(*) from app.subscription_lifecycle_events
          where before_issued_subscription_id = $1
            and after_issued_subscription_id = $2
            and event_type = 'replace'
        )::text as lifecycle_count,
        (
          select count(*) from app.lesson_reservations
          where subscription_id = $1 and state = 'reserved'
        )::text as reserved_on_old,
        (
          select count(*) from app.lesson_reservations
          where subscription_id = $2 and state = 'reserved'
        )::text as reserved_on_new,
        (
          select count(*) from app.lesson_reservations
          where subscription_id = $1 and state = 'released'
        )::text as released_on_old,
        (
          select count(*) from app.audit_events
          where entity_id = $1::text
            and action = 'crm.subscription_replaced'
        )::text as audit_count,
        (
          select count(*) from app.platform_outbox_events
          where aggregate_id = $1::text
            and event_type = 'commerce.subscription.changed'
            and payload ->> 'state' = 'replaced'
        )::text as outbox_count
      from app.subscriptions old
      join app.subscriptions replacement on replacement.id = $2
      where old.id = $1
    `,
    [oldId, newId],
  );
  const row = result.rows[0]!;
  return {
    oldStatus: row.old_status,
    oldVersion: Number(row.old_version),
    newStatus: row.new_status,
    newVersion: Number(row.new_version),
    newUsedUnits: normalizeNumeric(row.new_used_units),
    paymentCountOld: Number(row.payment_count_old),
    paymentCountNew: Number(row.payment_count_new),
    paymentMinor: row.payment_minor,
    obligationCount: Number(row.obligation_count),
    obligationType: row.obligation_type,
    obligationDirection: row.obligation_direction,
    obligationMinor: row.obligation_minor,
    lifecycleCount: Number(row.lifecycle_count),
    reservedOnOld: Number(row.reserved_on_old),
    reservedOnNew: Number(row.reserved_on_new),
    releasedOnOld: Number(row.released_on_old),
    auditCount: Number(row.audit_count),
    outboxCount: Number(row.outbox_count),
  };
}

async function persistedReplacementCount(
  pool: Pool,
  oldId: string,
): Promise<number> {
  return scalarCount(
    pool,
    "app.subscription_lifecycle_events",
    "before_issued_subscription_id = $1 and event_type = 'replace'",
    [oldId],
  );
}

async function scalarCount(
  pool: Pool,
  table: string,
  where: string,
  params: unknown[],
): Promise<number> {
  const result = await pool.query<{ count: string }>(
    `select count(*)::text as count from ${table} where ${where}`,
    params,
  );
  return Number(result.rows[0]!.count);
}

async function createFixture(pool: Pool) {
  const client = await pool.connect();
  await client.query("begin");
  try {
    const director = await client.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, 'director', now())
        returning id
      `,
      [`${marker}-director@example.test`],
    );
    const clientUser = await client.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, 'client', now())
        returning id
      `,
      [`${marker}-client@example.test`],
    );
    const otherClientUser = await client.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, 'client', now())
        returning id
      `,
      [`${marker}-other-client@example.test`],
    );
    const profile = await client.query<{ id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name)
        values ($1, 'Replace', 'Client')
        returning id
      `,
      [clientUser.rows[0]!.id],
    );
    const otherProfile = await client.query<{ id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name)
        values ($1, 'Other', 'Client')
        returning id
      `,
      [otherClientUser.rows[0]!.id],
    );
    const student = await client.query<{ id: string }>(
      `
        insert into app.students (profile_id, status)
        values ($1, 'active')
        returning id
      `,
      [profile.rows[0]!.id],
    );
    const otherStudent = await client.query<{ id: string }>(
      `
        insert into app.students (profile_id, status)
        values ($1, 'active')
        returning id
      `,
      [otherProfile.rows[0]!.id],
    );
    const packages = [
      await insertPackage(client, "source", 10, "800000", "RUB"),
      await insertPackage(client, "dearer", 7, "1000000", "RUB"),
      await insertPackage(client, "cheaper", 10, "600000", "RUB"),
      await insertPackage(client, "small", 2, "500000", "RUB"),
      await insertPackage(client, "euro", 10, "800000", "EUR"),
    ];
    await client.query("commit");
    return {
      actor: {
        userId: director.rows[0]!.id,
        role: "director",
      } as ActorContext,
      userIds: [
        director.rows[0]!.id,
        clientUser.rows[0]!.id,
        otherClientUser.rows[0]!.id,
      ],
      profileIds: [profile.rows[0]!.id, otherProfile.rows[0]!.id],
      studentId: student.rows[0]!.id,
      otherStudentId: otherStudent.rows[0]!.id,
      sourcePackageId: packages[0],
      dearerPackageId: packages[1],
      cheaperPackageId: packages[2],
      smallPackageId: packages[3],
      euroPackageId: packages[4],
      packageIds: packages,
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function insertPackage(
  client: PoolClient,
  suffix: string,
  units: number,
  priceMinor: string,
  currencyCode: string,
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
      values ($1, $2, $3::bigint, $4, 90, true, 1)
      returning id
    `,
    [`${marker}-${suffix}`, units, priceMinor, currencyCode],
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
      `
        select id from app.subscriptions
        where package_id = any($1::uuid[])
      `,
      [fixture.packageIds],
    );
    const subscriptionIds = subscriptions.rows.map((row) => row.id);
    const lessons = await client.query<{ id: string }>(
      `
        select id from app.lessons
        where student_id = any($1::uuid[])
      `,
      [[fixture.studentId, fixture.otherStudentId]],
    );
    const lessonIds = lessons.rows.map((row) => row.id);
    const payments = await client.query<{ id: string }>(
      `
        select id from app.payments
        where student_id = any($1::uuid[])
      `,
      [[fixture.studentId, fixture.otherStudentId]],
    );
    const paymentIds = payments.rows.map((row) => row.id);
    await deleteByIds(client, "app.idempotency_records", "actor_key", [
      fixture.actor.userId,
    ], "text");
    await deleteByIds(
      client,
      "app.platform_outbox_events",
      "aggregate_id",
      [...subscriptionIds, ...paymentIds],
      "text",
    );
    await client.query(
      "delete from app.audit_events where actor_user_id = $1",
      [fixture.actor.userId],
    );
    await deleteByIds(
      client,
      "app.aggregate_versions",
      "aggregate_id",
      [...subscriptionIds, ...paymentIds],
      "text",
    );
    await deleteByIds(
      client,
      "app.lesson_reservations",
      "lesson_id",
      lessonIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.lesson_client_charge_facts",
      "lesson_id",
      lessonIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.lesson_snapshots",
      "lesson_id",
      lessonIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.lessons",
      "id",
      lessonIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscription_lifecycle_events",
      "issued_subscription_id",
      subscriptionIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscription_obligation_facts",
      "issued_subscription_id",
      subscriptionIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscription_installments",
      "issued_subscription_id",
      subscriptionIds,
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
    await deleteByIds(
      client,
      "app.users",
      "id",
      fixture.userIds,
      "uuid",
    );
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

function normalizeNumeric(value: string): string {
  return value.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "");
}
