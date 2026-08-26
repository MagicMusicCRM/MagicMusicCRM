import { ConflictException, NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { ReplacementPackageRow } from "./subscription-lifecycle.repository";
import { ReplacementReadyContext, SubscriptionReplacementPolicy } from "./subscription-replacement.policy";

const actor: ActorContext = { userId: "actor-1", role: "manager" };

function createContext(
  overrides: Partial<ReplacementReadyContext> = {},
): ReplacementReadyContext {
  return {
    issuedSubscriptionId: "subscription-old",
    studentId: "student-1",
    payerStudentId: "payer-1",
    fundingMode: "installment",
    purchaseReason: "upgrade",
    oldPackageId: "package-old",
    oldStatus: "active",
    oldVersion: 3,
    oldFinalPriceMinor: "800000",
    oldCurrencyCode: "RUB",
    legacyLessonsUsed: "2",
    newPackage: {
      id: "package-new",
      name: "New package",
      unitCount: "7",
      basePriceMinor: "1000000",
      currencyCode: "RUB",
      validityDays: 30,
      active: true,
      version: 2,
      deletedAt: null,
    },
    usedUnits: "2",
    actualPaidMinor: "600000",
    reservedLessonCount: 3,
    reservedUnits: "6",
    reservedRows: [
      {
        reservationId: "reservation-1",
        lessonId: "lesson-1",
        scheduledAt: "2026-09-01T10:00:00.000Z",
        units: "3",
      },
      {
        reservationId: "reservation-2",
        lessonId: "lesson-2",
        scheduledAt: "2026-09-02T10:00:00.000Z",
        units: "2",
      },
      {
        reservationId: "reservation-3",
        lessonId: "lesson-3",
        scheduledAt: "2026-09-03T10:00:00.000Z",
        units: "1",
      },
    ],
    futureLessonCount: 1,
    futureUnits: "1",
    ...overrides,
  };
}

function createPackageRow(): ReplacementPackageRow {
  return {
    id: "package-new",
    name: "New package",
    lessons_total: "7",
    base_price_minor: "1000000",
    currency_code: "RUB",
    validity_days: 30,
    is_active: true,
    version: 2,
    deleted_at: null,
  };
}

describe("SubscriptionReplacementPolicy", () => {
  const policy = new SubscriptionReplacementPolicy();

  it("calculates, plans reservations, and keeps warning order for a replacement", () => {
    const context = createContext();

    expect(policy.calculate(context)).toEqual({
      deltaMinor: 200000n,
      positionMinor: 400000n,
      positionKind: "debt",
    });
    expect(policy.planReservations(context)).toEqual({
      transferReservationIds: ["reservation-1", "reservation-2"],
      releaseReservationIds: ["reservation-3"],
      transferredUnits: "5",
      releasedUnits: "1",
    });
    expect(
      policy.warnings(context).map((warning: { code: string }) => warning.code),
    ).toEqual([
      "USED_UNITS_TRANSFERRED",
      "FUTURE_LESSONS_PRESERVED",
      "RESERVATIONS_RELEASED_FOR_CAPACITY",
      "ACTUAL_PAYMENTS_PRESERVED",
    ]);
  });

  it.each([
    ["inactive", { active: false, deletedAt: null }],
    ["archived", { active: true, deletedAt: "2026-08-01T00:00:00.000Z" }],
  ])("rejects a %s replacement package", (_state, packageOverrides) => {
    const context = createContext({
      newPackage: { ...createContext().newPackage, ...packageOverrides },
    });

    expect(() => policy.assertContext(context)).toThrow(NotFoundException);
    expect(() => policy.assertContext(context)).toThrow(
      "Новый пакет не найден или находится в архиве.",
    );
  });

  it("rejects a replacement between currencies", () => {
    const context = createContext({
      newPackage: { ...createContext().newPackage, currencyCode: "USD" },
    });

    expect(() => policy.assertContext(context)).toThrow(
      UnprocessableEntityException,
    );
    expect(() => policy.assertContext(context)).toThrow(
      "Замена между разными валютами не поддерживается.",
    );
  });

  it("rejects a replacement volume below used units", () => {
    const context = createContext({
      newPackage: { ...createContext().newPackage, unitCount: "1.99" },
    });

    expect(() => policy.assertContext(context)).toThrow(
      "Объём нового пакета не может быть меньше уже использованного.",
    );
  });

  it("rejects stale preview token facts", () => {
    const context = createContext();
    const current = policy.createTokenPayload(actor, context);

    expect(() =>
      policy.assertPreviewCurrent(
        { ...current, actualPaidMinor: "600001", issuedAtSeconds: 1, expiresAtSeconds: 2 },
        current,
      ),
    ).toThrow(ConflictException);
    expect(() =>
      policy.assertPreviewCurrent(
        { ...current, actualPaidMinor: "600001", issuedAtSeconds: 1, expiresAtSeconds: 2 },
        current,
      ),
    ).toThrow(
      "После предпросмотра изменились платежи, использование, резервы или пакет.",
    );
  });

  it("creates a replacement commercial snapshot from the locked package", () => {
    expect(
      policy.createSnapshot("subscription-old", createContext(), createPackageRow()),
    ).toEqual({
      snapshotVersion: 1,
      packageVersion: 2,
      displayName: "New package",
      unitCount: "7",
      validityDays: 30,
      basePriceMinor: "1000000",
      currencyCode: "RUB",
      discount: { type: "none" },
      finalPriceMinor: "1000000",
      installments: [],
      paymentMethod: null,
      commercialRules: {
        carriedUsedUnits: "2",
        replacedFromSubscriptionId: "subscription-old",
      },
    });
  });
});
