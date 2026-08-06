import {
  ConflictException,
  ForbiddenException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import {
  ActorContext,
  UserRole,
} from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ActualPaymentService } from "./actual-payment.service";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionIssueService } from "./subscription-issue.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Subscription issue tests require local PostgreSQL.");
}

const marker = `v4-subscription-issue-${randomUUID()}`;
const roles: readonly UserRole[] = [
  "client",
  "teacher",
  "admin",
  "manager",
  "director",
  "system_admin",
];
const issuingRoles: readonly UserRole[] = [
  "admin",
  "manager",
  "director",
  "system_admin",
];

jest.setTimeout(120_000);

describe("Subscription issue, discount, installments and ActualPayment", () => {
  let pool: Pool;
  let database: DatabaseService;
  let issueService: SubscriptionIssueService;
  let paymentService: ActualPaymentService;
  let commerceRepository: CommerceProjectionRepository;
  let actors: Record<UserRole, ActorContext>;
  let studentId: string;
  let profileId: string;
  let packageId: string;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    const repository = new SubscriptionIssueRepository(database);
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
      repository,
      policy,
      integrity,
      reservations,
    );
    commerceRepository = new CommerceProjectionRepository(database);
    paymentService = new ActualPaymentService(
      repository,
      policy,
      integrity,
      commerceRepository,
    );
    const fixture = await createFixture(pool);
    actors = fixture.actors;
    studentId = fixture.studentId;
    profileId = fixture.profileId;
    packageId = fixture.packageId;
  });

  afterAll(async () => {
    if (pool) {
      await cleanupFixture(pool, {
        actorUserIds: actors
          ? roles.map((role) => actors[role].userId)
          : [],
        studentId,
        profileId,
      });
    }
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("issues 8000 - 20% = 6400 with exact installments and no revenue", async () => {
    const metadata = mutationMetadata("percent-installments");
    const input = {
      packageId,
      discount: {
        type: "percent" as const,
        percent: 20,
        reason: "Скидка владельца",
      },
      installments: [
        {
          dueAt: "2026-08-01T09:00:00.000Z",
          amountMinor: "320000",
        },
        {
          dueAt: "2026-09-01T09:00:00.000Z",
          amountMinor: "320000",
        },
      ],
      paymentMethod: "cashless" as const,
    };
    const first = await issueService.issue(
      actors.director,
      studentId,
      input,
      metadata,
    );
    const replay = await issueService.issue(
      actors.director,
      studentId,
      input,
      metadata,
    );

    expect(replay).toEqual(first);
    expect(first.subscription.commercialSnapshot).toMatchObject({
      basePriceMinor: "800000",
      finalPriceMinor: "640000",
      discount: {
        type: "percent",
        percentBasisPoints: 2000,
        reason: "Скидка владельца",
      },
      paymentMethod: "cashless",
    });
    expect(first.installments.map((item) => item.amountMinor)).toEqual([
      "320000",
      "320000",
    ]);
    expect(
      first.obligations.reduce(
        (sum, item) => sum + BigInt(item.amountMinor),
        0n,
      ),
    ).toBe(640000n);
    expect(first.balanceAtIssue).toEqual({
      currencyCode: "RUB",
      actualPaymentsMinor: "0",
      obligationsMinor: "640000",
      netMinor: "-640000",
    });

    const facts = await issueFactCounts(first.subscription.id);
    expect(facts).toEqual({
      subscriptions: 1,
      installments: 2,
      obligations: 2,
      lifecycle: 1,
      payments: 0,
      audits: 1,
      outbox: 1,
      idempotency: 1,
    });
    expect(await revenueMinor(first.subscription.id)).toBe("0");

    const payment = await paymentService.record(
      actors.director,
      studentId,
      {
        issuedSubscriptionId: first.subscription.id,
        amountMinor: "320000",
        method: "cashless",
        occurredAt: "2026-08-01T10:00:00.000Z",
      },
      mutationMetadata("first-installment-paid"),
    );
    const scope = await commerceRepository.resolveStudentScope(
      actors.director,
      studentId,
    );
    const projection = await commerceRepository.loadProjection(
      actors.director,
      [scope],
    );
    expect(
      projection[0]!.subscriptions[0]!.installments.map(
        (item) => item.status,
      ),
    ).toEqual(["paid", "pending"]);
    expect(projection[0]!.subscriptions[0]).toMatchObject({
      units: {
        total: "10.00",
        used: "0",
        reserved: "0",
        paid: "5.0000000000000000",
        available: "5.0000000000000000",
        remaining: "10.00",
      },
      financial: {
        actualPaidMinor: "320000",
        obligationMinor: "640000",
        debtMinor: "320000",
        overpaymentMinor: "0",
        nextPaymentAt: "2026-09-01T09:00:00+00:00",
      },
    });

    const adjustmentMetadata = mutationMetadata("refund-first-installment");
    const adjustmentInput = {
      sourcePaymentId: payment.payment.id,
      kind: "refund" as const,
      amountMinor: "100000",
      occurredAt: "2026-08-02T10:00:00.000Z",
      reason: "Возврат части первого платежа",
    };
    const adjustment = await paymentService.recordAdjustment(
      actors.director,
      studentId,
      adjustmentInput,
      adjustmentMetadata,
    );
    expect(
      await paymentService.recordAdjustment(
        actors.director,
        studentId,
        adjustmentInput,
        adjustmentMetadata,
      ),
    ).toEqual(adjustment);
    expect(adjustment.adjustment).toMatchObject({
      sourcePaymentId: payment.payment.id,
      kind: "refund",
      amountMinor: "-100000",
      status: "paid",
    });
    await expect(
      paymentService.recordAdjustment(
        actors.director,
        studentId,
        { ...adjustmentInput, amountMinor: "220001" },
        mutationMetadata("refund-over-remaining"),
      ),
    ).rejects.toMatchObject({
      response: { code: "PAYMENT_REFUND_EXCEEDS_AVAILABLE" },
    });
    await expect(
      pool.query(
        "update app.account_adjustments set description = 'rewrite' where id = $1",
        [adjustment.adjustment.id],
      ),
    ).rejects.toThrow("immutable commerce fact");

    const reconciled = await commerceRepository.loadProjection(
      actors.director,
      [scope],
    );
    const subscription = reconciled[0]!.subscriptions.find(
      (item) => item.id === first.subscription.id,
    )!;
    expect(Number(subscription.units.paid)).toBeCloseTo(3.4375);
    expect(Number(subscription.units.available)).toBeCloseTo(3.4375);
    expect(subscription.financial).toMatchObject({
      actualPaidMinor: "220000",
      debtMinor: "420000",
    });
    expect(reconciled[0]!.movements).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: adjustment.adjustment.id,
          kind: "refund",
          sourcePaymentId: payment.payment.id,
          issuedSubscriptionId: first.subscription.id,
        }),
      ]),
    );
  });

  it("reconciles a typed surcharge after a fixed discount", async () => {
    const result = await issueService.issue(
      actors.manager,
      studentId,
      {
        packageId,
        discount: {
          type: "fixed",
          fixedMinor: "160000",
          reason: "Фиксированная скидка",
        },
        surcharge: {
          amountMinor: "60000",
          reason: "Дополнительный урок",
        },
      },
      mutationMetadata("fixed-discount"),
    );

    expect(result.subscription.commercialSnapshot).toMatchObject({
      basePriceMinor: "800000",
      finalPriceMinor: "700000",
      discount: {
        type: "fixed",
        fixedMinor: "160000",
        reason: "Фиксированная скидка",
      },
      surcharge: {
        type: "fixed",
        amountMinor: "60000",
        reason: "Дополнительный урок",
      },
    });
    expect(result.installments).toEqual([]);
    expect(result.obligations).toHaveLength(1);
    expect(result.obligations[0]).toMatchObject({
      factType: "issue",
      direction: "debit",
      amountMinor: "700000",
    });
    expect(await revenueMinor(result.subscription.id)).toBe("0");
  });

  it("rejects invalid commercial terms atomically", async () => {
    const before = await countIssuedSubscriptions();
    await expect(
      issueService.issue(
        actors.director,
        studentId,
        {
          packageId,
          discount: {
            type: "percent",
            percent: 20,
            fixedMinor: "100",
            reason: "Две скидки",
          },
        },
        mutationMetadata("ambiguous-discount"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      issueService.issue(
        actors.director,
        studentId,
        {
          packageId,
          surcharge: {
            amountMinor: "60000",
            reason: "   ",
          },
        },
        mutationMetadata("missing-surcharge-reason"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      issueService.issue(
        actors.director,
        studentId,
        {
          packageId,
          surcharge: {
            amountMinor: "-1",
            reason: "Некорректная доплата",
          },
        },
        mutationMetadata("negative-surcharge"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      issueService.issue(
        actors.director,
        studentId,
        {
          packageId,
          discount: {
            type: "fixed",
            fixedMinor: "160000",
            reason: "   ",
          },
        },
        mutationMetadata("missing-reason"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      issueService.issue(
        actors.director,
        studentId,
        {
          packageId,
          discount: {
            type: "fixed",
            fixedMinor: "900000",
            reason: "Больше базы",
          },
        },
        mutationMetadata("negative-final"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      issueService.issue(
        actors.director,
        studentId,
        {
          packageId,
          installments: [
            {
              dueAt: "2026-08-01T09:00:00.000Z",
              amountMinor: "300000",
            },
            {
              dueAt: "2026-09-01T09:00:00.000Z",
              amountMinor: "300000",
            },
          ],
        },
        mutationMetadata("installment-mismatch"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(await countIssuedSubscriptions()).toBe(before);
  });

  it("records cash/cashless ActualPayment once and rejects key mismatch/destructive writes", async () => {
    const issued = await issueService.issue(
      actors.admin,
      studentId,
      { packageId },
      mutationMetadata("payment-target"),
    );
    const paymentMetadata = mutationMetadata("partial-payment-retry");
    const paymentInput = {
      issuedSubscriptionId: issued.subscription.id,
      amountMinor: "100000",
      method: "cash" as const,
      occurredAt: "2026-08-02T10:00:00.000Z",
      comment: "Оплата за август",
      invoiceIdentifier: "ЧЕК-3905",
    };
    const outcomes = await Promise.all([
      paymentService.record(
        actors.admin,
        studentId,
        paymentInput,
        paymentMetadata,
      ),
      paymentService.record(
        actors.admin,
        studentId,
        paymentInput,
        paymentMetadata,
      ),
    ]);
    expect(outcomes[1]).toEqual(outcomes[0]);
    expect(outcomes[0].payment).toMatchObject({
      studentId,
      issuedSubscriptionId: issued.subscription.id,
      amountMinor: "100000",
      currencyCode: "RUB",
      method: "cash",
      comment: "Оплата за август",
      invoiceIdentifier: "ЧЕК-3905",
      status: "paid",
      branchName: `${marker}-branch`,
      acceptedBy: expect.objectContaining({ userId: actors.admin.userId }),
      version: 1,
    });
    await expect(
      paymentService.record(
        actors.admin,
        studentId,
        { ...paymentInput, amountMinor: "100001" },
        paymentMetadata,
      ),
    ).rejects.toBeInstanceOf(ConflictException);
    await expect(
      paymentService.record(
        actors.admin,
        studentId,
        { ...paymentInput, branchId: randomUUID() },
        mutationMetadata("wrong-branch-payment"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);

    const cashless = await paymentService.record(
      actors.manager,
      studentId,
      {
        issuedSubscriptionId: issued.subscription.id,
        amountMinor: "50000",
        method: "cashless",
        occurredAt: "2026-08-03T10:00:00.000Z",
      },
      mutationMetadata("second-partial-payment"),
    );
    expect(cashless.payment.method).toBe("cashless");
    expect(await revenueMinor(issued.subscription.id)).toBe("150000");

    await expect(
      pool.query(
        "update app.payments set amount_minor = amount_minor + 1 where id = $1",
        [outcomes[0].payment.id],
      ),
    ).rejects.toMatchObject({ code: "23514" });
    await expect(
      pool.query("delete from app.payments where id = $1", [
        outcomes[0].payment.id,
      ]),
    ).rejects.toMatchObject({ code: "23514" });
    const count = await pool.query<{ count: string }>(
      `
        select count(*)::text as count
        from app.payments
        where issued_subscription_id = $1
      `,
      [issued.subscription.id],
    );
    expect(count.rows[0]!.count).toBe("2");
  });

  it("allows Admin/Manager/Director/system_admin and denies Teacher/client", async () => {
    for (const role of issuingRoles) {
      const issued = await issueService.issue(
        actors[role],
        studentId,
        { packageId },
        mutationMetadata(`role-${role}-issue`),
      );
      await expect(
        paymentService.record(
          actors[role],
          studentId,
          {
            issuedSubscriptionId: issued.subscription.id,
            amountMinor: "100",
            method: role === "admin" ? "cash" : "cashless",
            occurredAt: "2026-08-04T10:00:00.000Z",
          },
          mutationMetadata(`role-${role}-payment`),
        ),
      ).resolves.toMatchObject({
        payment: {
          studentId,
          issuedSubscriptionId: issued.subscription.id,
        },
      });
    }
    for (const role of ["teacher", "client"] as const) {
      await expect(
        issueService.issue(
          actors[role],
          studentId,
          { packageId },
          mutationMetadata(`role-${role}-issue`),
        ),
      ).rejects.toBeInstanceOf(ForbiddenException);
      await expect(
        paymentService.record(
          actors[role],
          studentId,
          {
            issuedSubscriptionId: "00000000-0000-4000-8000-000000000001",
            amountMinor: "100",
            method: "cash",
            occurredAt: "2026-08-04T10:00:00.000Z",
          },
          mutationMetadata(`role-${role}-payment`),
        ),
      ).rejects.toBeInstanceOf(ForbiddenException);
    }
  });

  function mutationMetadata(suffix: string) {
    return {
      idempotencyKey: `${marker}:${suffix}`,
      requestId: `${marker}:${suffix}:request`,
    };
  }

  async function issueFactCounts(issuedSubscriptionId: string) {
    const result = await pool.query<{
      subscriptions: string;
      installments: string;
      obligations: string;
      lifecycle: string;
      payments: string;
      audits: string;
      outbox: string;
      idempotency: string;
    }>(
      `
        select
          (
            select count(*) from app.subscriptions
            where id = $1
          )::text as subscriptions,
          (
            select count(*) from app.subscription_installments
            where issued_subscription_id = $1
          )::text as installments,
          (
            select count(*) from app.subscription_obligation_facts
            where issued_subscription_id = $1
          )::text as obligations,
          (
            select count(*) from app.subscription_lifecycle_events
            where issued_subscription_id = $1 and event_type = 'issue'
          )::text as lifecycle,
          (
            select count(*) from app.payments
            where issued_subscription_id = $1
          )::text as payments,
          (
            select count(*) from app.audit_events
            where entity_id = $1::text
          )::text as audits,
          (
            select count(*) from app.platform_outbox_events
            where aggregate_id = $1::text
          )::text as outbox,
          (
            select count(*) from app.idempotency_records
            where result_ref ->> 'entityId' = $1::text
          )::text as idempotency
      `,
      [issuedSubscriptionId],
    );
    return Object.fromEntries(
      Object.entries(result.rows[0]!).map(([key, value]) => [
        key,
        Number(value),
      ]),
    );
  }

  async function revenueMinor(issuedSubscriptionId: string): Promise<string> {
    const result = await pool.query<{ revenue_minor: string }>(
      `
        select coalesce(sum(amount_minor), 0)::text as revenue_minor
        from app.payments
        where issued_subscription_id = $1
      `,
      [issuedSubscriptionId],
    );
    return result.rows[0]!.revenue_minor;
  }

  async function countIssuedSubscriptions(): Promise<number> {
    const result = await pool.query<{ count: string }>(
      `
        select count(*)::text as count
        from app.subscriptions subscription
        join app.subscription_packages package
          on package.id = subscription.package_id
        where package.name like $1
      `,
      [`${marker}%`],
    );
    return Number(result.rows[0]!.count);
  }
});

async function createFixture(pool: Pool): Promise<{
  actors: Record<UserRole, ActorContext>;
  studentId: string;
  profileId: string;
  packageId: string;
}> {
  const client = await pool.connect();
  await client.query("begin");
  try {
    const actors = {} as Record<UserRole, ActorContext>;
    for (const role of roles) {
      const result = await client.query<{ id: string }>(
        `
          insert into app.users (email, role, email_verified_at)
          values ($1, $2, now())
          returning id
        `,
        [`${marker}-${role}@example.test`, role],
      );
      actors[role] = { userId: result.rows[0]!.id, role };
    }
    const branch = await client.query<{ id: string }>(
      `insert into app.branches (name, timezone_name)
       values ($1, 'Europe/Moscow') returning id`,
      [`${marker}-branch`],
    );
    for (const role of ["admin", "manager"] as const) {
      const staffProfile = await client.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name)
         values ($1, $2, 'Payment') returning id`,
        [actors[role].userId, role],
      );
      const staff = await client.query<{ id: string }>(
        `insert into app.staff_members (profile_id, role)
         values ($1, $2) returning id`,
        [staffProfile.rows[0]!.id, role],
      );
      await client.query(
        `insert into app.staff_branch_assignments (staff_member_id, branch_id)
         values ($1, $2)`,
        [staff.rows[0]!.id, branch.rows[0]!.id],
      );
    }
    const profile = await client.query<{ id: string }>(
      `
        insert into app.profiles (
          user_id,
          first_name,
          last_name
        )
        values ($1, 'Issue', 'Client')
        returning id
      `,
      [actors.client.userId],
    );
    const student = await client.query<{ id: string }>(
      `
        insert into app.students (profile_id, status, branch_id)
        values ($1, 'active', $2)
        returning id
      `,
      [profile.rows[0]!.id, branch.rows[0]!.id],
    );
    const packageResult = await client.query<{ id: string }>(
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
        values ($1, 10, 800000, 'RUB', 90, true, 1)
        returning id
      `,
      [`${marker}-8000-rub`],
    );
    await client.query("commit");
    return {
      actors,
      profileId: profile.rows[0]!.id,
      studentId: student.rows[0]!.id,
      packageId: packageResult.rows[0]!.id,
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
  input: {
    actorUserIds: string[];
    studentId?: string;
    profileId?: string;
  },
): Promise<void> {
  const client = await pool.connect();
  await client.query("begin");
  try {
    await client.query("set local session_replication_role = replica");
    const packages = await client.query<{ id: string }>(
      "select id from app.subscription_packages where name like $1",
      [`${marker}%`],
    );
    const packageIds = packages.rows.map((row) => row.id);
    const subscriptions =
      packageIds.length === 0
        ? { rows: [] as { id: string }[] }
        : await client.query<{ id: string }>(
            `
              select id
              from app.subscriptions
              where package_id = any($1::uuid[])
            `,
            [packageIds],
          );
    const subscriptionIds = subscriptions.rows.map((row) => row.id);
    const payments = input.studentId
      ? await client.query<{ id: string }>(
          `
            select id
            from app.payments
            where student_id = $1 and idempotency_ref is not null
          `,
          [input.studentId],
        )
      : { rows: [] as { id: string }[] };
    const paymentIds = payments.rows.map((row) => row.id);
    const adjustments = input.studentId
      ? await client.query<{ id: string }>(
          `select id from app.account_adjustments
           where student_id = $1 and idempotency_ref is not null`,
          [input.studentId],
        )
      : { rows: [] as { id: string }[] };
    const adjustmentIds = adjustments.rows.map((row) => row.id);
    const aggregateIds = [
      ...subscriptionIds,
      ...paymentIds,
      ...adjustmentIds,
    ];

    await deleteByIds(
      client,
      "app.idempotency_records",
      "actor_key",
      input.actorUserIds,
      "text",
    );
    await deleteByIds(
      client,
      "app.platform_outbox_events",
      "aggregate_id",
      aggregateIds,
      "text",
    );
    await deleteByIds(
      client,
      "app.audit_events",
      "entity_id",
      aggregateIds,
      "text",
    );
    await deleteByIds(
      client,
      "app.aggregate_versions",
      "aggregate_id",
      aggregateIds,
      "text",
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
    await deleteByIds(
      client,
      "app.account_adjustments",
      "id",
      adjustmentIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.payments",
      "id",
      paymentIds,
      "uuid",
    );
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
      packageIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscription_packages",
      "id",
      packageIds,
      "uuid",
    );
    if (input.studentId) {
      await client.query("delete from app.students where id = $1", [
        input.studentId,
      ]);
    }
    if (input.profileId) {
      await client.query("delete from app.profiles where id = $1", [
        input.profileId,
      ]);
    }
    await client.query(
      `delete from app.staff_branch_assignments
       where staff_member_id in (
         select staff.id from app.staff_members staff
         join app.profiles profile on profile.id = staff.profile_id
         where profile.user_id = any($1::uuid[])
       )`,
      [input.actorUserIds],
    );
    await client.query(
      `delete from app.staff_members
       where profile_id in (
         select id from app.profiles where user_id = any($1::uuid[])
       )`,
      [input.actorUserIds],
    );
    await client.query(
      `delete from app.profiles where user_id = any($1::uuid[])`,
      [input.actorUserIds],
    );
    await deleteByIds(
      client,
      "app.users",
      "id",
      input.actorUserIds,
      "uuid",
    );
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
