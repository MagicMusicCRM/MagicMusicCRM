import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import {
  IssueSubscriptionDiscountDto,
  IssueSubscriptionDto,
  IssueSubscriptionInstallmentDto,
  IssueSubscriptionSurchargeDto,
  PurchaseSubscriptionPreviewDto,
} from "../dto/issue-subscription.dto";
import { IssuedCommercialSnapshot } from "./commerce-schema.types";
import {
  PlannedInstallment,
  NormalizedDiscount,
  NormalizedIssue,
  NormalizedPurchase,
  NormalizedSurcharge,
} from "./subscription-issue.contracts";
import { IssuePackageRow } from "./subscription-issue.repository";
import { SubscriptionPurchaseTermsService } from "./subscription-purchase-terms.service";

@Injectable()
export class SubscriptionCommercialTermsService {
  constructor(
    private readonly purchaseTerms: SubscriptionPurchaseTermsService,
  ) {}

  assertPaymentMethod(
    value: string | undefined,
  ): asserts value is "cash" | "cashless" | undefined {
    if (value !== undefined && value !== "cash" && value !== "cashless") {
      throw new UnprocessableEntityException({
        code: "PAYMENT_METHOD_INVALID",
        field: "paymentMethod",
        message: "Способ оплаты должен быть cash или cashless.",
      });
    }
  }

  normalizePurchase(
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
    packageRow: IssuePackageRow,
    legacyLeadAutoPayment = false,
  ): NormalizedPurchase {
    const purchaseReason = dto.purchaseReason?.trim() || null;
    this.purchaseTerms.assertPurchaseReason(
      recipientStudentId,
      dto,
      purchaseReason,
    );
    this.purchaseTerms.assertFundingMode(dto);
    const dates = this.purchaseTerms.normalizeDates(dto);
    const pricing = this.normalizePricing(dto, packageRow);
    const paymentDto =
      legacyLeadAutoPayment && dto.paymentAmountMinor === undefined
        ? { ...dto, paymentAmountMinor: pricing.finalPriceMinor }
        : dto;
    const payment = this.purchaseTerms.normalizePayment(
      paymentDto,
      legacyLeadAutoPayment,
    );
    const normalized = this.normalizeShared(
      dto,
      packageRow,
      payment.amountMinor,
      pricing,
    );
    normalized.snapshot.commercialRules = {
      fundingMode: dto.fundingMode,
      payerStudentId: dto.payerStudentId,
    };
    return { ...normalized, purchaseReason, ...dates, payment };
  }

  bindPurchaseDefaults<T extends PurchaseSubscriptionPreviewDto>(
    dto: T,
    issuedAt: Date,
    legacyLeadAutoPayment = false,
  ): T {
    const timestamp = issuedAt.toISOString();
    return {
      ...dto,
      startsAt: dto.startsAt ?? this.toMoscowBusinessDate(issuedAt),
      paymentOccurredAt:
        dto.paymentOccurredAt ??
        ((dto.paymentAmountMinor !== undefined &&
          dto.paymentAmountMinor !== "0") ||
        (legacyLeadAutoPayment && dto.paymentAmountMinor === undefined)
          ? timestamp
          : undefined),
    };
  }

  private toMoscowBusinessDate(instant: Date): string {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "Europe/Moscow",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(instant);
    const value = (type: Intl.DateTimeFormatPartTypes) =>
      parts.find((part) => part.type === type)?.value ?? "";
    return `${value("year")}-${value("month")}-${value("day")}`;
  }

  normalizeIssue(
    dto: IssueSubscriptionDto,
    packageRow: IssuePackageRow,
  ): NormalizedIssue {
    return this.normalizeShared(dto, packageRow);
  }

  auditReasonForPurchase(normalized: NormalizedPurchase): string {
    return (
      normalized.purchaseReason ??
      normalized.discount.columns.reason ??
      (normalized.surcharge.snapshot.type === "fixed"
        ? normalized.surcharge.snapshot.reason
        : "Покупка абонемента")
    );
  }

  private normalizeShared(
    dto: IssueSubscriptionDto,
    packageRow: IssuePackageRow,
    paidNowMinor?: string,
    pricing?: Pick<
      NormalizedIssue,
      "discount" | "surcharge" | "finalPriceMinor"
    >,
  ): NormalizedIssue {
    const { discount, surcharge, finalPriceMinor } =
      pricing ?? this.normalizePricing(dto, packageRow);
    const installmentTotalMinor =
      paidNowMinor === undefined
        ? finalPriceMinor
        : (BigInt(finalPriceMinor) > BigInt(paidNowMinor)
            ? BigInt(finalPriceMinor) - BigInt(paidNowMinor)
            : 0n
          ).toString();
    const installments = this.normalizeInstallments(
      dto.installments,
      installmentTotalMinor,
    );
    const snapshot = this.createSnapshot(
      packageRow,
      discount,
      surcharge,
      finalPriceMinor,
      installments,
      dto.paymentMethod ?? null,
    );
    return { discount, surcharge, finalPriceMinor, installments, snapshot };
  }

