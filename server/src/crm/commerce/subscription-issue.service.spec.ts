import { NotFoundException } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import {
  IssueSubscriptionDto,
  PurchaseSubscriptionCommandDto,
  PurchaseSubscriptionPreviewDto,
} from "../dto/issue-subscription.dto";
import { SubscriptionCommercialTermsService } from "./subscription-commercial-terms.service";
import { PaymentLifecycleRepository } from "./payment-lifecycle.repository";
import { SubscriptionPurchasePaymentService } from "./subscription-purchase-payment.service";
import { SubscriptionPurchasePersistenceService } from "./subscription-purchase-persistence.service";
import { SubscriptionPurchaseTermsService } from "./subscription-purchase-terms.service";
import { SubscriptionGrantCommandService } from "./subscription-grant-command.service";
import { SubscriptionIssueResultService } from "./subscription-issue-result.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import {
  CommerceMutationMetadata,
  SubscriptionIssueService,
} from "./subscription-issue.service";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionPurchaseCommandService } from "./subscription-purchase-command.service";
import { SubscriptionPurchasePreviewService } from "./subscription-purchase-preview.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const RECIPIENT_ID = "11111111-1111-4111-8111-111111111111";
const PAYER_ID = "22222222-2222-4222-8222-222222222222";
const PACKAGE_ID = "33333333-3333-4333-8333-333333333333";
const ACTOR_ID = "44444444-4444-4444-8444-444444444444";
const SUBSCRIPTION_ID = "55555555-5555-4555-8555-555555555555";

interface HarnessOptions {
  omitPaymentDate?: boolean;
  payerBalanceMinor?: string;
  paymentAmountMinor?: string;
  replayed?: boolean;
  tokenActorUserId?: string;
  tokenPayerBalanceMinor?: string;
}

