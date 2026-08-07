import {
  calculateClientSettlement,
  calculateTeacherCompensation,
  LessonSettlementCalculationError,
} from "./lesson-settlement.calculation";

describe("Lesson settlement calculation", () => {
  it.each([
    [0, "0.00", "250"],
    [5_000, "0.50", "50250"],
    [10_000, "1.00", "100250"],
    [20_000, "2.00", "200250"],
  ])("calculates %i bp and a fixed penalty exactly", (share, units, amount) => {
    expect(calculateClientSettlement({
      durationMinutes: 60,
      hourShareBasisPoints: share,
      fixedPenaltyMinor: "250",
      chargeType: "personal_account",
      baseChargeMinor: 100_000n,
    })).toEqual({ units, amountMinor: amount });
  });

  it("calculates independent teacher modes and requires a reason for override", () => {
    expect(calculateTeacherCompensation({
      durationMinutes: 45,
      legacyType: "hourly",
      legacyRateRubles: "1000.00",
      mode: "percent",
      configuredValue: "5000",
    })).toMatchObject({
      standardAmountMinor: "75000",
      defaultValue: "75000",
      actualValue: "5000",
      amountMinor: "37500",
    });
    expect(() => calculateTeacherCompensation({
      durationMinutes: 60,
      legacyType: "fixed",
      legacyRateRubles: "700.00",
      mode: "fixed",
      configuredValue: "50000",
      overrideValue: "60000",
    })).toThrow(new LessonSettlementCalculationError(
      "TEACHER_OVERRIDE_REASON_REQUIRED",
    ));
  });
});
