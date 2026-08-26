import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import {
  IssueSubscriptionDto,
  PurchaseSubscriptionCommandDto,
  PurchaseSubscriptionPreviewDto,
} from "../dto/issue-subscription.dto";
import { SubscriptionCommercialTermsService } from "./subscription-commercial-terms.service";
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
  payerBalanceMinor?: string;
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
  const previewDto: PurchaseSubscriptionPreviewDto = {
    packageId: PACKAGE_ID,
    payerStudentId: PAYER_ID,
    fundingMode: "personal_account",
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
    lockPurchaseStudents: jest.fn().mockImplementation(
      async (_client: unknown, _actor: ActorContext, ids: readonly string[]) =>
        students.filter((student) => ids.includes(student.id)),
    ),
    assertStudentsInScope: jest.fn().mockResolvedValue(undefined),
    findActivePackageForShare: jest.fn().mockResolvedValue(packageRow),
    readAccountBalance: jest.fn().mockResolvedValue(payerBalanceMinor),
    createIssuedSubscription: jest.fn().mockResolvedValue({
      id: SUBSCRIPTION_ID,
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
  };
  const policy = { assertCanWriteCrm: jest.fn() };
  const previewTokens = {
    issuePurchase: jest.fn().mockReturnValue({
      token: "signed-preview-token",
      expiresAt: "2026-08-26T12:10:00.000Z",
    }),
    verifyPurchase: jest.fn(),
  };
  const reservations = { publishPostCommit: jest.fn().mockResolvedValue(undefined) };
  const terms = new SubscriptionCommercialTermsService();
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
    issuedAtSeconds: 1_777_377_600,
    expiresAtSeconds: 1_777_378_200,
  });
  const results = new SubscriptionIssueResultService(
    repository as unknown as SubscriptionIssueRepository,
  ) as SubscriptionIssueResultService & { load: jest.Mock };
  jest.spyOn(results, "load");
  const integrity = {
    executeVersionedMutation: jest.fn().mockImplementation(async (command) => {
      const resultRef = await command.mutate({} as never, 1);
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
    previewDto,
    recipientStudentId,
    repository,
    reservations,
    results,
    service,
  };
}

describe("SubscriptionIssueService", () => {
  it("previewPurchase reports the exact insufficient-balance blocker without invoking integrity", async () => {
    const harness = createHarness({ payerBalanceMinor: "5000" });
    const response = await harness.service.previewPurchase(
      harness.actor,
      harness.recipientStudentId,
      harness.previewDto,
    );

    expect(response).toMatchObject({
      finalPriceMinor: "8000",
      payerBalanceMinor: "5000",
      balanceAfterMinor: "-3000",
      canCommit: false,
      shortageMinor: "3000",
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

    expect(harness.repository.createIssuedSubscription.mock.invocationCallOrder[0]).toBeLessThan(
      harness.repository.createInstallments.mock.invocationCallOrder[0],
    );
    expect(harness.repository.createInstallments.mock.invocationCallOrder[0]).toBeLessThan(
      harness.repository.createObligations.mock.invocationCallOrder[0],
    );
    expect(harness.repository.createObligations.mock.invocationCallOrder[0]).toBeLessThan(
      harness.repository.createIssueLifecycle.mock.invocationCallOrder[0],
    );
    expect(harness.integrity.executeVersionedMutation.mock.invocationCallOrder[0]).toBeLessThan(
      harness.results.load.mock.invocationCallOrder[0],
    );
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
    expect(committed.integrity.executeVersionedMutation.mock.invocationCallOrder[0]).toBeLessThan(
      committed.reservations.publishPostCommit.mock.invocationCallOrder[0],
    );

    const replayedPurchase = createHarness({ replayed: true });
    await replayedPurchase.service.purchase(
      replayedPurchase.actor,
      replayedPurchase.recipientStudentId,
      replayedPurchase.commandDto,
      replayedPurchase.metadata,
    );
    expect(replayedPurchase.reservations.publishPostCommit).not.toHaveBeenCalled();

    const committedIssue = createHarness({ replayed: false });
    await committedIssue.service.issue(
      committedIssue.actor,
      committedIssue.recipientStudentId,
      committedIssue.issueDto,
      committedIssue.metadata,
    );
    expect(committedIssue.reservations.publishPostCommit).toHaveBeenCalledTimes(1);
    expect(committedIssue.integrity.executeVersionedMutation.mock.invocationCallOrder[0]).toBeLessThan(
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
});
