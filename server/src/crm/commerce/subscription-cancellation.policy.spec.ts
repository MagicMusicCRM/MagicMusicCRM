import {
  ConflictException,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { CancellationContext } from "./subscription-lifecycle.repository";
import {
  SubscriptionCancellationPolicy,
} from "./subscription-cancellation.policy";

const actor: ActorContext = { userId: "actor-1", role: "manager" };

function createContext(
  overrides: Partial<CancellationContext> = {},
): CancellationContext {
  return {
    issuedSubscriptionId: "subscription-1",
    studentId: "student-1",
    payerStudentId: "payer-1",
    fundingMode: "installment",
    package: {
      id: "package-1",
      name: "Package",
      version: 2,
      unitCount: "10",
    },
    status: "active",
    version: 4,
    currencyCode: "RUB",
    finalMinor: "800000",
    usedUnits: "2",
    actualPaidMinor: "500000",
    previousRefundMinor: "10000",
    writeoffMinor: "20000",
    netObligationMinor: "300000",
    balanceMinor: "100000",
    paymentRefs: [
      {
        id: "payment-1",
        amountMinor: "500000",
        occurredAt: "2026-08-01T10:00:00.000Z",
      },
    ],
    previousRefundRefs: [
      {
        id: "refund-1",
        amountMinor: "10000",
        occurredAt: "2026-08-10T10:00:00.000Z",
      },
    ],
    openPaymentRecordRefs: [
      {
        id: "record-1",
        status: "unpaid",
        version: 1,
        amountMinor: "300000",
      },
    ],
    writeoffRefs: [
      {
        id: "writeoff-1",
        lessonId: "lesson-used",
        amountMinor: "20000",
        units: "2",
        occurredAt: "2026-08-15T10:00:00.000Z",
      },
    ],
    obligationRefs: [
      {
        id: "obligation-1",
        direction: "debit",
        amountMinor: "300000",
        occurredAt: "2026-08-01T10:00:00.000Z",
      },
    ],
    futureLessonCount: 1,
    reservedLessonCount: 1,
    reservedUnits: "2",
    futureLessons: [
      {
        lessonId: "lesson-future",
        reservationId: "reservation-1",
        scheduledAt: "2026-09-01T10:00:00.000Z",
        units: "2",
        reserved: true,
      },
    ],
    ...overrides,
  };
}

describe("SubscriptionCancellationPolicy", () => {
  const policy = new SubscriptionCancellationPolicy();

  it("calculates funded cancellation, enforces the refund cap, and keeps warning order", () => {
    const context = createContext();

    expect(policy.calculate(context)).toEqual({
      confirmedFundedMinor: 500000n,
      previousRefundMinor: 10000n,
      unusedUnits: 600n,
      unusedValueMinor: 480000n,
      unfundedCancellationMinor: 190000n,
      recommendedRefundMinor: 290000n,
    });
    expect(policy.assertRefundWithinCap("290000", 290000n)).toBe(290000n);
    expect(() => policy.assertRefundWithinCap("290001", 290000n)).toThrow(
      UnprocessableEntityException,
    );
    expect(policy.warnings(context).map((warning) => warning.code)).toEqual([
      "FUTURE_LESSONS_PRESERVED",
      "RESERVATIONS_RELEASED",
      "ACTUAL_PAYMENTS_PRESERVED",
      "WRITEOFFS_PRESERVED",
    ]);
  });

  it("treats a personal-account cancellation as fully funded", () => {
    const context = createContext({
      fundingMode: "personal_account",
      actualPaidMinor: "0",
    });

    expect(policy.calculate(context)).toMatchObject({
      confirmedFundedMinor: 800000n,
      recommendedRefundMinor: 470000n,
    });
  });

  it.each(["0", "invalid"])(
    "rejects a package with %s cancellation units",
    (unitCount) => {
      const context = createContext({
        package: { ...createContext().package, unitCount },
      });

      expect(() => policy.calculate(context)).toThrow(
        unitCount === "0" ? UnprocessableEntityException : TypeError,
      );
    },
  );

  it("rejects an absent or inactive cancellation context", () => {
    expect(() => policy.assertContext(null)).toThrow(NotFoundException);
    expect(() => policy.assertContext(createContext({ status: "cancelled" }))).toThrow(
      UnprocessableEntityException,
    );
    expect(() => policy.assertContext(createContext({ status: "cancelled" }))).toThrow(
      "Отменить можно только активный абонемент.",
    );
  });

  it("rejects a cancellation preview whose payment facts became stale", () => {
    const context = createContext();
    const current = policy.createTokenPayload(actor, context);

    expect(() =>
      policy.assertPreviewCurrent(
        { ...current, actualPaidMinor: "500001", issuedAtSeconds: 1, expiresAtSeconds: 2 },
        current,
      ),
    ).toThrow(ConflictException);
    expect(() =>
      policy.assertPreviewCurrent(
        { ...current, actualPaidMinor: "500001", issuedAtSeconds: 1, expiresAtSeconds: 2 },
        current,
      ),
    ).toThrow(
      "После предпросмотра изменились платежи, списания, резервы или баланс.",
    );
  });
});