  private normalizePricing(
    dto: IssueSubscriptionDto,
    packageRow: IssuePackageRow,
  ): Pick<NormalizedIssue, "discount" | "surcharge" | "finalPriceMinor"> {
    const discount = this.normalizeDiscount(
      dto.discount,
      packageRow.base_price_minor,
    );
    const surcharge = this.normalizeSurcharge(dto.surcharge);
    return {
      discount,
      surcharge,
      finalPriceMinor: (
        BigInt(discount.finalPriceMinor) + BigInt(surcharge.amountMinor)
      ).toString(),
    };
  }

  private normalizeDiscount(
    dto: IssueSubscriptionDiscountDto | undefined,
    rawBasePriceMinor: string,
  ): NormalizedDiscount {
    if (!dto) return this.normalizeNoDiscount(rawBasePriceMinor);
    const reason = this.discountReason(dto);
    if (dto.type === "percent") {
      return this.normalizePercentDiscount(dto, rawBasePriceMinor, reason);
    }
    return this.normalizeFixedDiscount(dto, rawBasePriceMinor, reason);
  }

  private normalizeNoDiscount(rawBasePriceMinor: string): NormalizedDiscount {
    return {
      snapshot: { type: "none" },
      columns: {
        type: "none",
        percentBasisPoints: null,
        fixedMinor: null,
        reason: null,
      },
      finalPriceMinor: rawBasePriceMinor,
    };
  }

  private discountReason(dto: IssueSubscriptionDiscountDto): string {
    const reason = dto.reason?.trim();
    if (!reason || reason.length > 500) {
      throw new UnprocessableEntityException({
        code: "DISCOUNT_REASON_REQUIRED",
        field: "discount.reason",
        message: "Для скидки обязательно укажите причину.",
      });
    }
    return reason;
  }

  private normalizePercentDiscount(
    dto: IssueSubscriptionDiscountDto,
    rawBasePriceMinor: string,
    reason: string,
  ): NormalizedDiscount {
    if (dto.percent === undefined || dto.fixedMinor !== undefined) {
      this.throwDiscountShape();
    }
    const percent = dto.percent!;
    const basisPoints = Math.round(percent * 100);
    if (!this.isValidPercent(percent, basisPoints)) {
      throw new UnprocessableEntityException({
        code: "DISCOUNT_PERCENT_INVALID",
        field: "discount.percent",
        message: "Процент скидки должен быть от 0,01 до 100.",
      });
    }
    const basePriceMinor = BigInt(rawBasePriceMinor);
    const discountMinor =
      (basePriceMinor * BigInt(basisPoints) + 5_000n) / 10_000n;
    return {
      snapshot: { type: "percent", percentBasisPoints: basisPoints, reason },
      columns: {
        type: "percent",
        percentBasisPoints: basisPoints,
        fixedMinor: null,
        reason,
      },
      finalPriceMinor: (basePriceMinor - discountMinor).toString(),
    };
  }

  private isValidPercent(percent: number, basisPoints: number): boolean {
    return (
      Number.isFinite(percent) &&
      percent > 0 &&
      percent <= 100 &&
      basisPoints >= 1 &&
      basisPoints <= 10_000 &&
      Math.abs(percent * 100 - basisPoints) <= 1e-8
    );
  }

  private normalizeFixedDiscount(
    dto: IssueSubscriptionDiscountDto,
    rawBasePriceMinor: string,
    reason: string,
  ): NormalizedDiscount {
    if (
      dto.type !== "fixed" ||
      dto.fixedMinor === undefined ||
      dto.percent !== undefined ||
      !/^[1-9]\d*$/.test(dto.fixedMinor)
    ) {
      this.throwDiscountShape();
    }
    const basePriceMinor = BigInt(rawBasePriceMinor);
    const fixedMinor = BigInt(dto.fixedMinor!);
    if (fixedMinor > basePriceMinor) {
      throw new UnprocessableEntityException({
        code: "DISCOUNT_EXCEEDS_BASE_PRICE",
        field: "discount.fixedMinor",
        message: "Фиксированная скидка не может превышать базовую стоимость.",
      });
    }
    return {
      snapshot: { type: "fixed", fixedMinor: fixedMinor.toString(), reason },
      columns: {
        type: "fixed",
        percentBasisPoints: null,
        fixedMinor: fixedMinor.toString(),
        reason,
      },
      finalPriceMinor: (basePriceMinor - fixedMinor).toString(),
    };
  }

