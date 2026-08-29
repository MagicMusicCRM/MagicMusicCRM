import { PaymentCorrectionService } from "./payment-correction.service";
import { ActorContext } from "../../common/security/actor-context";

const actor = {
  userId: "11111111-1111-4111-8111-111111111111",
  role: "director",
} as ActorContext;
const studentId = "22222222-2222-4222-8222-222222222222";
const recipientStudentId = "33333333-3333-4333-8333-333333333333";
const recordId = "44444444-4444-4444-8444-444444444444";
const subscriptionId = "55555555-5555-4555-8555-555555555555";
const actualPaymentId = "66666666-6666-4666-8666-666666666666";

function target() {
  return {
    payment_record_id: recordId,
    payer_student_id: studentId,
    recipient_student_id: recipientStudentId,
    issued_subscription_id: subscriptionId,
    installment_id: null,
    amount_minor: "100000",
    currency_code: "RUB",
    status: "paid",
    record_version: 2,
    record_due_at: "2026-08-10T09:00:00.000Z",
    record_method: "cashless",
    record_external_identifier: "old-check",
    record_verification_note: "Старая запись",
    actual_payment_id: actualPaymentId,
    payment_student_id: studentId,
    payment_amount_minor: "100000",
    payment_currency_code: "RUB",
    payment_method: "cashless",
    payment_date: "2026-08-10T09:00:00.000Z",
    payment_branch_id: "77777777-7777-4777-8777-777777777777",
    payment_invoice_number: "old-check",
    linked_adjustment_count: 0,
    exclusion_id: null,
  } as const;
}

function createHarness() {
  const reversalRepository = {
    findTarget: jest.fn().mockResolvedValue(target()),
    lockTarget: jest.fn().mockResolvedValue(target()),
    createExclusion: jest.fn().mockResolvedValue("exclusion-a"),
    createCorrection: jest.fn().mockResolvedValue({}),
    findCorrection: jest.fn().mockResolvedValue({
      correction_id: "88888888-8888-4888-8888-888888888888",
      source_payment_record_id: recordId,
      replacement_payment_record_id: "99999999-9999-4999-8999-999999999999",
      reversal_adjustment_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      reason: "Исправление суммы",
      actor_user_id: actor.userId,
      audit_event_id: null,
      occurred_at: "2026-08-15T12:00:00.000Z",
    }),
  };
  const replacement = {
    id: "99999999-9999-4999-8999-999999999999",
    student_id: studentId,
    issued_subscription_id: subscriptionId,
    installment_id: null,
    amount_minor: "150000",
    currency_code: "RUB",
    status: "paid",
    due_at: "2026-08-15T09:00:00.000Z",
    method: "cash",
    external_identifier: "new-check",
    verification_note: "Новая запись",
    actual_payment_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    version: 1,
    created_by: actor.userId,
    verified_by: actor.userId,
    verified_at: "2026-08-15T09:00:00.000Z",
    created_at: "2026-08-15T09:00:00.000Z",
    updated_at: "2026-08-15T09:00:00.000Z",
  };
  const paymentRepository = {
    lockSubscriptionTarget: jest.fn().mockResolvedValue({
      issued_subscription_id: subscriptionId,
      installment_id: null,
      amount_minor: null,
      currency_code: "RUB",
      due_at: null,
      recipient_student_id: recipientStudentId,
      existing_payment_record_id: null,
    }),
    lockInstallmentTarget: jest.fn(),
    createRecord: jest.fn().mockResolvedValue(replacement),
    linkActualPayment: jest.fn().mockResolvedValue(undefined),
    appendStatusEvent: jest.fn().mockResolvedValue({}),
    initializeRecordAggregate: jest.fn().mockResolvedValue(undefined),
    findRecord: jest.fn().mockResolvedValue(replacement),
  };
  const issueRepository = {
    lockPurchaseStudents: jest
      .fn()
      .mockResolvedValue([{ id: studentId }, { id: recipientStudentId }]),
    readAccountBalance: jest.fn().mockResolvedValue("500000"),
    createPaymentAdjustment: jest.fn().mockResolvedValue({ id: "reverse-a" }),
    createActualPayment: jest.fn().mockResolvedValue({ id: "actual-a" }),
  };
  const projections = {
    resolveStudentScope: jest.fn().mockResolvedValue({
      studentId,
      branchId: "77777777-7777-4777-8777-777777777777",
    }),
    loadProjection: jest
      .fn()
      .mockResolvedValue([
        { accounts: [{ currencyCode: "RUB", balanceMinor: "500000" }] },
      ]),
  };
  const policy = { assertCanWriteCrm: jest.fn() };
  const signed = {
    kind: "payment.correction",
    actorUserId: actor.userId,
    studentId,
    recipientStudentId,
    paymentRecordId: recordId,
    expectedVersion: 2,
    oldStatus: "paid",
    oldActualPaymentId: actualPaymentId,
    issuedSubscriptionId: subscriptionId,
    installmentId: null,
    oldAmountMinor: "100000",
    currencyCode: "RUB",
    amountMinor: "150000",
    status: "paid",
    dueAt: "2026-08-15T09:00:00.000Z",
    method: "cash",
    externalIdentifier: "new-check",
    occurredAt: "2026-08-15T09:00:00.000Z",
    branchId: "77777777-7777-4777-8777-777777777777",
    verificationNote: "Новая запись",
    walletBalanceMinor: "500000",
    resultingBalanceMinor: "500000",
    issuedAtSeconds: 1,
    expiresAtSeconds: 2,
  } as const;
  const previewTokens = {
    issuePaymentCorrection: jest.fn().mockReturnValue({
      token: "signed-preview",
      expiresAt: "2026-08-15T12:05:00.000Z",
    }),
    verifyPaymentCorrection: jest.fn().mockReturnValue(signed),
  };
  const integrity = {
    executeVersionedMutation: jest.fn().mockImplementation(async (options) => {
      const resultRef = await options.mutate({ query: jest.fn() });
      return {
        resultRef,
        replayed: false,
        auditId: "audit-a",
        eventId: "event-a",
      };
    }),
  };
  const reservations = { publishPostCommit: jest.fn() };
  const service = new PaymentCorrectionService(
    reversalRepository as never,
    paymentRepository as never,
    issueRepository as never,
    projections as never,
    policy as never,
    integrity as never,
    previewTokens as never,
    reservations as never,
  );
  return {
    service,
    reversalRepository,
    paymentRepository,
    issueRepository,
    projections,
    integrity,
    reservations,
  };
}

