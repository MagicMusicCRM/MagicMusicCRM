import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { fingerprintPayload } from "../../platform/platform-integrity.util";
import { IssuedCommercialSnapshot } from "./commerce-schema.types";
import {
  ReplacementContext,
  ReplacementPackageRow,
} from "./subscription-lifecycle.repository";
import { LifecycleWarning } from "./subscription-lifecycle.types";
import { SubscriptionReplacePreviewTokenPayload } from "./subscription-preview-token";

export type ReplacementReadyContext = ReplacementContext & {
  newPackage: NonNullable<ReplacementContext["newPackage"]>;
};

export interface ReplacementCalculation {
  deltaMinor: bigint;
  positionMinor: bigint;
  positionKind: "debt" | "overpayment" | "settled";
}

export interface ReplacementReservationPlan {
  transferReservationIds: string[];
  releaseReservationIds: string[];
  transferredUnits: string;
  releasedUnits: string;
}

@Injectable()
export class SubscriptionReplacementPolicy {
  assertContext(
    context: ReplacementContext | null,
  ): asserts context is ReplacementReadyContext {
    if (!context) {
      throw new NotFoundException("Выданный абонемент не найден.");
    }
    if (context.oldStatus !== "active") {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_NOT_ACTIVE",
        message: "Заменить можно только активный абонемент.",
        status: context.oldStatus,
      });
    }
    if (
      !context.newPackage ||
      !context.newPackage.active ||
      context.newPackage.deletedAt !== null
    ) {
      throw new NotFoundException(
        "Новый пакет не найден или находится в архиве.",
      );
    }
    if (context.oldCurrencyCode !== context.newPackage.currencyCode) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_CURRENCY_MISMATCH",
        message: "Замена между разными валютами не поддерживается.",
        oldCurrencyCode: context.oldCurrencyCode,
        newCurrencyCode: context.newPackage.currencyCode,
      });
    }
    if (
      unitsToHundredths(context.newPackage.unitCount) <
      unitsToHundredths(context.usedUnits)
    ) {
      throw new UnprocessableEntityException({
        code: "REPLACEMENT_VOLUME_BELOW_USED",
        message:
          "Объём нового пакета не может быть меньше уже использованного.",
        usedUnits: context.usedUnits,
        newUnitCount: context.newPackage.unitCount,
      });
    }
  }

  calculate(context: ReplacementReadyContext): ReplacementCalculation {
    const oldFinal = BigInt(context.oldFinalPriceMinor);
    const newFinal = BigInt(context.newPackage.basePriceMinor);
    const paid = BigInt(context.actualPaidMinor);
    const positionMinor = newFinal - paid;
    return {
      deltaMinor: newFinal - oldFinal,
      positionMinor,
      positionKind:
        positionMinor > 0n
          ? "debt"
          : positionMinor < 0n
            ? "overpayment"
            : "settled",
    };
  }

  planReservations(
    context: ReplacementReadyContext,
  ): ReplacementReservationPlan {
    let remaining =
      unitsToHundredths(context.newPackage.unitCount) -
      unitsToHundredths(context.usedUnits);
    let exhausted = false;
    let transferred = 0n;
    let released = 0n;
    const transferReservationIds: string[] = [];
    const releaseReservationIds: string[] = [];
    for (const reservation of context.reservedRows) {
      const units = unitsToHundredths(reservation.units);
      if (!exhausted && units <= remaining) {
        transferReservationIds.push(reservation.reservationId);
        transferred += units;
        remaining -= units;
      } else {
        exhausted = true;
        releaseReservationIds.push(reservation.reservationId);
        released += units;
      }
    }
    return {
      transferReservationIds,
      releaseReservationIds,
      transferredUnits: hundredthsToUnits(transferred),
      releasedUnits: hundredthsToUnits(released),
    };
  }

  createSnapshot(
    oldIssuedSubscriptionId: string,
    context: ReplacementReadyContext,
    packageRow: ReplacementPackageRow,
  ): IssuedCommercialSnapshot {
    return {
      snapshotVersion: 1,
      packageVersion: Number(packageRow.version),
      displayName: packageRow.name,
      unitCount: packageRow.lessons_total,
      validityDays: packageRow.validity_days,
      basePriceMinor: packageRow.base_price_minor,
      currencyCode: packageRow.currency_code,
      discount: { type: "none" },
      finalPriceMinor: packageRow.base_price_minor,
      installments: [],
      paymentMethod: null,
      commercialRules: {
        carriedUsedUnits: context.usedUnits,
        replacedFromSubscriptionId: oldIssuedSubscriptionId,
      },
    };
  }

  createTokenPayload(
    actor: ActorContext,
    context: ReplacementReadyContext,
  ): Omit<
    SubscriptionReplacePreviewTokenPayload,
    "issuedAtSeconds" | "expiresAtSeconds"
  > {
    const calculation = this.calculate(context);
    const reservationPlan = this.planReservations(context);
    return {
      kind: "subscription.replace",
      actorUserId: actor.userId,
      studentId: context.studentId,
      payerStudentId: context.payerStudentId,
      issuedSubscriptionId: context.issuedSubscriptionId,
      expectedVersion: context.oldVersion,
      newPackageId: context.newPackage.id,
      newPackageVersion: context.newPackage.version,
      currencyCode: context.oldCurrencyCode,
      usedUnits: context.usedUnits,
      reservedLessonCount: context.reservedLessonCount,
      reservedUnits: context.reservedUnits,
      transferableReservationCount:
        reservationPlan.transferReservationIds.length,
      transferableReservationUnits: reservationPlan.transferredUnits,
      releasedReservationCount: reservationPlan.releaseReservationIds.length,
      releasedReservationUnits: reservationPlan.releasedUnits,
      reservationPlanFingerprint: fingerprintPayload({
        transfer: reservationPlan.transferReservationIds,
        release: reservationPlan.releaseReservationIds,
      }),
      futureLessonCount: context.futureLessonCount,
      futureUnits: context.futureUnits,
      oldFinalMinor: context.oldFinalPriceMinor,
      newFinalMinor: context.newPackage.basePriceMinor,
      actualPaidMinor: context.actualPaidMinor,
      deltaMinor: calculation.deltaMinor.toString(),
      positionKind: calculation.positionKind,
      positionMinor: absolute(calculation.positionMinor).toString(),
    };
  }

  assertPreviewCurrent(
    signed: SubscriptionReplacePreviewTokenPayload,
    current: Omit<
      SubscriptionReplacePreviewTokenPayload,
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
        code: "REPLACEMENT_PREVIEW_STALE",
        message:
          "После предпросмотра изменились платежи, использование, резервы или пакет.",
      });
    }
  }

  warnings(context: ReplacementReadyContext): LifecycleWarning[] {
    const warnings: LifecycleWarning[] = [];
    if (unitsToHundredths(context.usedUnits) > 0n) {
      warnings.push({
        code: "USED_UNITS_TRANSFERRED",
        units: context.usedUnits,
        message: "Использованные единицы будут перенесены в новый абонемент.",
      });
    }
    if (context.futureLessonCount > 0) {
      warnings.push({
        code: "FUTURE_LESSONS_PRESERVED",
        count: context.futureLessonCount,
        units: context.futureUnits,
        message:
          "Будущие занятия сохранятся; существующие резервы будут перенесены.",
      });
    }
    const reservationPlan = this.planReservations(context);
    if (reservationPlan.releaseReservationIds.length > 0) {
      warnings.push({
        code: "RESERVATIONS_RELEASED_FOR_CAPACITY",
        count: reservationPlan.releaseReservationIds.length,
        units: reservationPlan.releasedUnits,
        message:
          "Не помещающиеся в новый объём резервы будут сняты; занятия сохранятся.",
      });
    }
    if (BigInt(context.actualPaidMinor) > 0n) {
      warnings.push({
        code: "ACTUAL_PAYMENTS_PRESERVED",
        message: "Фактические платежи останутся неизменными.",
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

function hundredthsToUnits(value: bigint): string {
  const whole = value / 100n;
  const fraction = (value % 100n).toString().padStart(2, "0");
  return fraction === "00"
    ? whole.toString()
    : `${whole}.${fraction.replace(/0$/, "")}`;
}

function absolute(value: bigint): bigint {
  return value < 0n ? -value : value;
}
