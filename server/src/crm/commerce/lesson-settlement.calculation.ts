import { ClientChargeFactType, TeacherCompensationFactType } from "./lesson-settlement.port";

const maxMinor = 9_223_372_036_854_775_807n;

export class LessonSettlementCalculationError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

export function durationShareBasisPoints(
  selectedMinutes: number,
  durationMinutes: number,
): number {
  if (!Number.isInteger(selectedMinutes) || selectedMinutes < 0) {
    throw new LessonSettlementCalculationError("INVALID_PARTIAL_DURATION");
  }
  if (!Number.isInteger(durationMinutes) || durationMinutes <= 0) {
    throw new LessonSettlementCalculationError("INVALID_LESSON_DURATION");
  }
  if (selectedMinutes > durationMinutes) {
    throw new LessonSettlementCalculationError(
      "PARTIAL_DURATION_EXCEEDS_LESSON",
    );
  }
  const duration = BigInt(durationMinutes);
  return Number(
    (BigInt(selectedMinutes) * 10_000n + duration / 2n) / duration,
  );
}

function roundRatio(numerator: bigint, denominator: bigint): bigint {
  return (numerator + denominator / 2n) / denominator;
}

export function rublesToMinor(value: string): bigint {
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(value);
  if (!match) throw new LessonSettlementCalculationError("INVALID_MONEY");
  return BigInt(match[1]!) * 100n + BigInt((match[2] ?? "").padEnd(2, "0"));
}

export function minorToRubles(value: bigint): string {
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

function parseTeacherValues(
  configuredValue: string,
  overrideValue: string | undefined,
): { configured: bigint; overridden: bigint } {
  if (
    !/^\d+$/.test(configuredValue) ||
    (overrideValue !== undefined && !/^\d+$/.test(overrideValue))
  ) {
    throw new LessonSettlementCalculationError("INVALID_TEACHER_VALUE");
  }
  const configured = BigInt(configuredValue);
  const overridden = overrideValue === undefined
    ? configured
    : BigInt(overrideValue);
  if (configured > maxMinor || overridden > maxMinor) {
    throw new LessonSettlementCalculationError("TEACHER_VALUE_TOO_LARGE");
  }
  return { configured, overridden };
}

function teacherOverrideState(
  mode: TeacherCompensationFactType,
  overrideValue: string | undefined,
  configured: bigint,
  overridden: bigint,
  overrideReason: string | undefined,
): { hasOverride: boolean; normalizedReason: string | undefined } {
  if (
    (mode === "none" || mode === "standard") &&
    overrideValue !== undefined
  ) {
    throw new LessonSettlementCalculationError("TEACHER_OVERRIDE_NOT_ALLOWED");
  }
  if (mode === "percent" && overridden > 20_000n) {
    throw new LessonSettlementCalculationError("INVALID_TEACHER_PERCENT");
  }
  const hasOverride =
    overrideValue !== undefined && overridden !== configured;
  const normalizedReason = overrideReason?.trim() || undefined;
  if (hasOverride && !normalizedReason) {
    throw new LessonSettlementCalculationError(
      "TEACHER_OVERRIDE_REASON_REQUIRED",
    );
  }
  return { hasOverride, normalizedReason };
}

function resolveTeacherModeValues(
  mode: TeacherCompensationFactType,
  standardAmount: bigint,
  configured: bigint,
  overridden: bigint,
  durationMinutes: number,
): {
  defaultValue: bigint;
  actualValue: bigint;
  rate: bigint;
  amount: bigint;
} {
  switch (mode) {
    case "none":
      return { defaultValue: 0n, actualValue: 0n, rate: 0n, amount: 0n };
    case "standard":
      return {
        defaultValue: standardAmount,
        actualValue: standardAmount,
        rate: standardAmount,
        amount: standardAmount,
      };
    case "percent":
      return {
        defaultValue: standardAmount,
        actualValue: overridden,
        rate: standardAmount,
        amount: roundRatio(standardAmount * overridden, 10_000n),
      };
    case "fixed":
      return {
        defaultValue: configured,
        actualValue: overridden,
        rate: overridden,
        amount: overridden,
      };
    case "hourly":
      return {
        defaultValue: configured,
        actualValue: overridden,
        rate: overridden,
        amount: roundRatio(overridden * BigInt(durationMinutes), 60n),
      };
    default:
      mode satisfies never;
      return {
        defaultValue: configured,
        actualValue: overridden,
        rate: overridden,
        amount: overridden,
      };
  }
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
  const { configured, overridden } = parseTeacherValues(
    input.configuredValue,
    input.overrideValue,
  );
  const { hasOverride, normalizedReason } = teacherOverrideState(
    input.mode,
    input.overrideValue,
    configured,
    overridden,
    input.overrideReason,
  );
  const { defaultValue, actualValue, rate, amount } = resolveTeacherModeValues(
    input.mode,
    standardAmount,
    configured,
    overridden,
    input.durationMinutes,
  );
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
    overrideReason: hasOverride ? normalizedReason! : null,
  };
}
