import { UnprocessableEntityException } from "@nestjs/common";
import type { IssueSubscriptionDiscountDto, IssueSubscriptionSurchargeDto } from "../dto/issue-subscription.dto";
import type { NormalizedDiscount, NormalizedSurcharge } from "./subscription-issue.contracts";

export function normalizeCommercialPrice(basePriceMinor: string, dto: { discount?: IssueSubscriptionDiscountDto; surcharge?: IssueSubscriptionSurchargeDto }) {
  const discount = normalizeDiscount(dto.discount, basePriceMinor);
  const surcharge = normalizeSurcharge(dto.surcharge);
  return { discount, surcharge, finalPriceMinor: (BigInt(discount.finalPriceMinor) + BigInt(surcharge.amountMinor)).toString() };
}

function normalizeDiscount(
  dto: IssueSubscriptionDiscountDto | undefined,
  rawBasePriceMinor: string,
): NormalizedDiscount {
  if (!dto) return normalizeNoDiscount(rawBasePriceMinor);
  const reason = discountReason(dto);
  if (dto.type === "percent") {
    return normalizePercentDiscount(dto, rawBasePriceMinor, reason);
  }
  return normalizeFixedDiscount(dto, rawBasePriceMinor, reason);
}

function normalizeNoDiscount(rawBasePriceMinor: string): NormalizedDiscount {
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

function discountReason(dto: IssueSubscriptionDiscountDto): string {
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

function normalizePercentDiscount(
  dto: IssueSubscriptionDiscountDto,
  rawBasePriceMinor: string,
  reason: string,
): NormalizedDiscount {
  if (dto.percent === undefined || dto.fixedMinor !== undefined) {
    throwDiscountShape();
  }
  const percent = dto.percent!;
  const basisPoints = Math.round(percent * 100);
  if (!isValidPercent(percent, basisPoints)) {
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

function isValidPercent(percent: number, basisPoints: number): boolean {
  return (
    Number.isFinite(percent) &&
    percent > 0 &&
    percent <= 100 &&
    basisPoints >= 1 &&
    basisPoints <= 10_000 &&
    Math.abs(percent * 100 - basisPoints) <= 1e-8
  );
}

function normalizeFixedDiscount(
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
    throwDiscountShape();
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


function normalizeSurcharge(
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


function throwDiscountShape(): never {
  throw new UnprocessableEntityException({
    code: "DISCOUNT_SHAPE_INVALID",
    field: "discount",
    message: "Укажите либо процентную, либо фиксированную скидку, но не обе.",
  });
}
