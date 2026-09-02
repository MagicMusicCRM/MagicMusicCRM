import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { PurchaseSubscriptionPreviewDto } from "../dto/issue-subscription.dto";

@Injectable()
export class SubscriptionPurchaseTermsService {
  assertPurchaseReason(
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
          "При оплате другим клиентом обязательно укажите причину.",
      });
    }
  }

  assertFundingMode(dto: PurchaseSubscriptionPreviewDto): void {
    if (
      dto.fundingMode !== "personal_account" &&
      dto.fundingMode !== "installment"
    ) {
      throw new UnprocessableEntityException({
        code: "FUNDING_MODE_INVALID",
        field: "fundingMode",
        message: "Выберите оплату или рассрочку.",
      });
    }
    if (
      dto.fundingMode === "personal_account" &&
      dto.installments !== undefined
    ) {
      throw new UnprocessableEntityException({
        code: "PERSONAL_ACCOUNT_INSTALLMENTS_FORBIDDEN",
        field: "installments",
        message: "Для прямой оплаты рассрочка не применяется.",
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

  normalizeDates(dto: PurchaseSubscriptionPreviewDto): {
    startsAt: string;
    expiresAt: string | null;
  } {
    const today = new Date();
    const defaultStart = this.dateOnly(today);
    const startsAt = this.assertDateOnly(dto.startsAt ?? defaultStart, "startsAt");
    const expiresAt = dto.expiresAt == null
      ? null
      : this.assertDateOnly(dto.expiresAt, "expiresAt");
    if (expiresAt !== null && expiresAt < startsAt) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_DATE_RANGE_INVALID",
        field: "expiresAt",
        message: "Дата окончания не может быть раньше даты начала.",
      });
    }
    return { startsAt, expiresAt };
  }

  normalizePayment(
    dto: PurchaseSubscriptionPreviewDto,
    allowLegacyNullPaymentMethod = false,
  ): {
    amountMinor: string;
    occurredAt: Date | null;
    method: "cash" | "cashless" | null;
    comment: string | null;
  } {
    const rawAmountMinor = dto.paymentAmountMinor ?? "0";
    if (!/^(0|[1-9]\d*)$/.test(rawAmountMinor)) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_AMOUNT_INVALID",
        field: "paymentAmountMinor",
        message: "Сумма оплаты должна быть неотрицательной.",
      });
    }
    const amountMinor = BigInt(rawAmountMinor).toString();
    const comment = dto.paymentComment?.trim() || null;
    if (comment && comment.length > 500) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_COMMENT_TOO_LONG",
        field: "paymentComment",
        message: "Комментарий к оплате не должен превышать 500 символов.",
      });
    }
    if (amountMinor === "0") {
      return { amountMinor, occurredAt: null, method: null, comment };
    }
    if (!dto.paymentMethod && !allowLegacyNullPaymentMethod) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_METHOD_REQUIRED",
        field: "paymentMethod",
        message: "Для фактической оплаты выберите способ оплаты.",
      });
    }
    const occurredAt = dto.paymentOccurredAt
      ? new Date(dto.paymentOccurredAt)
      : new Date();
    if (Number.isNaN(occurredAt.getTime())) {
      throw new UnprocessableEntityException({
        code: "PAYMENT_DATE_INVALID",
        field: "paymentOccurredAt",
        message: "Укажите корректную дату оплаты.",
      });
    }
    return {
      amountMinor,
      occurredAt,
      method: dto.paymentMethod ?? null,
      comment,
    };
  }

  private dateOnly(value: Date): string {
    return value.toISOString().slice(0, 10);
  }

  private assertDateOnly(value: string, field: string): string {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_DATE_INVALID",
        field,
        message: "Укажите дату в формате ГГГГ-ММ-ДД.",
      });
    }
    const parsed = new Date(`${value}T00:00:00.000Z`);
    if (
      Number.isNaN(parsed.getTime()) ||
      parsed.toISOString().slice(0, 10) !== value
    ) {
      throw new UnprocessableEntityException({
        code: "SUBSCRIPTION_DATE_INVALID",
        field,
        message: "Укажите корректную календарную дату.",
      });
    }
    return value;
  }
}