function createHarness(options: HarnessOptions = {}) {
  const actor: ActorContext = { userId: ACTOR_ID, role: "director" };
  const recipientStudentId = RECIPIENT_ID;
  const packageRow = {
    id: PACKAGE_ID,
    name: "Абонемент на 8 занятий",
    branch_id: null,
    lessons_total: 8,
    base_price_minor: "8000",
    currency_code: "RUB",
    validity_days: 30,
    version: 1,
  };
  const students = [
    { id: RECIPIENT_ID, version: 1, branch_id: null },
    { id: PAYER_ID, version: 1, branch_id: null },
  ];
  const payerBalanceMinor = options.payerBalanceMinor ?? "10000";
  const paymentAmountMinor = options.paymentAmountMinor ?? "3000";
  const expectedPaymentAmountMinor = paymentAmountMinor;
  const previewDto: PurchaseSubscriptionPreviewDto = {
    packageId: PACKAGE_ID,
    payerStudentId: PAYER_ID,
    fundingMode: "personal_account",
    startsAt: "2026-08-26",
    expiresAt: "2026-09-26",
    paymentAmountMinor,
    paymentOccurredAt:
      options.omitPaymentDate || paymentAmountMinor === "0"
        ? undefined
        : "2026-08-26T12:00:00.000Z",
    paymentMethod: paymentAmountMinor === "0" ? undefined : "cashless",
    paymentComment: "Оплата при продаже",
    purchaseReason: "Оплата другим клиентом",
  };
  const commandDto: PurchaseSubscriptionCommandDto = {
    ...previewDto,
    previewToken: "signed-preview-token",
    confirm: true,
  };
  const issueDto: IssueSubscriptionDto = { packageId: PACKAGE_ID };
  const metadata: CommerceMutationMetadata = {
    idempotencyKey: "subscription-test-key",
    requestId: "subscription-test-request",
  };
  const repository = {
    readPurchasePreviewContext: jest.fn().mockResolvedValue({
      students,
      package: packageRow,
      payerBalanceMinor,
    }),
    lockPurchaseStudents: jest
      .fn()
      .mockImplementation(
        async (
          _client: unknown,
          _actor: ActorContext,
          ids: readonly string[],
        ) => students.filter((student) => ids.includes(student.id)),
      ),
    assertStudentsInScope: jest.fn().mockResolvedValue(undefined),
    findActivePackageForShare: jest.fn().mockResolvedValue(packageRow),
    readAccountBalance: jest.fn().mockResolvedValue(payerBalanceMinor),
    createIssuedSubscription: jest.fn().mockResolvedValue({
      id: SUBSCRIPTION_ID,
    }),
    createActualPayment: jest.fn().mockResolvedValue({
      id: "66666666-6666-4666-8666-666666666666",
    }),
    createInstallments: jest.fn().mockResolvedValue([]),
    createObligations: jest.fn().mockResolvedValue([]),
    createIssueLifecycle: jest.fn().mockResolvedValue(undefined),
    findIssuedSubscription: jest.fn().mockResolvedValue({
      id: SUBSCRIPTION_ID,
      student_id: RECIPIENT_ID,
      payer_student_id: PAYER_ID,
      funding_mode: "personal_account",
      purchase_reason: "Оплата другим клиентом",
      package_id: PACKAGE_ID,
      lessons_total: 8,
      lessons_used: 0,
      starts_at: "2026-08-26",
      expires_at: "2026-09-25",
      status: "active",
      version: 1,
      commercial_snapshot: {
        snapshotVersion: 1,
        packageVersion: 1,
        displayName: "Абонемент на 8 занятий",
        unitCount: "8",
        validityDays: 30,
        basePriceMinor: "8000",
        currencyCode: "RUB",
        discount: { type: "none" },
        surcharge: { type: "none" },
        finalPriceMinor: "8000",
        installments: [],
        paymentMethod: null,
        commercialRules: {},
      },
      created_at: "2026-08-26T12:00:00.000Z",
    }),
    listInstallments: jest.fn().mockResolvedValue([]),
    listObligations: jest.fn().mockResolvedValue([]),
    listActualPaymentsForSubscription: jest
      .fn()
      .mockResolvedValue(
        expectedPaymentAmountMinor === "0"
          ? []
          : [{ amount_minor: expectedPaymentAmountMinor }],
      ),
  };
  const policy = { assertCanWriteCrm: jest.fn() };
  const previewTokens = {
    issuePurchase: jest.fn().mockReturnValue({
      token: "signed-preview-token",
      expiresAt: "2026-08-26T12:10:00.000Z",
    }),
    verifyPurchase: jest.fn(),
  };
  const reservations = {
    publishPostCommit: jest.fn().mockResolvedValue(undefined),
  };
  const paymentLifecycle = {
    createRecord: jest.fn().mockResolvedValue({
      id: "77777777-7777-4777-8777-777777777777",
      status: "paid",
    }),
    linkActualPayment: jest.fn().mockResolvedValue(undefined),
    appendStatusEvent: jest.fn().mockResolvedValue(undefined),
    initializeRecordAggregate: jest.fn().mockResolvedValue(undefined),
  };
  const terms = new SubscriptionCommercialTermsService(
    new SubscriptionPurchaseTermsService(),
  );
  const preview = new SubscriptionPurchasePreviewService(
    repository as unknown as SubscriptionIssueRepository,
    policy as unknown as CrmPolicy,
    terms,
    previewTokens as unknown as SubscriptionPreviewTokenService,
  );
  const normalized = terms.normalizePurchase(
    recipientStudentId,
    previewDto,
    packageRow,
  );
  previewTokens.verifyPurchase.mockReturnValue({
    ...preview.createTokenPayload(
      actor,
      recipientStudentId,
      previewDto,
      {
        students,
        package: packageRow,
        payerBalanceMinor: options.tokenPayerBalanceMinor ?? payerBalanceMinor,
      },
      normalized,
    ),
    actorUserId: options.tokenActorUserId ?? actor.userId,
    issuedAtSeconds: Math.floor(Date.now() / 1_000),
    expiresAtSeconds: Math.floor(Date.now() / 1_000) + 600,
  });
  const results = new SubscriptionIssueResultService(
    repository as unknown as SubscriptionIssueRepository,
  ) as SubscriptionIssueResultService & { load: jest.Mock };
  jest.spyOn(results, "load");
  const integrity = {
    executeVersionedMutation: jest.fn().mockImplementation(async (command) => {
      const resultRef = options.replayed
        ? { entityId: SUBSCRIPTION_ID, version: 1 }
        : await command.mutate({} as never, 1);
      return {
        resultRef,
        version: 1,
        replayed: options.replayed ?? false,
        auditId: "audit-id",
        eventId: "event-id",
      };
    }),
  };
  const purchase = new SubscriptionPurchaseCommandService(
    repository as unknown as SubscriptionIssueRepository,
    policy as unknown as CrmPolicy,
    integrity as unknown as PlatformIntegrityService,
    reservations as unknown as SubscriptionReservationService,
    preview,
    terms,
    results,
    new SubscriptionPurchasePersistenceService(
      repository as unknown as SubscriptionIssueRepository,
      new SubscriptionPurchasePaymentService(
        repository as unknown as SubscriptionIssueRepository,
        paymentLifecycle as unknown as PaymentLifecycleRepository,
      ),
    ),
  );
  const grant = new SubscriptionGrantCommandService(
    repository as unknown as SubscriptionIssueRepository,
    policy as unknown as CrmPolicy,
    integrity as unknown as PlatformIntegrityService,
    reservations as unknown as SubscriptionReservationService,
    terms,
    results,
  );
  const service = new SubscriptionIssueService(preview, purchase, grant);
  return {
    actor,
    commandDto,
    integrity,
    issueDto,
    metadata,
    packageRow,
    previewDto,
    recipientStudentId,
    repository,
    paymentLifecycle,
    reservations,
    results,
    service,
    terms,
  };
}