describe("PaymentCorrectionService", () => {
  it("keeps a subscription-linked correction out of the wallet", async () => {
    const { service } = createHarness();
    const preview = await service.preview(actor, studentId, recordId, {
      expectedVersion: 2,
      amountMinor: "150000",
      status: "paid",
      method: "cash",
      externalIdentifier: "new-check",
      occurredAt: "2026-08-15T09:00:00.000Z",
      branchId: "77777777-7777-4777-8777-777777777777",
      verificationNote: "Новая запись",
    });

    expect(preview.walletDeltaMinor).toBe("0");
    expect(preview.resultingBalanceMinor).toBe("500000");
    expect(preview.before.amountMinor).toBe("100000");
    expect(preview.after.amountMinor).toBe("150000");
    expect(preview.previewToken).toBe("signed-preview");
  });

  it("reverses, replaces and links the correction inside one mutation", async () => {
    const {
      service,
      reversalRepository,
      paymentRepository,
      issueRepository,
      integrity,
      reservations,
    } = createHarness();

    const response = await service.correct(
      actor,
      studentId,
      recordId,
      {
        previewToken: "signed-preview",
        confirm: true,
        reason: "Исправление суммы",
      },
      {
        idempotencyKey: "payment-correction-test",
        requestId: "request-payment-correction",
      },
    );

    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.payment-correction.commit",
        aggregateType: "commerce:payment-correction",
        expectedVersion: 0,
      }),
    );
    expect(issueRepository.createPaymentAdjustment).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ amountMinor: "-100000" }),
    );
    expect(reversalRepository.createExclusion).toHaveBeenCalledTimes(1);
    expect(paymentRepository.createRecord).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ amountMinor: "150000", status: "paid" }),
    );
    expect(reversalRepository.createCorrection).toHaveBeenCalledTimes(1);
    expect(reservations.publishPostCommit).toHaveBeenCalledTimes(1);
    expect(response.replacement.amountMinor).toBe("150000");
  });
});
