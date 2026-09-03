import { normalizeCommercialPrice } from "./commercial-price";
import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import {
  IssueSubscriptionDto,
  IssueSubscriptionInstallmentDto,
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
    return normalizeCommercialPrice(packageRow.base_price_minor, dto);
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


}
