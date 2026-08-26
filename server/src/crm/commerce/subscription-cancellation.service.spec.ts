import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { CrmPolicy } from "../crm.policy";
import { SubscriptionCancellationPolicy } from "./subscription-cancellation.policy";
import { SubscriptionCancellationService } from "./subscription-cancellation.service";
import { SubscriptionIssueRepository } from "./subscription-issue.repository";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";
import {
  CancellationContext,
  SubscriptionLifecycleRepository,
} from "./subscription-lifecycle.repository";
import { SubscriptionPreviewTokenService } from "./subscription-preview-token.service";
import { SubscriptionReservationService } from "./subscription-reservation.service";

const actor: ActorContext = { userId: "actor-1", role: "manager" };

describe("SubscriptionCancellationService", () => {
  it("maps a cancellation preview from current funding, usage, payments, and lessons", async () => {
    const context: CancellationContext = {
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
      previousRefundRefs: [],
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
      obligationRefs: [],
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
    };
    const service = new SubscriptionCancellationService(
      {
        readCancellationContext: async () => context,
      } as unknown as SubscriptionLifecycleRepository,
      {
        assertStudentsInScope: async () => undefined,
      } as unknown as SubscriptionIssueRepository,
      new CrmPolicy(),
      {} as PlatformIntegrityService,
      {
        issueCancellation: () => ({
          token: "preview-token",
          expiresAt: "2026-08-26T12:00:00.000Z",
        }),
      } as unknown as SubscriptionPreviewTokenService,
      {} as SubscriptionReservationService,
      new SubscriptionLifecycleCommandPolicy(),
      new SubscriptionCancellationPolicy(),
    );

    await expect(
      service.preview(actor, "student-1", "subscription-1"),
    ).resolves.toEqual({
      issuedSubscriptionId: "subscription-1",
      expectedVersion: 4,
      package: {
        id: "package-1",
        name: "Package",
        unitCount: "10",
      },
      usage: {
        usedUnits: "2",
        reservedUnits: "2",
        unusedUnits: "6",
      },
      financial: {
        payerStudentId: "payer-1",
        fundingMode: "installment",
        currencyCode: "RUB",
        finalMinor: "800000",
        actualPaidMinor: "500000",
        confirmedFundedMinor: "500000",
        previousRefundMinor: "10000",
        writeoffMinor: "20000",
        balanceMinor: "100000",
        unusedValueMinor: "480000",
        unfundedCancellationMinor: "190000",
        recommendedRefundMinor: "290000",
        maximumRefundMinor: "290000",
      },
      openPayments: {
        count: 1,
        amountMinor: "300000",
      },
      future: {
        lessonCount: 1,
        reservedLessonCount: 1,
        reservedUnits: "2",
        lessons: [
          {
            lessonId: "lesson-future",
            scheduledAt: "2026-09-01T10:00:00.000Z",
            units: "2",
            reserved: true,
          },
        ],
      },
      warnings: [
        {
          code: "FUTURE_LESSONS_PRESERVED",
          count: 1,
          message:
            "Будущие занятия сохранятся; активные резервы абонемента будут сняты.",
        },
        {
          code: "RESERVATIONS_RELEASED",
          count: 1,
          units: "2",
          message:
            "Резервы будут сняты без удаления или изменения самих занятий.",
        },
        {
          code: "ACTUAL_PAYMENTS_PRESERVED",
          message: "Фактические платежи и выручка останутся неизменными.",
        },
        {
          code: "WRITEOFFS_PRESERVED",
          count: 1,
          message: "Исторические списания останутся неизменными.",
        },
      ],
      previewToken: "preview-token",
      expiresAt: "2026-08-26T12:00:00.000Z",
    });
  });
});