describe("SubscriptionIssueService", () => {
  it("keeps an omitted student payment amount at zero while explicit payment controls it", () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-08-29T10:15:00.000Z"));
    try {
      const harness = createHarness();
      const legacy = harness.terms.normalizePurchase(
        harness.recipientStudentId,
        {
          ...harness.previewDto,
          paymentAmountMinor: undefined,
          paymentOccurredAt: undefined,
          paymentMethod: "cashless",
        },
        harness.packageRow,
      );
      const explicitZero = harness.terms.normalizePurchase(
        harness.recipientStudentId,
        {
          ...harness.previewDto,
          paymentAmountMinor: "0",
          paymentOccurredAt: undefined,
          paymentMethod: "cashless",
        },
        harness.packageRow,
      );

      expect(legacy.payment).toMatchObject({
        amountMinor: "0",
        method: null,
        occurredAt: null,
      });
      expect(explicitZero.payment).toMatchObject({
        amountMinor: "0",
        method: null,
        occurredAt: null,
      });
    } finally {
      jest.useRealTimers();
    }
  });

  it("isolates legacy lead auto-payment behind the internal normalization mode", () => {
    const harness = createHarness();
    const legacyDto = harness.terms.bindPurchaseDefaults(
      {
        ...harness.previewDto,
        payerStudentId: harness.recipientStudentId,
        paymentAmountMinor: undefined,
        paymentOccurredAt: undefined,
        paymentMethod: undefined,
      },
      new Date("2026-08-29T10:15:00.000Z"),
      true,
    );
    const legacyLead = harness.terms.normalizePurchase(
      harness.recipientStudentId,
      legacyDto,
      harness.packageRow,
      true,
    );

    expect(legacyLead.payment).toEqual({
      amountMinor: "8000",
      method: null,
      occurredAt: new Date("2026-08-29T10:15:00.000Z"),
      comment: "Оплата при продаже",
    });
  });

  it("uses the Moscow business date for an omitted legacy start date", () => {
    const harness = createHarness();
    const bound = harness.terms.bindPurchaseDefaults(
      {
        ...harness.previewDto,
        startsAt: undefined,
        paymentAmountMinor: undefined,
        paymentOccurredAt: undefined,
      },
      new Date("2026-08-29T21:30:00.000Z"),
    );

    expect(bound.startsAt).toBe("2026-08-30");
  });

  it("binds an omitted explicit-payment date to the signed preview", async () => {
    jest.useFakeTimers().setSystemTime(new Date("2026-08-29T10:15:00.000Z"));
    try {
      const harness = createHarness({ omitPaymentDate: true });
      jest.setSystemTime(new Date("2026-08-29T10:15:05.000Z"));

      await expect(
        harness.service.purchase(
          harness.actor,
          harness.recipientStudentId,
          harness.commandDto,
          harness.metadata,
        ),
      ).resolves.toBeDefined();
      expect(harness.repository.createActualPayment).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          amountMinor: "3000",
          occurredAt: new Date("2026-08-29T10:15:00.000Z"),
        }),
      );
    } finally {
      jest.useRealTimers();
    }
  });

  it("rejects an explicit public payment without a payment method", async () => {
    const harness = createHarness();

    await expect(
      harness.service.previewPurchase(
        harness.actor,
        harness.recipientStudentId,
        {
          ...harness.previewDto,
          paymentAmountMinor: "3000",
          paymentOccurredAt: undefined,
          paymentMethod: undefined,
        },
      ),
    ).rejects.toMatchObject({
      response: { code: "PAYMENT_METHOD_REQUIRED" },
    });
  });

  it("previewPurchase allows partial payment and reports the remaining debt", async () => {
    const harness = createHarness({ payerBalanceMinor: "0" });
    const response = await harness.service.previewPurchase(
      harness.actor,
      harness.recipientStudentId,
      harness.previewDto,
    );

    expect(response).toMatchObject({
      finalPriceMinor: "8000",
      payerBalanceMinor: "0",
      paidNowMinor: "3000",
      balanceAfterMinor: "-5000",
      canCommit: true,
      shortageMinor: "5000",
      debtMinor: "5000",
      overpaymentMinor: "0",
      previewToken: "signed-preview-token",
      previewExpiresAt: "2026-08-26T12:10:00.000Z",
    });
    expect(harness.integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("purchase rejects a preview bound to another actor before creating facts", async () => {
    const harness = createHarness({ tokenActorUserId: "another-user" });

    await expect(
      harness.service.purchase(
        harness.actor,
        harness.recipientStudentId,
        harness.commandDto,
        harness.metadata,
      ),
    ).rejects.toMatchObject({
      response: { code: "PREVIEW_TOKEN_SCOPE_MISMATCH" },
    });
    expect(harness.repository.createIssuedSubscription).not.toHaveBeenCalled();
    expect(harness.repository.createInstallments).not.toHaveBeenCalled();
    expect(harness.repository.createObligations).not.toHaveBeenCalled();
    expect(harness.repository.createIssueLifecycle).not.toHaveBeenCalled();
  });

  it("purchase rejects stale student, package or balance facts before creating facts", async () => {
    const harness = createHarness({ tokenPayerBalanceMinor: "9000" });

    await expect(
      harness.service.purchase(
        harness.actor,
        harness.recipientStudentId,
        harness.commandDto,
        harness.metadata,
      ),
    ).rejects.toMatchObject({ response: { code: "PURCHASE_PREVIEW_STALE" } });
    expect(harness.repository.createIssuedSubscription).not.toHaveBeenCalled();
    expect(harness.repository.createInstallments).not.toHaveBeenCalled();
    expect(harness.repository.createObligations).not.toHaveBeenCalled();
    expect(harness.repository.createIssueLifecycle).not.toHaveBeenCalled();
  });

  it("purchase writes subscription, installments, obligations and lifecycle in that order", async () => {
    const harness = createHarness();
    await harness.service.purchase(
      harness.actor,
      harness.recipientStudentId,
      harness.commandDto,
      harness.metadata,
    );

    expect(
      harness.repository.createIssuedSubscription.mock.invocationCallOrder[0],
    ).toBeLessThan(
      harness.repository.createInstallments.mock.invocationCallOrder[0],
    );
    expect(
      harness.repository.createInstallments.mock.invocationCallOrder[0],
    ).toBeLessThan(
      harness.repository.createObligations.mock.invocationCallOrder[0],
    );
    expect(
      harness.repository.createObligations.mock.invocationCallOrder[0],
    ).toBeLessThan(
      harness.repository.createIssueLifecycle.mock.invocationCallOrder[0],
    );
    expect(
      harness.integrity.executeVersionedMutation.mock.invocationCallOrder[0],
    ).toBeLessThan(harness.results.load.mock.invocationCallOrder[0]);
    expect(harness.repository.createIssuedSubscription).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        startsAt: "2026-08-26",
        expiresAt: "2026-09-26",
      }),
    );
    expect(harness.repository.createActualPayment).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        studentId: PAYER_ID,
        issuedSubscriptionId: SUBSCRIPTION_ID,
        amountMinor: "3000",
        method: "cashless",
        comment: "Оплата при продаже",
      }),
    );
    expect(harness.paymentLifecycle.createRecord).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        studentId: PAYER_ID,
        issuedSubscriptionId: SUBSCRIPTION_ID,
        amountMinor: "3000",
        status: "paid",
      }),
    );
    expect(harness.paymentLifecycle.linkActualPayment).toHaveBeenCalledTimes(1);
    expect(harness.paymentLifecycle.appendStatusEvent).toHaveBeenCalledTimes(1);
    expect(
      harness.paymentLifecycle.initializeRecordAggregate,
    ).toHaveBeenCalledTimes(1);
  });

  it("purchase with zero paid now creates the subscription without a fake payment", async () => {
    const harness = createHarness({ paymentAmountMinor: "0" });

    await harness.service.purchase(
      harness.actor,
      harness.recipientStudentId,
      harness.commandDto,
      harness.metadata,
    );

    expect(harness.repository.createIssuedSubscription).toHaveBeenCalledTimes(
      1,
    );
    expect(harness.repository.createActualPayment).not.toHaveBeenCalled();
    expect(harness.paymentLifecycle.createRecord).not.toHaveBeenCalled();
  });

  it("purchase result reports the actual payment instead of a zero placeholder", async () => {
    const harness = createHarness();

    const response = await harness.service.purchase(
      harness.actor,
      harness.recipientStudentId,
      harness.commandDto,
      harness.metadata,
    );

    expect(response.balanceAtIssue).toEqual({
      currencyCode: "RUB",
      actualPaymentsMinor: "3000",
      obligationsMinor: "8000",
      netMinor: "-5000",
    });
  });

  it("purchase and issue publish reservations only for a non-replayed commit", async () => {
    const committed = createHarness({ replayed: false });
    await committed.service.purchase(
      committed.actor,
      committed.recipientStudentId,
      committed.commandDto,
      committed.metadata,
    );
    expect(committed.reservations.publishPostCommit).toHaveBeenCalledTimes(1);
    expect(
      committed.integrity.executeVersionedMutation.mock.invocationCallOrder[0],
    ).toBeLessThan(
      committed.reservations.publishPostCommit.mock.invocationCallOrder[0],
    );

    const replayedPurchase = createHarness({ replayed: true });
    await replayedPurchase.service.purchase(
      replayedPurchase.actor,
      replayedPurchase.recipientStudentId,
      replayedPurchase.commandDto,
      replayedPurchase.metadata,
    );
    expect(
      replayedPurchase.reservations.publishPostCommit,
    ).not.toHaveBeenCalled();

    const committedIssue = createHarness({ replayed: false });
    await committedIssue.service.issue(
      committedIssue.actor,
      committedIssue.recipientStudentId,
      committedIssue.issueDto,
      committedIssue.metadata,
    );
    expect(committedIssue.reservations.publishPostCommit).toHaveBeenCalledTimes(
      1,
    );
    expect(
      committedIssue.integrity.executeVersionedMutation.mock
        .invocationCallOrder[0],
    ).toBeLessThan(
      committedIssue.reservations.publishPostCommit.mock.invocationCallOrder[0],
    );

    const replayedIssue = createHarness({ replayed: true });
    await replayedIssue.service.issue(
      replayedIssue.actor,
      replayedIssue.recipientStudentId,
      replayedIssue.issueDto,
      replayedIssue.metadata,
    );
    expect(replayedIssue.reservations.publishPostCommit).not.toHaveBeenCalled();
  });

  it("denies a purchase replay after the actor loses student scope", async () => {
    const harness = createHarness({ replayed: true });
    harness.repository.assertStudentsInScope.mockRejectedValueOnce(
      new NotFoundException("Клиент не найден."),
    );

    await expect(
      harness.service.purchase(
        harness.actor,
        harness.recipientStudentId,
        harness.commandDto,
        harness.metadata,
      ),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(harness.results.load).not.toHaveBeenCalled();
    expect(harness.repository.createIssuedSubscription).not.toHaveBeenCalled();
  });
});
