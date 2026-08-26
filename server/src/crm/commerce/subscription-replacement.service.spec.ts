import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";
import { SubscriptionLifecycleRepository } from "./subscription-lifecycle.repository";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionReplacementPolicy } from "./subscription-replacement.policy";
import { SubscriptionReplacementService } from "./subscription-replacement.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const actor: ActorContext = { userId: "actor-1", role: "manager" };

describe("SubscriptionReplacementService", () => {
  it("maps a replacement preview from current package, usage, and reservation facts", async () => {
    const context = {
      issuedSubscriptionId: "subscription-old",
      studentId: "student-1",
      payerStudentId: "payer-1",
      fundingMode: "installment" as const,
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
    };
    const service = new SubscriptionReplacementService(
      {
        readReplacementContext: async () => context,
      } as unknown as SubscriptionLifecycleRepository,
      {
        assertStudentsInScope: async () => undefined,
      } as unknown as SubscriptionIssueRepository,
      new CrmPolicy(),
      {} as PlatformIntegrityService,
      {
        issue: () => ({
          token: "preview-token",
          expiresAt: "2026-08-26T12:00:00.000Z",
        }),
      } as unknown as SubscriptionPreviewTokenService,
      {} as SubscriptionReservationService,
      new SubscriptionLifecycleCommandPolicy(),
      new SubscriptionReplacementPolicy(),
    );

    await expect(
      service.preview(actor, "student-1", "subscription-old", {
        newPackageId: "package-new",
      }),
    ).resolves.toEqual({
      issuedSubscriptionId: "subscription-old",
      expectedVersion: 3,
      oldPackageId: "package-old",
      newPackage: {
        id: "package-new",
        version: 2,
        name: "New package",
        unitCount: "7",
      },
      usage: {
        usedUnits: "2",
        reservedLessonCount: 3,
        reservedUnits: "6",
        transferableReservationCount: 2,
        transferableReservationUnits: "5",
        releasedReservationCount: 1,
        releasedReservationUnits: "1",
        futureLessonCount: 1,
        futureUnits: "1",
      },
      financial: {
        currencyCode: "RUB",
        oldFinalMinor: "800000",
        newFinalMinor: "1000000",
        actualPaidMinor: "600000",
        obligationDeltaMinor: "200000",
        resultingPosition: {
          kind: "debt",
          amountMinor: "400000",
        },
      },
      warnings: [
        {
          code: "USED_UNITS_TRANSFERRED",
          message: "Использованные единицы будут перенесены в новый абонемент.",
          units: "2",
        },
        {
          code: "FUTURE_LESSONS_PRESERVED",
          message:
            "Будущие занятия сохранятся; существующие резервы будут перенесены.",
          count: 1,
          units: "1",
        },
        {
          code: "RESERVATIONS_RELEASED_FOR_CAPACITY",
          message:
            "Не помещающиеся в новый объём резервы будут сняты; занятия сохранятся.",
          count: 1,
          units: "1",
        },
        {
          code: "ACTUAL_PAYMENTS_PRESERVED",
          message: "Фактические платежи останутся неизменными.",
        },
      ],
      previewToken: "preview-token",
      expiresAt: "2026-08-26T12:00:00.000Z",
    });
  });
});
