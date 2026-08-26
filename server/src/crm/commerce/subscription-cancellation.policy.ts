import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { CancellationContext } from "./subscription-lifecycle.repository";
import { LifecycleWarning } from "./subscription-lifecycle.types";
import { SubscriptionCancelPreviewTokenPayload } from "./subscription-preview-token";

export interface CancellationCalculation {
  confirmedFundedMinor: bigint;
  previousRefundMinor: bigint;
  unusedUnits: bigint;
  unusedValueMinor: bigint;
  unfundedCancellationMinor: bigint;
  recommendedRefundMinor: bigint;
}

@Injectable()
export class SubscriptionCancellationPolicy {
  assertContext(
    context: CancellationContext | null,
  ): asserts context is CancellationContext {
    if (!context) {
      throw new NotFoundException("Выданный абонемент не найден.");
    }
    if (context.status !== "active") {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_NOT_ACTIVE",
        message: "Отменить можно только активный абонемент.",
        status: context.status,
      });
    }
  }

  calculate(context: CancellationContext): CancellationCalculation {
    const totalUnits = unitsToHundredths(context.package.unitCount);
    if (totalUnits <= 0n) {
      throw new UnprocessableEntityException({
        code: "CANCELLATION_UNITS_INVALID",
        message: "У абонемента нет корректного объёма для расчёта возврата.",
      });
    }
    const protectedUnits = minBigInt(
      totalUnits,
      unitsToHundredths(context.usedUnits) +
        unitsToHundredths(context.reservedUnits),
    );
    const unusedUnits = totalUnits - protectedUnits;
    const finalMinor = BigInt(context.finalMinor);
    const actualPaidMinor = BigInt(context.actualPaidMinor);
    const confirmedFundedMinor =
      context.fundingMode === "personal_account"
        ? finalMinor
        : minBigInt(finalMinor, maxBigInt(0n, actualPaidMinor));
    const previousRefundMinor = BigInt(context.previousRefundMinor);
    const unusedValueMinor = (finalMinor * unusedUnits) / totalUnits;
    const grossRefundMinor =
      (confirmedFundedMinor * unusedUnits) / totalUnits;
    const recommendedRefundMinor = minBigInt(
      unusedValueMinor,
      maxBigInt(0n, grossRefundMinor - previousRefundMinor),
    );
    return {
      confirmedFundedMinor,
      previousRefundMinor,
      unusedUnits,
      unusedValueMinor,
      unfundedCancellationMinor:
        unusedValueMinor - recommendedRefundMinor,
      recommendedRefundMinor,
    };
  }

  assertRefundWithinCap(
    refundMinor: string,
    recommendedRefundMinor: bigint,
  ): bigint {
    const chosenRefundMinor = BigInt(refundMinor);
    if (chosenRefundMinor > recommendedRefundMinor) {
      throw new UnprocessableEntityException({
        code: "CANCELLATION_REFUND_EXCEEDS_CAP",
        message: "Возврат превышает подтверждённый доступный максимум.",
        maximumRefundMinor: recommendedRefundMinor.toString(),
      });
    }
    return chosenRefundMinor;
  }

  createTokenPayload(
    actor: ActorContext,
    context: CancellationContext,
  ): Omit<
    SubscriptionCancelPreviewTokenPayload,
    "issuedAtSeconds" | "expiresAtSeconds"
  > {
    return {
      kind: "subscription.cancel",
      actorUserId: actor.userId,
      studentId: context.studentId,
      payerStudentId: context.payerStudentId,
      issuedSubscriptionId: context.issuedSubscriptionId,
      expectedVersion: context.version,
      packageId: context.package.id,
      packageVersion: context.package.version,
      unitCount: context.package.unitCount,
      usedUnits: context.usedUnits,
      currencyCode: context.currencyCode,
      finalMinor: context.finalMinor,
      actualPaidMinor: context.actualPaidMinor,
      fundingMode: context.fundingMode,
      previousRefundMinor: context.previousRefundMinor,
      writeoffMinor: context.writeoffMinor,
      balanceMinor: context.balanceMinor,
      openPaymentRecordCount: context.openPaymentRecordRefs.length,
      openPaymentRecordMinor: sumMinor(
        context.openPaymentRecordRefs.map((record) => record.amountMinor),
      ).toString(),
      futureLessonCount: context.futureLessonCount,
      reservedLessonCount: context.reservedLessonCount,
      reservedUnits: context.reservedUnits,
      impactFingerprint: fingerprintPayload({
        payments: context.paymentRefs,
        refunds: context.previousRefundRefs,
        openPaymentRecords: context.openPaymentRecordRefs,
        writeoffs: context.writeoffRefs,
        obligations: context.obligationRefs,
        future: context.futureLessons,
      }),
    };
  }

  assertPreviewCurrent(
    signed: SubscriptionCancelPreviewTokenPayload,
    current: Omit<
      SubscriptionCancelPreviewTokenPayload,
      "issuedAtSeconds" | "expiresAtSeconds"
    >,
  ): void {
    const {
      issuedAtSeconds: _issuedAtSeconds,
      expiresAtSeconds: _expiresAtSeconds,
      ...signedFacts
    } = signed;
    if (fingerprintPayload(signedFacts) !== fingerprintPayload(current)) {
      throw new ConflictException({
        code: "CANCELLATION_PREVIEW_STALE",
        message:
          "После предпросмотра изменились платежи, списания, резервы или баланс.",
      });
    }
  }

  warnings(context: CancellationContext): LifecycleWarning[] {
    const warnings: LifecycleWarning[] = [];
    if (context.futureLessonCount > 0) {
      warnings.push({
        code: "FUTURE_LESSONS_PRESERVED",
        count: context.futureLessonCount,
        message:
          "Будущие занятия сохранятся; активные резервы абонемента будут сняты.",
      });
    }
    if (context.reservedLessonCount > 0) {
      warnings.push({
        code: "RESERVATIONS_RELEASED",
        count: context.reservedLessonCount,
        units: context.reservedUnits,
        message:
          "Резервы будут сняты без удаления или изменения самих занятий.",
      });
    }
    if (BigInt(context.actualPaidMinor) > 0n) {
      warnings.push({
        code: "ACTUAL_PAYMENTS_PRESERVED",
        message: "Фактические платежи и выручка останутся неизменными.",
      });
    }
    if (
      context.writeoffRefs.length > 0 ||
      BigInt(context.writeoffMinor) > 0n
    ) {
      warnings.push({
        code: "WRITEOFFS_PRESERVED",
        count: context.writeoffRefs.length,
        message: "Исторические списания останутся неизменными.",
      });
    }
    return warnings;
  }
}

function unitsToHundredths(value: string): bigint {
  if (!/^(0|[1-9]\d*)(\.\d{1,2})?$/.test(value)) {
    throw new TypeError(`Invalid unit value: ${value}`);
  }
  const [whole, fraction = ""] = value.split(".");
  return BigInt(whole!) * 100n + BigInt(fraction.padEnd(2, "0"));
}

function sumMinor(values: string[]): bigint {
  return values.reduce((sum, value) => sum + BigInt(value), 0n);
}

function minBigInt(left: bigint, right: bigint): bigint {
  return left < right ? left : right;
}

function maxBigInt(left: bigint, right: bigint): bigint {
  return left > right ? left : right;
}
