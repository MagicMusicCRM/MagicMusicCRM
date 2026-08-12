import { ClientChargeFactType, TeacherCompensationFactType } from "./lesson-settlement.port";

const maxMinor = 9_223_372_036_854_775_807n;

export class LessonSettlementCalculationError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

function roundRatio(numerator: bigint, denominator: bigint): bigint {
  return (numerator + denominator / 2n) / denominator;
}

export function rublesToMinor(value: string): bigint {
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(value);
  if (!match) throw new LessonSettlementCalculationError("INVALID_MONEY");
  return BigInt(match[1]!) * 100n + BigInt((match[2] ?? "").padEnd(2, "0"));
}

function minorToRubles(value: bigint): string {
  return `${value / 100n}.${(value % 100n).toString().padStart(2, "0")}`;
}

export function calculateClientSettlement(input: {
  durationMinutes: number;
  hourShareBasisPoints: number;
  fixedPenaltyMinor: string;
  chargeType: ClientChargeFactType;
  baseChargeMinor: bigint;
}) {
  if (
    !Number.isInteger(input.durationMinutes) || input.durationMinutes <= 0 ||
    !Number.isInteger(input.hourShareBasisPoints) ||
    input.hourShareBasisPoints < 0 || input.hourShareBasisPoints > 20_000 ||
    input.baseChargeMinor < 0n || !/^\d+$/.test(input.fixedPenaltyMinor)
  ) {
    throw new LessonSettlementCalculationError("INVALID_CLIENT_SETTLEMENT");
  }
  const penalty = BigInt(input.fixedPenaltyMinor);
  if (
    input.chargeType === "none" &&
    (input.hourShareBasisPoints > 0 || penalty > 0n)
  ) {
    throw new LessonSettlementCalculationError(
      "CLIENT_FUNDING_SOURCE_REQUIRED",
    );
  }
  const unitsHundredths = input.chargeType === "none"
    ? 0n
    : roundRatio(
        BigInt(input.durationMinutes) * BigInt(input.hourShareBasisPoints),
        6_000n,
      );
  const amount = input.chargeType === "personal_account"
    ? roundRatio(
        input.baseChargeMinor * BigInt(input.hourShareBasisPoints),
        10_000n,
      ) + penalty
    : penalty;
  if (penalty > maxMinor || amount > maxMinor) {
    throw new LessonSettlementCalculationError("CLIENT_AMOUNT_TOO_LARGE");
  }
  return {
    units: `${unitsHundredths / 100n}.${(unitsHundredths % 100n)
      .toString().padStart(2, "0")}`,
    amountMinor: amount.toString(),
  };
}

export function calculateTeacherCompensation(input: {
  durationMinutes: number;
  legacyType: "fixed" | "hourly" | "none";
  legacyRateRubles: string;
  mode: TeacherCompensationFactType;
  configuredValue: string;
  overrideValue?: string;
  overrideReason?: string;
}) {
  if (!Number.isInteger(input.durationMinutes) || input.durationMinutes <= 0) {
    throw new LessonSettlementCalculationError("INVALID_LESSON_DURATION");
  }
  const legacyRate = rublesToMinor(input.legacyRateRubles);
  const standardAmount = input.legacyType === "fixed"
    ? legacyRate
    : input.legacyType === "hourly"
      ? roundRatio(legacyRate * BigInt(input.durationMinutes), 60n)
      : 0n;
  if (!/^\d+$/.test(input.configuredValue) ||
      (input.overrideValue !== undefined && !/^\d+$/.test(input.overrideValue))) {
    throw new LessonSettlementCalculationError("INVALID_TEACHER_VALUE");
  }
  const configured = BigInt(input.configuredValue);
  const overridden = input.overrideValue === undefined
    ? configured
    : BigInt(input.overrideValue);
  if (configured > maxMinor || overridden > maxMinor) {
    throw new LessonSettlementCalculationError("TEACHER_VALUE_TOO_LARGE");
  }
  if ((input.mode === "none" || input.mode === "standard") &&
      input.overrideValue !== undefined) {
    throw new LessonSettlementCalculationError("TEACHER_OVERRIDE_NOT_ALLOWED");
  }
  if (input.mode === "percent" && overridden > 20_000n) {
    throw new LessonSettlementCalculationError("INVALID_TEACHER_PERCENT");
  }
  const hasOverride = input.overrideValue !== undefined && overridden !== configured;
  const overrideReason = input.overrideReason?.trim() || undefined;
  if (hasOverride && !overrideReason) {
    throw new LessonSettlementCalculationError("TEACHER_OVERRIDE_REASON_REQUIRED");
  }

  const defaultValue = input.mode === "standard" || input.mode === "percent"
    ? standardAmount
    : input.mode === "none" ? 0n : configured;
  const actualValue = input.mode === "standard"
    ? standardAmount
    : input.mode === "none" ? 0n : overridden;
  const rate = input.mode === "percent" ? standardAmount : actualValue;
  const amount = input.mode === "hourly"
    ? roundRatio(actualValue * BigInt(input.durationMinutes), 60n)
    : input.mode === "percent"
      ? roundRatio(standardAmount * actualValue, 10_000n)
      : actualValue;
  if (standardAmount > maxMinor || amount > maxMinor) {
    throw new LessonSettlementCalculationError("TEACHER_AMOUNT_TOO_LARGE");
  }
  return {
    standardAmountMinor: standardAmount.toString(),
    defaultValue: defaultValue.toString(),
    actualValue: actualValue.toString(),
    rateMinor: rate.toString(),
    snapshotRate: minorToRubles(rate),
    amountMinor: amount.toString(),
    overrideReason: hasOverride ? overrideReason! : null,
  };
}
