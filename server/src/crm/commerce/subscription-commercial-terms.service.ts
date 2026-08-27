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

@Injectable()
export class SubscriptionCommercialTermsService {
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
  ): NormalizedPurchase {
    const purchaseReason = dto.purchaseReason?.trim() || null;
    this.assertPurchaseReason(recipientStudentId, dto, purchaseReason);
    this.assertFundingMode(dto);
    const normalized = this.normalizeShared(dto, packageRow);
    normalized.snapshot.commercialRules = {
      fundingMode: dto.fundingMode,
      payerStudentId: dto.payerStudentId,
    };
    return { ...normalized, purchaseReason };
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

  private assertPurchaseReason(
    recipientStudentId: string,
    dto: PurchaseSubscriptionPreviewDto,
    purchaseReason: string | null,
  ): void {
    if (purchaseReason && purchaseReason.length > 500) {
      throw new UnprocessableEntityException({
        code: "PURCHASE_REASON_TOO_LONG",
        field: "purchaseReason",
        message: "Причина покупки не должна превышать 500 символов.",
      });
    }
    if (dto.payerStudentId !== recipientStudentId && purchaseReason === null) {
      throw new UnprocessableEntityException({
        code: "PURCHASE_REASON_REQUIRED",
        field: "purchaseReason",
        message:
          "При оплате со счёта другого клиента обязательно укажите причину.",
      });
    }
  }

  private assertFundingMode(dto: PurchaseSubscriptionPreviewDto): void {
    if (dto.fundingMode !== "personal_account" && dto.fundingMode !== "installment") {
      throw new UnprocessableEntityException({
        code: "FUNDING_MODE_INVALID",
        field: "fundingMode",
        message: "Выберите личный счёт или рассрочку.",
      });
    }
    if (dto.fundingMode === "personal_account" && dto.installments !== undefined) {
      throw new UnprocessableEntityException({
        code: "PERSONAL_ACCOUNT_INSTALLMENTS_FORBIDDEN",
        field: "installments",
        message: "При покупке с личного счёта рассрочка не применяется.",
      });
    }
    if (dto.fundingMode === "installment" && dto.installments === undefined) {
      throw new UnprocessableEntityException({
        code: "INSTALLMENTS_REQUIRED",
        field: "installments",
        message: "Для рассрочки укажите график платежей.",
      });
    }
  }

  private normalizeShared(
    dto: IssueSubscriptionDto,
    packageRow: IssuePackageRow,
  ): NormalizedIssue {
    const discount = this.normalizeDiscount(dto.discount, packageRow.base_price_minor);
    const surcharge = this.normalizeSurcharge(dto.surcharge);
    const finalPriceMinor = (
      BigInt(discount.finalPriceMinor) + BigInt(surcharge.amountMinor)
    ).toString();
    const installments = this.normalizeInstallments(dto.installments, finalPriceMinor);
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
