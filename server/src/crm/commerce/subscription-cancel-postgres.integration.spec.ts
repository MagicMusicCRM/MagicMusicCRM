import {
  ConflictException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import { resolve } from "node:path";
import { Pool, PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { runPreflight } from "../../platform/rollout/v4/preflight";
import { reconcileV7Commerce } from "../../migration/commerce/v7/commerce-data";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ActualPaymentService } from "./actual-payment.service";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import { PaymentLifecycleRepository } from "./payment-lifecycle.repository";
import { PaymentLifecycleService } from "./payment-lifecycle.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionIssueService } from "./subscription-issue.service";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";
import { SubscriptionCancellationPolicy } from "./subscription-cancellation.policy";
import { SubscriptionReplacementPolicy } from "./subscription-replacement.policy";
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
  let paymentLifecycle: PaymentLifecycleService;
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
    const commands = new SubscriptionLifecycleCommandPolicy();
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
    paymentLifecycle = new PaymentLifecycleService(
      new PaymentLifecycleRepository(
        database,
        new PlatformIntegrityRepository(),
      ),
      issueRepository,
      policy,
      integrity,
      commerceRepository,
      reservations,
    );
    paymentService = new ActualPaymentService(
      issueRepository,
      policy,
      integrity,
      commerceRepository,
      paymentLifecycle,
    );
    lifecycleService = new SubscriptionLifecycleService(
      new SubscriptionLifecycleRepository(database),
      issueRepository,
      policy,
      integrity,
      new SubscriptionPreviewTokenService({
        get: (key: string, fallback?: string) =>
          key === "COMMERCE_PREVIEW_SECRET" ? previewSecret : fallback,
      } as unknown as ConfigService),
      reservations,
      commands,
      new SubscriptionReplacementPolicy(),
      new SubscriptionCancellationPolicy(),
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

  it("creates one cancellation credit, releases reservations and preserves historical facts", async () => {
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
      refundMinor: "0",
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
    expect(first.cancellation).toMatchObject({
      issuedSubscriptionId: issued.subscription.id,
      version: 2,
      status: "cancelled",
      payerStudentId: fixture.studentId,
      releasedReservationCount: 1,
      releasedReservationUnits: "2",
      futureLessonCount: 2,
      closedPaymentRecordCount: 0,
      confirmedFundedMinor: "600000",
      previousRefundMinor: "0",
      unusedUnits: "7",
      unfundedCancellationMinor: "140000",
      chosenRefundMinor: "0",
      totalCreditMinor: "140000",
      creditFactId: expect.any(String),
    });
    expect(await immutableState(
      pool,
      fixture.studentId,
      issued.subscription.id,
    )).toEqual({
      ...financeBefore,
      obligationCount: String(Number(financeBefore.obligationCount) + 1),
      obligationCreditMinor: "140000",
    });
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

  it("refunds an unused personal-account purchase to the original payer", async () => {
    await paymentLifecycle.create(
      actor,
      fixture.otherStudentId,
      {
        amountMinor: "800000",
        currencyCode: "RUB",
        status: "paid",
        method: "cashless",
        occurredAt: "2026-08-12T09:00:00.000Z",
        externalIdentifier: `${marker}-personal-funding`,
        reason: "Пополнение личного счёта плательщика",
      },
      metadata("personal-funding"),
    );
    const purchaseInput = {
      packageId: fixture.sourcePackageId,
      payerStudentId: fixture.otherStudentId,
      fundingMode: "personal_account" as const,
      purchaseReason: "Родитель оплатил абонемент ученика",
    };
    const purchasePreview = await issueService.previewPurchase(
      actor,
      fixture.studentId,
      purchaseInput,
    );
    const purchased = await issueService.purchase(
      actor,
      fixture.studentId,
      {
        ...purchaseInput,
        previewToken: purchasePreview.previewToken,
        confirm: true,
      },
      metadata("personal-purchase"),
    );
    const preview = await lifecycleService.previewCancellation(
      actor,
      fixture.studentId,
      purchased.subscription.id,
    );
    expect(preview.financial).toMatchObject({
      payerStudentId: fixture.otherStudentId,
      fundingMode: "personal_account",
      actualPaidMinor: "0",
      confirmedFundedMinor: "800000",
      previousRefundMinor: "0",
      unusedValueMinor: "800000",
      unfundedCancellationMinor: "0",
      recommendedRefundMinor: "800000",
    });

    const result = await lifecycleService.cancel(
      actor,
      fixture.studentId,
      purchased.subscription.id,
      {
        expectedVersion: preview.expectedVersion,
        previewToken: preview.previewToken,
        confirm: true,
        reason: "Абонемент назначен ошибочно, вернуть плательщику",
        refundMinor: "800000",
      },
      metadata("personal-cancel"),
    );
    expect(result.cancellation).toMatchObject({
      payerStudentId: fixture.otherStudentId,
      confirmedFundedMinor: "800000",
      unfundedCancellationMinor: "0",
      chosenRefundMinor: "800000",
      totalCreditMinor: "800000",
      closedPaymentRecordCount: 0,
    });
    const facts = await pool.query<{
      payer_student_id: string;
      credit_minor: string;
      linked_payment_count: string;
      reason: string;
      audit_reason_text: string;
    }>(
      `
        select
          credit.student_id as payer_student_id,
          credit.amount_minor::text as credit_minor,
          (select count(*)::text from app.payments payment
           where payment.issued_subscription_id = subscription.id)
            as linked_payment_count,
          lifecycle.reason,
          (select audit.reason_text
           from app.audit_events audit
           where audit.action = 'crm.subscription_cancelled'
             and audit.entity_id = subscription.id::text)
            as audit_reason_text
        from app.subscriptions subscription
        join app.subscription_obligation_facts credit
          on credit.issued_subscription_id = subscription.id
         and credit.source_type = 'subscription.cancel'
        join app.subscription_lifecycle_events lifecycle
          on lifecycle.issued_subscription_id = subscription.id
         and lifecycle.event_type = 'cancel'
        where subscription.id = $1
      `,
      [purchased.subscription.id],
    );
    expect(facts.rows[0]).toEqual({
      payer_student_id: fixture.otherStudentId,
      credit_minor: "800000",
      linked_payment_count: "0",
      reason: "Абонемент назначен ошибочно, вернуть плательщику",
      audit_reason_text: "Абонемент назначен ошибочно, вернуть плательщику",
    });
  });

  it("caps an installment refund, closes open payments and credits once", async () => {
    const purchaseInput = {
      packageId: fixture.sourcePackageId,
      payerStudentId: fixture.otherStudentId,
      fundingMode: "installment" as const,
      purchaseReason: "Оплата частями другим клиентом",
      installments: [
        { dueAt: "2035-01-10T09:00:00.000Z", amountMinor: "400000" },
        { dueAt: "2035-02-10T09:00:00.000Z", amountMinor: "400000" },
      ],
    };
    const purchasePreview = await issueService.previewPurchase(
      actor,
      fixture.studentId,
      purchaseInput,
    );
    const purchased = await issueService.purchase(
      actor,
      fixture.studentId,
      {
        ...purchaseInput,
        previewToken: purchasePreview.previewToken,
        confirm: true,
      },
      metadata("installment-purchase"),
    );
    const paid = await paymentLifecycle.create(
      actor,
      fixture.otherStudentId,
      {
        issuedSubscriptionId: purchased.subscription.id,
        installmentId: purchased.installments[0]!.id,
        amountMinor: "400000",
        status: "paid",
        method: "cashless",
        externalIdentifier: `${marker}-installment-paid`,
        occurredAt: "2026-08-13T09:00:00.000Z",
        reason: "Первая часть рассрочки подтверждена",
      },
      metadata("installment-paid"),
    );
    const unpaid = await paymentLifecycle.create(
      actor,
      fixture.otherStudentId,
      {
        issuedSubscriptionId: purchased.subscription.id,
        installmentId: purchased.installments[1]!.id,
        amountMinor: "400000",
        status: "unpaid",
        reason: "Вторая часть не поступила",
      },
      metadata("installment-unpaid"),
    );
    const pending = await paymentLifecycle.create(
      actor,
      fixture.otherStudentId,
      {
        issuedSubscriptionId: purchased.subscription.id,
        amountMinor: "100000",
        status: "posted_pending",
        reason: "Дополнительный перевод ожидает проверки",
      },
      metadata("installment-pending"),
    );
    await paymentService.recordAdjustment(
      actor,
      fixture.otherStudentId,
      {
        sourcePaymentId: paid.actualPayment!.id,
        kind: "refund",
        amountMinor: "100000",
        occurredAt: "2026-08-14T09:00:00.000Z",
        reason: "Предыдущий частичный возврат",
      },
      metadata("installment-previous-refund"),
    );
    await seedConsumedUnits(
      pool,
      fixture.studentId,
      purchased.subscription.id,
      "2",
    );
    await seedFutureLessons(
      pool,
      fixture.studentId,
      purchased.subscription.id,
      [{ units: "1", reserved: true }],
    );

    const preview = await lifecycleService.previewCancellation(
      actor,
      fixture.studentId,
      purchased.subscription.id,
    );
    expect(preview).toMatchObject({
      usage: { usedUnits: "2", reservedUnits: "1", unusedUnits: "7" },
      financial: {
        payerStudentId: fixture.otherStudentId,
        fundingMode: "installment",
        actualPaidMinor: "400000",
        confirmedFundedMinor: "400000",
        previousRefundMinor: "100000",
        unusedValueMinor: "560000",
        unfundedCancellationMinor: "380000",
        recommendedRefundMinor: "180000",
      },
      openPayments: { count: 2, amountMinor: "500000" },
    });
    await expect(
      lifecycleService.cancel(
        actor,
        fixture.studentId,
        purchased.subscription.id,
        {
          expectedVersion: preview.expectedVersion,
          previewToken: preview.previewToken,
          confirm: true,
          reason: "Запрошен недопустимо большой возврат",
          refundMinor: "180001",
        },
        metadata("installment-over-cap"),
      ),
    ).rejects.toMatchObject({
      response: { code: "CANCELLATION_REFUND_EXCEEDS_CAP" },
    });

    const command = {
      expectedVersion: preview.expectedVersion,
      previewToken: preview.previewToken,
      confirm: true as const,
      reason: "Клиент прекратил обучение, согласован частичный возврат",
      refundMinor: "150000",
    };
    const operation = metadata("installment-cancel");
    const first = await lifecycleService.cancel(
      actor,
      fixture.studentId,
      purchased.subscription.id,
      command,
      operation,
    );
    expect(
      await lifecycleService.cancel(
        actor,
        fixture.studentId,
        purchased.subscription.id,
        command,
        operation,
      ),
    ).toEqual({ ...first, replayed: true });
    expect(first.cancellation).toMatchObject({
      payerStudentId: fixture.otherStudentId,
      closedPaymentRecordCount: 2,
      previousRefundMinor: "100000",
      unfundedCancellationMinor: "380000",
      chosenRefundMinor: "150000",
      totalCreditMinor: "530000",
    });
    const openIds = [
      unpaid.paymentRecord.id,
      pending.paymentRecord.id,
    ];
    const facts = await pool.query<{
      credits: string;
      credit_minor: string;
      credit_payer: string;
      exclusions: string;
      ordinary_open: string;
      ordinary_paid: string;
      reason: string;
    }>(
      `
        select
          (select count(*)::text
           from app.subscription_obligation_facts fact
           where fact.issued_subscription_id = $1
             and fact.source_type = 'subscription.cancel') as credits,
          (select amount_minor::text
           from app.subscription_obligation_facts fact
           where fact.issued_subscription_id = $1
             and fact.source_type = 'subscription.cancel') as credit_minor,
          (select student_id::text
           from app.subscription_obligation_facts fact
           where fact.issued_subscription_id = $1
             and fact.source_type = 'subscription.cancel') as credit_payer,
          (select count(*)::text
           from app.commerce_reporting_exclusions exclusion
           where exclusion.source_kind = 'payment_record'
             and exclusion.source_id = any($2::uuid[])) as exclusions,
          (select count(*)::text
           from app.commerce_ordinary_payment_records record
           where record.id = any($2::uuid[])) as ordinary_open,
          (select count(*)::text
           from app.commerce_ordinary_payment_records record
           where record.id = $3) as ordinary_paid,
          (select reason
           from app.subscription_lifecycle_events event
           where event.issued_subscription_id = $1
             and event.event_type = 'cancel') as reason
      `,
      [purchased.subscription.id, openIds, paid.paymentRecord.id],
    );
    expect(facts.rows[0]).toEqual({
      credits: "1",
      credit_minor: "530000",
      credit_payer: fixture.otherStudentId,
      exclusions: "2",
      ordinary_open: "0",
      ordinary_paid: "1",
      reason: "Клиент прекратил обучение, согласован частичный возврат",
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
      refundMinor: "0",
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

  it("repairs a late legacy aggregate before cancellation", async () => {
    const issued = await issue("late-legacy-aggregate");
    await pool.query(
      `delete from app.aggregate_versions
       where aggregate_type = 'commerce:issued-subscription'
         and aggregate_id = $1::text`,
      [issued.subscription.id],
    );
    const driftBeforeRepair = (await runPreflight(pool)).checks.find(
      (check) => check.id === "commerce.v7-subscription-version-drift",
    );
    expect(driftBeforeRepair?.rows).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ entityId: issued.subscription.id }),
      ]),
    );
    expect(await reconcile()).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          issueCode: "subscription_aggregate_version_mismatch",
          entityId: issued.subscription.id,
        }),
      ]),
    );
    const repairSql = await fs
      .readFile(
        resolve(
          process.cwd(),
          "db/migrations/0139_repair_issued_subscription_aggregate_versions.up.sql",
        ),
        "utf8",
      )
      .catch(() => "select 1;");
    await pool.query(repairSql);
    const driftAfterRepair = (await runPreflight(pool)).checks.find(
      (check) => check.id === "commerce.v7-subscription-version-drift",
    );
    expect(driftAfterRepair?.rows).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({ entityId: issued.subscription.id }),
      ]),
    );
    expect(await reconcile()).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          issueCode: "subscription_aggregate_version_mismatch",
          entityId: issued.subscription.id,
        }),
      ]),
    );

    const preview = await lifecycleService.previewCancellation(
      actor,
      fixture.studentId,
      issued.subscription.id,
    );
    const result = await lifecycleService.cancel(
      actor,
      fixture.studentId,
      issued.subscription.id,
      {
        expectedVersion: preview.expectedVersion,
        previewToken: preview.previewToken,
        confirm: true,
        reason: "legacy.aggregate.repaired",
        refundMinor: "0",
      },
      metadata("late-legacy-aggregate-cancel"),
    );

    expect(result.cancellation).toMatchObject({
      issuedSubscriptionId: issued.subscription.id,
      status: "cancelled",
      version: 2,
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

  async function reconcile() {
    const client = await pool.connect();
    try {
      return await reconcileV7Commerce(client);
    } finally {
      client.release();
    }
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
          coalesce(
            (
              select max(existing.scheduled_at)
              from app.lessons existing
              where existing.student_id = $1
                and existing.scheduled_at > now()
            ),
            now()
          ) + make_interval(days => $2::integer),
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
    const otherStudentId = await insertStudent(
      client,
      otherProfile,
      branch.rows[0]!.id,
    );
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
    await deleteByIds(
      client,
      "app.issued_subscription_aggregate_version_repair",
      "subscription_id",
      subscriptionIds,
      "uuid",
    );
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
    const adjustments = await client.query<{ id: string }>(
      "select id from app.account_adjustments where student_id = any($1::uuid[])",
      [[fixture.studentId, fixture.otherStudentId]],
    );
    const adjustmentIds = adjustments.rows.map((row) => row.id);
    const paymentRecords = await client.query<{ id: string }>(
      "select id from app.client_payment_records where student_id = any($1::uuid[])",
      [[fixture.studentId, fixture.otherStudentId]],
    );
    const paymentRecordIds = paymentRecords.rows.map((row) => row.id);
    await client.query(
      "delete from app.commerce_reporting_exclusions where actor_user_id = $1",
      [fixture.actor.userId],
    );
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
      [
        ...subscriptionIds,
        ...paymentIds,
        ...paymentRecordIds,
        ...adjustmentIds,
      ],
      "text",
    );
    await client.query("delete from app.audit_events where actor_user_id = $1", [
      fixture.actor.userId,
    ]);
    await deleteByIds(
      client,
      "app.aggregate_versions",
      "aggregate_id",
      [
        ...subscriptionIds,
        ...paymentIds,
        ...paymentRecordIds,
        ...adjustmentIds,
      ],
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
    await deleteByIds(
      client,
      "app.account_adjustments",
      "id",
      adjustmentIds,
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
