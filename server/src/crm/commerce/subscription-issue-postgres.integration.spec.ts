import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
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
import { InstallmentDueWorker } from "./installment-due.worker";
import { PaymentLifecycleRepository } from "./payment-lifecycle.repository";
import { PaymentLifecycleService } from "./payment-lifecycle.service";
import { PaymentReversalRepository } from "./payment-reversal.repository";
import { PaymentReversalService } from "./payment-reversal.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionIssueService } from "./subscription-issue.service";
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
  throw new Error("Subscription issue tests require local PostgreSQL.");
}

const marker = `v4-subscription-issue-${randomUUID()}`;
const previewSecret = "purchase-preview-test-secret-at-least-32-bytes";
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
  let issueRepository: SubscriptionIssueRepository;
  let issueService: SubscriptionIssueService;
  let paymentService: ActualPaymentService;
  let paymentLifecycle: PaymentLifecycleService;
  let paymentReversal: PaymentReversalService;
  let dueWorker: InstallmentDueWorker;
  let commerceRepository: CommerceProjectionRepository;
  let actors: Record<UserRole, ActorContext>;
  let studentId: string;
  let profileId: string;
  let packageId: string;
  let payerStudentId: string;
  let racePayerStudentId: string;
  let outsideStudentId: string;
  let extraProfileIds: string[];
  let extraBranchIds: string[];
  let extraUserIds: string[];

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);
    issueRepository = new SubscriptionIssueRepository(database);
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
    const previewTokens = new SubscriptionPreviewTokenService({
      get: (key: string, fallback?: string) =>
        key === "COMMERCE_PREVIEW_SECRET" ? previewSecret : fallback,
    } as unknown as ConfigService);
    issueService = new SubscriptionIssueService(
      issueRepository,
      policy,
      integrity,
      reservations,
      previewTokens,
    );
    commerceRepository = new CommerceProjectionRepository(database);
    const paymentRepository = new PaymentLifecycleRepository(
      database,
      new PlatformIntegrityRepository(),
    );
    paymentLifecycle = new PaymentLifecycleService(
      paymentRepository,
      issueRepository,
      policy,
      integrity,
      commerceRepository,
      reservations,
    );
    paymentReversal = new PaymentReversalService(
      new PaymentReversalRepository(database),
      issueRepository,
      commerceRepository,
      policy,
      integrity,
      previewTokens,
      reservations,
    );
    dueWorker = new InstallmentDueWorker(paymentRepository, reservations);
    paymentService = new ActualPaymentService(
      issueRepository,
      policy,
      integrity,
      commerceRepository,
      paymentLifecycle,
    );
    const fixture = await createFixture(pool);
    actors = fixture.actors;
    studentId = fixture.studentId;
    profileId = fixture.profileId;
    packageId = fixture.packageId;
    payerStudentId = fixture.payerStudentId;
    racePayerStudentId = fixture.racePayerStudentId;
    outsideStudentId = fixture.outsideStudentId;
    extraProfileIds = fixture.extraProfileIds;
    extraBranchIds = fixture.extraBranchIds;
    extraUserIds = fixture.extraUserIds;
  });

  afterAll(async () => {
    if (pool) {
      await cleanupFixture(pool, {
        actorUserIds: actors
          ? [
              ...roles.map((role) => actors[role].userId),
              ...(extraUserIds ?? []),
            ]
          : [],
        studentId,
        profileId,
        extraStudentIds: [payerStudentId, racePayerStudentId, outsideStudentId],
        extraProfileIds,
        extraBranchIds,
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
    ).toEqual(["paid", "scheduled"]);
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
        debtMinor: "0",
        pendingMinor: "0",
        remainingObligationMinor: "320000",
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
      debtMinor: "0",
      remainingObligationMinor: "420000",
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

  it("materializes due installments once and serializes paid/unpaid verification", async () => {
    const issued = await issueService.issue(
      actors.director,
      studentId,
      {
        packageId,
        installments: [
          { dueAt: "2030-01-01T09:00:00.000Z", amountMinor: "400000" },
          { dueAt: "2031-01-01T09:00:00.000Z", amountMinor: "400000" },
        ],
      },
      mutationMetadata("payment-lifecycle-subscription"),
    );

    await Promise.all([
      dueWorker.runOnce(new Date("2030-06-01T00:00:00.000Z"), 100),
      dueWorker.runOnce(new Date("2030-06-01T00:00:00.000Z"), 100),
    ]);
    const first = await pool.query<{
      id: string;
      status: "posted_pending";
      version: string;
    }>(
      `select id, status, version::text
       from app.client_payment_records
       where installment_id = $1`,
      [issued.installments[0]!.id],
    );
    expect(first.rows).toHaveLength(1);
    expect(first.rows[0]).toMatchObject({
      status: "posted_pending",
      version: "1",
    });
    expect(
      await pool.query(
        "select id from app.client_payment_records where installment_id = $1",
        [issued.installments[1]!.id],
      ),
    ).toHaveProperty("rowCount", 0);
    await expect(
      paymentLifecycle.create(
        actors.director,
        studentId,
        {
          issuedSubscriptionId: issued.subscription.id,
          installmentId: issued.installments[0]!.id,
          amountMinor: "400000",
          status: "posted_pending",
          reason: "Повторная ручная фиксация той же части",
        },
        mutationMetadata("duplicate-installment-record"),
      ),
    ).rejects.toBeInstanceOf(ConflictException);

    const transitions = await Promise.allSettled([
      paymentLifecycle.transition(
        actors.admin,
        studentId,
        first.rows[0]!.id,
        {
          expectedVersion: 1,
          targetStatus: "paid",
          method: "cashless",
          externalIdentifier: `${marker}-verify-admin`,
          occurredAt: "2030-06-01T10:00:00.000Z",
          reason: "Платёж рассрочки проверен администратором",
        },
        mutationMetadata("payment-verify-admin"),
      ),
      paymentLifecycle.transition(
        actors.manager,
        studentId,
        first.rows[0]!.id,
        {
          expectedVersion: 1,
          targetStatus: "paid",
          method: "cashless",
          externalIdentifier: `${marker}-verify-manager`,
          occurredAt: "2030-06-01T10:00:00.000Z",
          reason: "Платёж рассрочки проверен управляющим",
        },
        mutationMetadata("payment-verify-manager"),
      ),
    ]);
    expect(transitions.filter((item) => item.status === "fulfilled")).toHaveLength(1);
    expect(transitions.filter((item) => item.status === "rejected")).toHaveLength(1);
    const paid = await pool.query<{
      status: string;
      actual_payment_id: string;
      events: string;
      payments: string;
    }>(
      `select record.status, record.actual_payment_id,
         (select count(*)::text from app.client_payment_status_events event
          where event.payment_record_id = record.id) as events,
         (select count(*)::text from app.payments payment
          where payment.payment_record_id = record.id) as payments
       from app.client_payment_records record where record.id = $1`,
      [first.rows[0]!.id],
    );
    expect(paid.rows[0]).toMatchObject({
      status: "paid",
      events: "2",
      payments: "1",
    });
    const paymentProjection = await commerceRepository.loadProjection(
      actors.admin,
      [await commerceRepository.resolveStudentScope(actors.admin, studentId)],
    );
    expect(
      paymentProjection[0]!.movements.find(
        (movement) => movement.id === first.rows[0]!.id,
      ),
    ).toMatchObject({
      kind: "payment_record",
      status: "paid",
      paymentRecordVersion: 2,
      installmentId: issued.installments[0]!.id,
      dueAt: "2030-01-01T09:00:00+00:00",
    });

    await dueWorker.runOnce(new Date("2032-01-01T00:00:00.000Z"), 100);
    const second = await pool.query<{ id: string }>(
      "select id from app.client_payment_records where installment_id = $1",
      [issued.installments[1]!.id],
    );
    expect(second.rows).toHaveLength(1);
    await paymentLifecycle.transition(
      actors.admin,
      studentId,
      second.rows[0]!.id,
      {
        expectedVersion: 1,
        targetStatus: "unpaid",
        reason: "Платёж по рассрочке не поступил",
      },
      mutationMetadata("payment-mark-unpaid"),
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
      projection[0]!.subscriptions.find(
        (item) => item.id === issued.subscription.id,
      )!.financial,
    ).toMatchObject({
      actualPaidMinor: "400000",
      pendingMinor: "0",
      debtMinor: "400000",
      remainingObligationMinor: "400000",
    });
    await expect(
      paymentLifecycle.transition(
        actors.director,
        studentId,
        first.rows[0]!.id,
        {
          expectedVersion: 2,
          targetStatus: "unpaid",
          reason: "Недопустимая отмена подтверждённой оплаты",
        },
        mutationMetadata("paid-is-immutable"),
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
  });

  it("creates and replays a manual pending record before marking it debt", async () => {
    const input = {
      amountMinor: "12345",
      currencyCode: "RUB",
      status: "posted_pending" as const,
      dueAt: "2026-08-07T09:00:00.000Z",
      verificationNote: "Проверить ручной перевод",
      reason: "Клиент сообщил о переводе",
    };
    const mutation = mutationMetadata("manual-pending-payment");
    const created = await paymentLifecycle.create(
      actors.director,
      payerStudentId,
      input,
      mutation,
    );
    expect(
      await paymentLifecycle.create(
        actors.director,
        payerStudentId,
        input,
        mutation,
      ),
    ).toEqual(created);
    expect(created).toMatchObject({
      paymentRecord: { status: "posted_pending", version: 1 },
      actualPayment: null,
      statusHistory: [{ reason: "Клиент сообщил о переводе" }],
    });
    const unpaid = await paymentLifecycle.transition(
      actors.admin,
      payerStudentId,
      created.paymentRecord.id,
      {
        expectedVersion: 1,
        targetStatus: "unpaid",
        reason: "Перевод не найден в банке",
      },
      mutationMetadata("manual-payment-unpaid"),
    );
    expect(unpaid).toMatchObject({
      paymentRecord: { status: "unpaid", version: 2 },
      actualPayment: null,
      statusHistory: [
        { afterStatus: "posted_pending" },
        { afterStatus: "unpaid", reason: "Перевод не найден в банке" },
      ],
    });
    const scope = await commerceRepository.resolveStudentScope(
      actors.director,
      payerStudentId,
    );
    expect(
      (await commerceRepository.loadProjection(actors.director, [scope]))[0]!
        .accounts,
    ).toEqual([
      expect.objectContaining({
        currencyCode: "RUB",
        pendingMinor: "0",
        debtMinor: "12345",
        balanceMinor: "0",
      }),
    ]);
  });

  it("reverses one paid fact exactly once and excludes it from ordinary reads", async () => {
    const created = await paymentLifecycle.create(
      actors.admin,
      studentId,
      {
        amountMinor: "23456",
        currencyCode: "RUB",
        status: "paid",
        method: "cashless",
        externalIdentifier: `${marker}-reversal-payment`,
        occurredAt: "2026-08-07T12:00:00.000Z",
        reason: "Оплата для проверки сторно",
      },
      mutationMetadata("reversal-paid-source"),
    );
    const preview = await paymentReversal.preview(
      actors.admin,
      studentId,
      created.paymentRecord.id,
      { expectedVersion: 1 },
      new Date("2026-08-07T12:01:00.000Z"),
    );
    expect(preview).toMatchObject({
      paymentRecordId: created.paymentRecord.id,
      operation: "monetary_reversal",
      walletDeltaMinor: "-23456",
    });
    const commands = [
      mutationMetadata("reversal-paid-admin"),
      mutationMetadata("reversal-paid-manager"),
    ];
    const attempts = await Promise.allSettled(
      commands.map((metadata) =>
        paymentReversal.reverse(
          actors.admin,
          studentId,
          created.paymentRecord.id,
          {
            previewToken: preview.previewToken,
            confirm: true,
            reason: "Дублирующая ошибочная оплата",
          },
          metadata,
        ),
      ),
    );
    expect(attempts.filter((item) => item.status === "fulfilled")).toHaveLength(1);
    expect(attempts.filter((item) => item.status === "rejected")).toHaveLength(1);
    const winnerIndex = attempts.findIndex((item) => item.status === "fulfilled");
    const winner = attempts[winnerIndex] as PromiseFulfilledResult<{
      exclusion: { id: string; auditEventId: string };
    }>;
    const winningActor = actors.admin;
    const replay = await paymentReversal.reverse(
      winningActor,
      studentId,
      created.paymentRecord.id,
      {
        previewToken: preview.previewToken,
        confirm: true,
        reason: "Дублирующая ошибочная оплата",
      },
      commands[winnerIndex]!,
    );
    expect(replay).toMatchObject({
      operation: "monetary_reversal",
      replayed: true,
      exclusion: { id: winner.value.exclusion.id },
    });

    const facts = await pool.query<{
      payments: string;
      adjustments: string;
      exclusions: string;
      ordinary_payments: string;
      ordinary_adjustments: string;
      ordinary_records: string;
      audits: string;
    }>(
      `
        select
          (select count(*)::text from app.payments
           where id = $1) as payments,
          (select count(*)::text from app.account_adjustments
           where source_payment_id = $1) as adjustments,
          (select count(*)::text from app.commerce_reporting_exclusions
           where source_kind = 'payment' and source_id = $1) as exclusions,
          (select count(*)::text from app.commerce_ordinary_payments
           where id = $1) as ordinary_payments,
          (select count(*)::text from app.commerce_ordinary_account_adjustments
           where source_payment_id = $1) as ordinary_adjustments,
          (select count(*)::text from app.commerce_ordinary_payment_records
           where id = $2) as ordinary_records,
          (select count(*)::text from app.audit_events
           where id = $3 and action = 'crm.payment_reversed') as audits
      `,
      [
        created.actualPayment!.id,
        created.paymentRecord.id,
        winner.value.exclusion.auditEventId,
      ],
    );
    expect(facts.rows[0]).toEqual({
      payments: "1",
      adjustments: "1",
      exclusions: "1",
      ordinary_payments: "0",
      ordinary_adjustments: "0",
      ordinary_records: "0",
      audits: "1",
    });
    const scope = await commerceRepository.resolveStudentScope(
      actors.director,
      studentId,
    );
    const [projection] = await commerceRepository.loadProjection(
      actors.director,
      [scope],
    );
    expect(
      projection!.movements.some((item) =>
        [created.paymentRecord.id, created.actualPayment!.id].includes(item.id),
      ),
    ).toBe(false);
    expect(projection!.technicalHistory).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          paymentRecordId: created.paymentRecord.id,
          eventType: "monetary_reversal",
          reason: "Дублирующая ошибочная оплата",
          actorUserId: winningActor.userId,
        }),
      ]),
    );
    await expect(
      paymentLifecycle.transition(
        actors.admin,
        studentId,
        created.paymentRecord.id,
        {
          expectedVersion: 1,
          targetStatus: "unpaid",
          reason: "Попытка изменить удалённую оплату",
        },
        mutationMetadata("reversal-paid-transition"),
      ),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("technically voids a due marker and materializes one replacement", async () => {
    const issued = await issueService.issue(
      actors.director,
      studentId,
      {
        packageId,
        installments: [
          { dueAt: "2040-01-01T09:00:00.000Z", amountMinor: "400000" },
          { dueAt: "2041-01-01T09:00:00.000Z", amountMinor: "400000" },
        ],
      },
      mutationMetadata("reversal-due-subscription"),
    );
    const dueAt = new Date("2040-02-01T00:00:00.000Z");
    await dueWorker.runOnce(dueAt, 100);
    const first = await pool.query<{ id: string }>(
      `select id from app.commerce_ordinary_payment_records
       where installment_id = $1`,
      [issued.installments[0]!.id],
    );
    const preview = await paymentReversal.preview(
      actors.manager,
      studentId,
      first.rows[0]!.id,
      { expectedVersion: 1 },
      dueAt,
    );
    expect(preview.operation).toBe("technical_void");
    await paymentReversal.reverse(
      actors.manager,
      studentId,
      first.rows[0]!.id,
      {
        previewToken: preview.previewToken,
        confirm: true,
        reason: "Неверно созданная часть рассрочки",
      },
      mutationMetadata("reversal-due-marker"),
    );
    await dueWorker.runOnce(dueAt, 100);
    const records = await pool.query<{ id: string; ordinary: boolean }>(
      `
        select record.id, ordinary.id is not null as ordinary
        from app.client_payment_records record
        left join app.commerce_ordinary_payment_records ordinary
          on ordinary.id = record.id
        where record.installment_id = $1
        order by record.created_at, record.id
      `,
      [issued.installments[0]!.id],
    );
    expect(records.rows).toHaveLength(2);
    expect(records.rows.filter((row) => row.ordinary)).toHaveLength(1);
    expect(records.rows.find((row) => row.ordinary)!.id).not.toBe(
      first.rows[0]!.id,
    );
  });

  it("purchases once from another client personal account and replays safely", async () => {
    await fundWallet(payerStudentId, "cross-account", "800000");
    const input = {
      packageId,
      payerStudentId,
      fundingMode: "personal_account" as const,
      purchaseReason: "Родитель оплачивает обучение ребёнка",
      paymentMethod: "cashless" as const,
    };
    const preview = await issueService.previewPurchase(
      actors.admin,
      studentId,
      input,
    );
    expect(preview).toMatchObject({
      recipientStudentId: studentId,
      payerStudentId,
      finalPriceMinor: "800000",
      payerBalanceMinor: "800000",
      balanceAfterMinor: "0",
      canCommit: true,
      shortageMinor: "0",
    });

    const metadata = mutationMetadata("cross-account-purchase");
    const command = {
      ...input,
      previewToken: preview.previewToken,
      confirm: true as const,
    };
    const first = await issueService.purchase(
      actors.admin,
      studentId,
      command,
      metadata,
    );
    expect(
      await issueService.purchase(
        actors.admin,
        studentId,
        command,
        metadata,
      ),
    ).toEqual(first);
    expect(first.subscription).toMatchObject({
      studentId,
      payerStudentId,
      fundingMode: "personal_account",
      purchaseReason: "Родитель оплачивает обучение ребёнка",
      unitCount: 10,
    });
    expect(first.obligations).toEqual([
      expect.objectContaining({
        factType: "issue",
        amountMinor: "800000",
        sourceType: "subscription.purchase",
      }),
    ]);
    const facts = await pool.query<{
      debit_count: string;
      payer_student_id: string;
    }>(
      `
        select count(obligation.id)::text as debit_count,
               subscription.payer_student_id
        from app.subscriptions subscription
        join app.subscription_obligation_facts obligation
          on obligation.issued_subscription_id = subscription.id
        where subscription.id = $1
        group by subscription.payer_student_id
      `,
      [first.subscription.id],
    );
    expect(facts.rows[0]).toEqual({
      debit_count: "1",
      payer_student_id: payerStudentId,
    });
    await expect(
      pool.query<{ reason: string; reason_text: string }>(
        `select reason, reason_text
         from app.audit_events
         where action = 'crm.subscription_purchased'
           and entity_id = $1`,
        [first.subscription.id],
      ),
    ).resolves.toMatchObject({
      rows: [
        {
          reason: "subscription_purchase",
          reason_text: "Родитель оплачивает обучение ребёнка",
        },
      ],
    });
  });

  it("rejects an unfunded personal-account purchase without partial facts", async () => {
    const input = {
      packageId,
      payerStudentId: outsideStudentId,
      fundingMode: "personal_account" as const,
      purchaseReason: "Проверка недостаточного остатка",
    };
    const preview = await issueService.previewPurchase(
      actors.director,
      studentId,
      input,
    );
    expect(preview).toMatchObject({
      canCommit: false,
      payerBalanceMinor: "0",
      shortageMinor: "800000",
    });
    const before = await countIssuedSubscriptions();
    await expect(
      issueService.purchase(
        actors.director,
        studentId,
        { ...input, previewToken: preview.previewToken, confirm: true },
        mutationMetadata("unfunded-purchase"),
      ),
    ).rejects.toMatchObject({
      response: { code: "INSUFFICIENT_PERSONAL_ACCOUNT_BALANCE" },
    });
    expect(await countIssuedSubscriptions()).toBe(before);
  });

  it("rechecks current finance capability when a previewed purchase commits", async () => {
    const input = {
      packageId,
      payerStudentId: studentId,
      fundingMode: "installment" as const,
      purchaseReason: "Проверка отзыва доступа",
      installments: [
        {
          dueAt: "2026-12-15T09:00:00.000Z",
          amountMinor: "400000",
        },
        {
          dueAt: "2027-01-15T09:00:00.000Z",
          amountMinor: "400000",
        },
      ],
    };
    const preview = await issueService.previewPurchase(
      actors.admin,
      studentId,
      input,
    );
    const before = await countIssuedSubscriptions();
    await pool.query(
      `
        insert into app.user_capability_overrides (
          user_id,
          capability_key,
          capability_version,
          effect,
          reason_code,
          actor_user_id
        )
        values ($1, 'commerce.client_finance.write', 1, 'deny', 'test.revoked', $2)
      `,
      [actors.admin.userId, actors.director.userId],
    );
    try {
      await expect(
        issueService.purchase(
          actors.admin,
          studentId,
          { ...input, previewToken: preview.previewToken, confirm: true },
          mutationMetadata("revoked-after-preview"),
        ),
      ).rejects.toMatchObject({
        response: {
          code: "CAPABILITY_DENIED",
          capabilityKey: "commerce.client_finance.write",
        },
      });
      await expect(countIssuedSubscriptions()).resolves.toBe(before);
    } finally {
      await pool.query(
        `delete from app.user_capability_overrides
          where user_id = $1
            and capability_key = 'commerce.client_finance.write'
            and reason_code = 'test.revoked'`,
        [actors.admin.userId],
      );
    }
  });

  it("serializes competing purchases so only one can spend the payer balance", async () => {
    await fundWallet(racePayerStudentId, "race", "800000");
    const input = {
      packageId,
      payerStudentId: racePayerStudentId,
      fundingMode: "personal_account" as const,
      purchaseReason: "Общий семейный счёт",
    };
    const [leftPreview, rightPreview] = await Promise.all([
      issueService.previewPurchase(actors.director, studentId, input),
      issueService.previewPurchase(actors.director, studentId, input),
    ]);
    const outcomes = await Promise.allSettled([
      issueService.purchase(
        actors.director,
        studentId,
        {
          ...input,
          previewToken: leftPreview.previewToken,
          confirm: true,
        },
        mutationMetadata("race-left"),
      ),
      issueService.purchase(
        actors.director,
        studentId,
        {
          ...input,
          previewToken: rightPreview.previewToken,
          confirm: true,
        },
        mutationMetadata("race-right"),
      ),
    ]);
    expect(outcomes.filter((item) => item.status === "fulfilled")).toHaveLength(
      1,
    );
    const rejected = outcomes.find((item) => item.status === "rejected");
    expect(rejected).toMatchObject({
      reason: {
        response: { code: "PURCHASE_PREVIEW_STALE" },
      },
    });
    const debits = await pool.query<{ count: string }>(
      `
        select count(*)::text as count
        from app.subscription_obligation_facts
        where student_id = $1 and source_type = 'subscription.purchase'
      `,
      [racePayerStudentId],
    );
    expect(debits.rows[0]!.count).toBe("1");
  });

  it("locks reversed recipient/payer pairs in one order without deadlock", async () => {
    const installments = [
      { dueAt: "2026-10-01T09:00:00.000Z", amountMinor: "400000" },
      { dueAt: "2026-11-01T09:00:00.000Z", amountMinor: "400000" },
    ];
    const left = {
      packageId,
      payerStudentId,
      fundingMode: "installment" as const,
      purchaseReason: "Семейная рассрочка A",
      installments,
    };
    const right = {
      packageId,
      payerStudentId: studentId,
      fundingMode: "installment" as const,
      purchaseReason: "Семейная рассрочка B",
      installments,
    };
    const [leftPreview, rightPreview] = await Promise.all([
      issueService.previewPurchase(actors.director, studentId, left),
      issueService.previewPurchase(actors.director, payerStudentId, right),
    ]);
    await expect(
      Promise.all([
        issueService.purchase(
          actors.director,
          studentId,
          { ...left, previewToken: leftPreview.previewToken, confirm: true },
          mutationMetadata("reverse-lock-left"),
        ),
        issueService.purchase(
          actors.director,
          payerStudentId,
          { ...right, previewToken: rightPreview.previewToken, confirm: true },
          mutationMetadata("reverse-lock-right"),
        ),
      ]),
    ).resolves.toHaveLength(2);
  });

  it("rolls every purchase fact back on a fault and enforces both client scopes", async () => {
    await expect(
      issueService.previewPurchase(actors.admin, studentId, {
        packageId,
        payerStudentId: outsideStudentId,
        fundingMode: "personal_account",
        purchaseReason: "Чужой филиал",
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    const input = {
      packageId,
      payerStudentId,
      fundingMode: "installment" as const,
      purchaseReason: "Проверка атомарности",
      installments: [
        { dueAt: "2026-12-01T09:00:00.000Z", amountMinor: "400000" },
        { dueAt: "2027-01-01T09:00:00.000Z", amountMinor: "400000" },
      ],
    };
    const preview = await issueService.previewPurchase(
      actors.director,
      studentId,
      input,
    );
    const before = await countIssuedSubscriptions();
    const fault = jest
      .spyOn(issueRepository, "createIssueLifecycle")
      .mockRejectedValueOnce(new Error("fault after debit"));
    await expect(
      issueService.purchase(
        actors.director,
        studentId,
        { ...input, previewToken: preview.previewToken, confirm: true },
        mutationMetadata("atomic-fault"),
      ),
    ).rejects.toThrow("fault after debit");
    fault.mockRestore();
    expect(await countIssuedSubscriptions()).toBe(before);
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

  async function fundWallet(
    targetStudentId: string,
    suffix: string,
    availableMinor: string,
  ): Promise<void> {
    const issued = await issueService.issue(
      actors.director,
      targetStudentId,
      { packageId },
      mutationMetadata(`${suffix}-funding-subscription`),
    );
    await paymentService.record(
      actors.director,
      targetStudentId,
      {
        issuedSubscriptionId: issued.subscription.id,
        amountMinor: (800000n + BigInt(availableMinor)).toString(),
        method: "cashless",
        occurredAt: "2026-08-05T10:00:00.000Z",
      },
      mutationMetadata(`${suffix}-wallet-credit`),
    );
  }

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
  payerStudentId: string;
  racePayerStudentId: string;
  outsideStudentId: string;
  extraProfileIds: string[];
  extraBranchIds: string[];
  extraUserIds: string[];
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
    const outsideBranch = await client.query<{ id: string }>(
      `insert into app.branches (name, timezone_name)
       values ($1, 'Europe/Moscow') returning id`,
      [`${marker}-outside-branch`],
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
    const extraStudents: {
      userId: string;
      profileId: string;
      studentId: string;
    }[] = [];
    for (const [label, branchId] of [
      ["Payer", branch.rows[0]!.id],
      ["RacePayer", branch.rows[0]!.id],
      ["Outside", outsideBranch.rows[0]!.id],
    ] as const) {
      const extraUser = await client.query<{ id: string }>(
        `insert into app.users (email, role, email_verified_at)
         values ($1, 'client', now()) returning id`,
        [`${marker}-${label.toLowerCase()}@example.test`],
      );
      const extraProfile = await client.query<{ id: string }>(
        `insert into app.profiles (user_id, first_name, last_name)
         values ($1, $2, 'Client') returning id`,
        [extraUser.rows[0]!.id, `${marker}-${label}`],
      );
      const extraStudent = await client.query<{ id: string }>(
        `insert into app.students (profile_id, status, branch_id)
         values ($1, 'active', $2) returning id`,
        [extraProfile.rows[0]!.id, branchId],
      );
      extraStudents.push({
        userId: extraUser.rows[0]!.id,
        profileId: extraProfile.rows[0]!.id,
        studentId: extraStudent.rows[0]!.id,
      });
    }
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
      payerStudentId: extraStudents[0]!.studentId,
      racePayerStudentId: extraStudents[1]!.studentId,
      outsideStudentId: extraStudents[2]!.studentId,
      extraProfileIds: extraStudents.map((item) => item.profileId),
      extraBranchIds: [outsideBranch.rows[0]!.id],
      extraUserIds: extraStudents.map((item) => item.userId),
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
    extraStudentIds?: string[];
    extraProfileIds?: string[];
    extraBranchIds?: string[];
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
    const studentIds = [input.studentId, ...(input.extraStudentIds ?? [])]
      .filter((id): id is string => Boolean(id));
    const payments = studentIds.length > 0
      ? await client.query<{ id: string }>(
          `
            select id
            from app.payments
            where student_id = any($1::uuid[]) and idempotency_ref is not null
          `,
          [studentIds],
        )
      : { rows: [] as { id: string }[] };
    const paymentIds = payments.rows.map((row) => row.id);
    const adjustments = studentIds.length > 0
      ? await client.query<{ id: string }>(
          `select id from app.account_adjustments
           where student_id = any($1::uuid[]) and idempotency_ref is not null`,
          [studentIds],
        )
      : { rows: [] as { id: string }[] };
    const adjustmentIds = adjustments.rows.map((row) => row.id);
    const paymentRecords = studentIds.length > 0
      ? await client.query<{ id: string }>(
          `select id from app.client_payment_records
           where student_id = any($1::uuid[])`,
          [studentIds],
        )
      : { rows: [] as { id: string }[] };
    const paymentRecordIds = paymentRecords.rows.map((row) => row.id);
    const aggregateIds = [
      ...subscriptionIds,
      ...paymentIds,
      ...adjustmentIds,
      ...paymentRecordIds,
    ];

    await client.query(
      `delete from app.commerce_reporting_exclusions
       where source_id = any($1::uuid[])
          or counterpart_id = any($1::uuid[])`,
      [[...paymentIds, ...adjustmentIds, ...paymentRecordIds]],
    );

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
    if (studentIds.length > 0) {
      await client.query("delete from app.students where id = any($1::uuid[])", [
        studentIds,
      ]);
    }
    const profileIds = [input.profileId, ...(input.extraProfileIds ?? [])]
      .filter((id): id is string => Boolean(id));
    if (profileIds.length > 0) {
      await client.query("delete from app.profiles where id = any($1::uuid[])", [
        profileIds,
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
    await deleteByIds(
      client,
      "app.branches",
      "id",
      input.extraBranchIds ?? [],
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
