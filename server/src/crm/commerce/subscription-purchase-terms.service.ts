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
          "При оплате со счёта другого клиента обязательно укажите причину.",
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
        message: "Выберите личный счёт или рассрочку.",
      });
    }
    if (
      dto.fundingMode === "personal_account" &&
      dto.installments !== undefined
    ) {
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

  normalizeDates(dto: PurchaseSubscriptionPreviewDto): {
    startsAt: string;
    expiresAt: string;
  } {
    const today = new Date();
    const defaultStart = this.dateOnly(today);
    const startsAt = this.assertDateOnly(dto.startsAt ?? defaultStart, "startsAt");
    const expiresAt = this.assertDateOnly(
      dto.expiresAt ?? this.addCalendarMonth(startsAt),
      "expiresAt",
    );
    if (expiresAt < startsAt) {
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

  private addCalendarMonth(value: string): string {
    const source = new Date(`${value}T00:00:00.000Z`);
    const year = source.getUTCFullYear();
    const month = source.getUTCMonth();
    const day = source.getUTCDate();
    const firstOfTarget = new Date(Date.UTC(year, month + 1, 1));
    const lastDay = new Date(
      Date.UTC(
        firstOfTarget.getUTCFullYear(),
        firstOfTarget.getUTCMonth() + 1,
        0,
      ),
    ).getUTCDate();
    const target = new Date(
      Date.UTC(
        firstOfTarget.getUTCFullYear(),
        firstOfTarget.getUTCMonth(),
        Math.min(day, lastDay),
      ),
    );
    return this.dateOnly(target);
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
