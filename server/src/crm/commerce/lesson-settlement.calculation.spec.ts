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
    expect(
      calculateClientSettlement({
        durationMinutes: 60,
        hourShareBasisPoints: share,
        fixedPenaltyMinor: "250",
        chargeType: "personal_account",
        baseChargeMinor: 100_000n,
      }),
    ).toEqual({ units, amountMinor: amount });
  });

  it("allows no funding only when both the share and penalty are zero", () => {
    expect(
      calculateClientSettlement({
        durationMinutes: 60,
        hourShareBasisPoints: 0,
        fixedPenaltyMinor: "0",
        chargeType: "none",
        baseChargeMinor: 0n,
      }),
    ).toEqual({ units: "0.00", amountMinor: "0" });

    for (const input of [
      { hourShareBasisPoints: 10_000, fixedPenaltyMinor: "0" },
      { hourShareBasisPoints: 0, fixedPenaltyMinor: "250" },
    ]) {
      expect(() =>
        calculateClientSettlement({
          durationMinutes: 60,
          ...input,
          chargeType: "none",
          baseChargeMinor: 0n,
        })
      ).toThrow(
        new LessonSettlementCalculationError(
          "CLIENT_FUNDING_SOURCE_REQUIRED",
        ),
      );
    }
  });

  it("calculates all five independent teacher compensation modes", () => {
    const scenarios = [
      {
        mode: "none" as const,
        configuredValue: "0",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "0",
          actualValue: "0",
          rateMinor: "0",
          amountMinor: "0",
        },
      },
      {
        mode: "standard" as const,
        configuredValue: "0",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "75000",
          actualValue: "75000",
          rateMinor: "75000",
          amountMinor: "75000",
        },
      },
      {
        mode: "percent" as const,
        configuredValue: "5000",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "75000",
          actualValue: "5000",
          rateMinor: "75000",
          amountMinor: "37500",
        },
      },
      {
        mode: "fixed" as const,
        configuredValue: "60000",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "60000",
          actualValue: "60000",
          rateMinor: "60000",
          amountMinor: "60000",
        },
      },
      {
        mode: "hourly" as const,
        configuredValue: "120000",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "120000",
          actualValue: "120000",
          rateMinor: "120000",
          amountMinor: "90000",
        },
      },
    ];

    for (const scenario of scenarios) {
      expect(
        calculateTeacherCompensation({
          durationMinutes: 45,
          legacyType: "hourly",
          legacyRateRubles: "1000.00",
          mode: scenario.mode,
          configuredValue: scenario.configuredValue,
        }),
      ).toMatchObject(scenario.expected);
    }
  });

  it("accepts a changed override only with a non-empty reason", () => {
    expect(() =>
      calculateTeacherCompensation({
        durationMinutes: 60,
        legacyType: "fixed",
        legacyRateRubles: "700.00",
        mode: "fixed",
        configuredValue: "50000",
        overrideValue: "60000",
      }),
    ).toThrow(
      new LessonSettlementCalculationError("TEACHER_OVERRIDE_REASON_REQUIRED"),
    );

    expect(
      calculateTeacherCompensation({
        durationMinutes: 60,
        legacyType: "fixed",
        legacyRateRubles: "700.00",
        mode: "fixed",
        configuredValue: "50000",
        overrideValue: "60000",
        overrideReason: "Согласовано директором",
      }),
    ).toMatchObject({
      defaultValue: "50000",
      actualValue: "60000",
      amountMinor: "60000",
      overrideReason: "Согласовано директором",
    });

    for (const mode of ["none", "standard"] as const) {
      expect(() =>
        calculateTeacherCompensation({
          durationMinutes: 60,
          legacyType: "fixed",
          legacyRateRubles: "700.00",
          mode,
          configuredValue: "0",
          overrideValue: "1",
          overrideReason: "Не должно применяться",
        }),
      ).toThrow(
        new LessonSettlementCalculationError("TEACHER_OVERRIDE_NOT_ALLOWED"),
      );
    }
  });
});