  private normalizeInstallments(
    dto: IssueSubscriptionInstallmentDto[] | undefined,
    finalPriceMinor: string,
  ): PlannedInstallment[] {
    if (dto === undefined) return [];
    if (dto.length < 2) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENTS_MINIMUM_TWO",
        field: "installments",
        message: "Рассрочка должна содержать минимум две части.",
      });
    }
    let total = 0n;
    const installments = dto.map((item, index) => {
      const normalized = this.normalizeInstallment(item, index);
      total += BigInt(normalized.amountMinor);
      return normalized;
    });
    if (total !== BigInt(finalPriceMinor)) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENT_SUM_MISMATCH",
        field: "installments",
        message:
          "Сумма частей рассрочки должна точно совпадать с итоговой стоимостью.",
        expectedMinor: finalPriceMinor,
        actualMinor: total.toString(),
      });
    }
    return installments;
  }

  private normalizeInstallment(
    item: IssueSubscriptionInstallmentDto,
    index: number,
  ): PlannedInstallment {
    if (!/^[1-9]\d*$/.test(item.amountMinor)) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENT_AMOUNT_INVALID",
        field: `installments.${index}.amountMinor`,
        message: "Сумма части рассрочки должна быть положительной.",
      });
    }
    const dueAt = new Date(item.dueAt);
    if (Number.isNaN(dueAt.getTime())) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENT_DATE_INVALID",
        field: `installments.${index}.dueAt`,
        message: "Укажите корректную дату части рассрочки.",
      });
    }
    return {
      installmentNumber: index + 1,
      dueAt,
      amountMinor: BigInt(item.amountMinor).toString(),
    };
  }

  private normalizeSurcharge(
    dto: IssueSubscriptionSurchargeDto | undefined,
  ): NormalizedSurcharge {
    if (!dto) return { snapshot: { type: "none" }, amountMinor: "0" };
    const reason = dto.reason?.trim();
    if (!reason || reason.length > 500) {
      throw new UnprocessableEntityException({
        code: "SURCHARGE_REASON_REQUIRED",
        field: "surcharge.reason",
        message: "Для доплаты обязательно укажите причину.",
      });
    }
    if (!/^[1-9]\d*$/.test(dto.amountMinor)) {
      throw new UnprocessableEntityException({
        code: "SURCHARGE_AMOUNT_INVALID",
        field: "surcharge.amountMinor",
        message: "Доплата должна быть положительной суммой.",
      });
    }
    const amount = BigInt(dto.amountMinor);
    if (amount > 999_999_999_999n) {
      throw new UnprocessableEntityException({
        code: "SURCHARGE_AMOUNT_OUT_OF_RANGE",
        field: "surcharge.amountMinor",
        message: "Доплата выходит за допустимый диапазон.",
      });
    }
    return {
      snapshot: { type: "fixed", amountMinor: amount.toString(), reason },
      amountMinor: amount.toString(),
    };
  }

  private createSnapshot(
    packageRow: IssuePackageRow,
    discount: NormalizedDiscount,
    surcharge: NormalizedSurcharge,
    finalPriceMinor: string,
    installments: PlannedInstallment[],
    paymentMethod: "cash" | "cashless" | null,
  ): IssuedCommercialSnapshot {
    return {
      snapshotVersion: 1,
      packageVersion: Number(packageRow.version),
      displayName: packageRow.name,
      unitCount: String(packageRow.lessons_total),
      validityDays: packageRow.validity_days,
      basePriceMinor: packageRow.base_price_minor,
      currencyCode: packageRow.currency_code,
      discount: discount.snapshot,
      surcharge: surcharge.snapshot,
      finalPriceMinor,
      installments: installments.map((item) => ({
        installmentNumber: item.installmentNumber,
        dueAt: item.dueAt.toISOString(),
        amountMinor: item.amountMinor,
      })),
      paymentMethod,
      commercialRules: {},
    };
  }

  private throwDiscountShape(): never {
    throw new UnprocessableEntityException({
      code: "DISCOUNT_SHAPE_INVALID",
      field: "discount",
      message: "Укажите либо процентную, либо фиксированную скидку, но не обе.",
    });
  }
}
