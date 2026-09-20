import {
  calculateClientSettlement,
  calculateTeacherCompensation,
  durationShareBasisPoints,
  LessonSettlementCalculationError,
} from "./lesson-settlement.calculation";

describe("Lesson settlement calculation", () => {
  type TeacherInput = Parameters<typeof calculateTeacherCompensation>[0];
  type TeacherResult = ReturnType<typeof calculateTeacherCompensation>;

  const validTeacherInput: TeacherInput = {
    durationMinutes: 60,
    legacyType: "fixed",
    legacyRateRubles: "700.00",
    mode: "fixed",
    configuredValue: "50000",
  };

  it.each([
    [0, 30, 0],
    [30, 30, 10_000],
    [15, 30, 5_000],
    [45, 60, 7_500],
    [30, 90, 3_333],
  ])("converts %i of %i minutes to %i basis points", (
    selectedMinutes,
    durationMinutes,
    expected,
  ) => {
    expect(durationShareBasisPoints(selectedMinutes, durationMinutes)).toBe(
      expected,
    );
  });

  it.each([
    [-1, 60, "INVALID_PARTIAL_DURATION"],
    [1.5, 60, "INVALID_PARTIAL_DURATION"],
    [61, 60, "PARTIAL_DURATION_EXCEEDS_LESSON"],
  ])("rejects partial duration %s/%s", (selected, duration, code) => {
    expect(() => durationShareBasisPoints(selected, duration)).toThrow(
      expect.objectContaining({ code }),
    );
  });

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
    ).toEqual({
      hourShareBasisPoints: share,
      units,
      amountMinor: amount,
    });
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
    ).toEqual({
      hourShareBasisPoints: 0,
      units: "0.00",
      amountMinor: "0",
    });

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

  it.each([
      {
        mode: "none",
        configuredValue: "0",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "0",
          actualValue: "0",
          rateMinor: "0",
          snapshotRate: "0.00",
          amountMinor: "0",
          overrideReason: null,
        },
      },
      {
        mode: "standard",
        configuredValue: "0",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "75000",
          actualValue: "75000",
          rateMinor: "75000",
          snapshotRate: "750.00",
          amountMinor: "75000",
          overrideReason: null,
        },
      },
      {
        mode: "percent",
        configuredValue: "5000",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "75000",
          actualValue: "5000",
          rateMinor: "75000",
          snapshotRate: "750.00",
          amountMinor: "37500",
          overrideReason: null,
        },
      },
      {
        mode: "fixed",
        configuredValue: "60000",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "60000",
          actualValue: "60000",
          rateMinor: "60000",
          snapshotRate: "600.00",
          amountMinor: "60000",
          overrideReason: null,
        },
      },
      {
        mode: "hourly",
        configuredValue: "120000",
        expected: {
          standardAmountMinor: "75000",
          defaultValue: "120000",
          actualValue: "120000",
          rateMinor: "120000",
          snapshotRate: "1200.00",
          amountMinor: "90000",
          overrideReason: null,
        },
      },
  ] satisfies Array<{
    mode: TeacherInput["mode"];
    configuredValue: string;
    expected: TeacherResult;
  }>)("calculates the complete $mode result", ({
    mode,
    configuredValue,
    expected,
  }) => {
    expect(calculateTeacherCompensation({
      durationMinutes: 45,
      legacyType: "hourly",
      legacyRateRubles: "1000.00",
      mode,
      configuredValue,
    })).toEqual(expected);
  });

  it.each([
    {
      legacyType: "fixed",
      expected: {
        standardAmountMinor: "100000", defaultValue: "100000",
        actualValue: "100000", rateMinor: "100000", snapshotRate: "1000.00",
        amountMinor: "100000", overrideReason: null,
      },
    },
    {
      legacyType: "hourly",
      expected: {
        standardAmountMinor: "75000", defaultValue: "75000",
        actualValue: "75000", rateMinor: "75000", snapshotRate: "750.00",
        amountMinor: "75000", overrideReason: null,
      },
    },
    {
      legacyType: "none",
      expected: {
        standardAmountMinor: "0", defaultValue: "0", actualValue: "0",
        rateMinor: "0", snapshotRate: "0.00", amountMinor: "0",
        overrideReason: null,
      },
    },
  ] satisfies Array<{
    legacyType: TeacherInput["legacyType"];
    expected: TeacherResult;
  }>)("preserves the complete legacy $legacyType result", ({
    legacyType,
    expected,
  }) => {
    expect(calculateTeacherCompensation({
      durationMinutes: 45,
      legacyType,
      legacyRateRubles: "1000.00",
      mode: "standard",
      configuredValue: "0",
    })).toEqual(expected);
  });

  it.each([
    {
      name: "legacy hourly below half",
      input: { durationMinutes: 29, legacyType: "hourly", legacyRateRubles: "0.01", mode: "standard", configuredValue: "0" },
      expected: { standardAmountMinor: "0", defaultValue: "0", actualValue: "0", rateMinor: "0", snapshotRate: "0.00", amountMinor: "0", overrideReason: null },
    },
    {
      name: "legacy hourly exact half",
      input: { durationMinutes: 30, legacyType: "hourly", legacyRateRubles: "0.01", mode: "standard", configuredValue: "0" },
      expected: { standardAmountMinor: "1", defaultValue: "1", actualValue: "1", rateMinor: "1", snapshotRate: "0.01", amountMinor: "1", overrideReason: null },
    },
    {
      name: "teacher hourly below half",
      input: { durationMinutes: 29, legacyType: "none", legacyRateRubles: "0", mode: "hourly", configuredValue: "1" },
      expected: { standardAmountMinor: "0", defaultValue: "1", actualValue: "1", rateMinor: "1", snapshotRate: "0.01", amountMinor: "0", overrideReason: null },
    },
    {
      name: "teacher hourly exact half",
      input: { durationMinutes: 30, legacyType: "none", legacyRateRubles: "0", mode: "hourly", configuredValue: "1" },
      expected: { standardAmountMinor: "0", defaultValue: "1", actualValue: "1", rateMinor: "1", snapshotRate: "0.01", amountMinor: "1", overrideReason: null },
    },
    {
      name: "percent below half",
      input: { durationMinutes: 60, legacyType: "fixed", legacyRateRubles: "0.01", mode: "percent", configuredValue: "4999" },
      expected: { standardAmountMinor: "1", defaultValue: "1", actualValue: "4999", rateMinor: "1", snapshotRate: "0.01", amountMinor: "0", overrideReason: null },
    },
    {
      name: "percent exact half",
      input: { durationMinutes: 60, legacyType: "fixed", legacyRateRubles: "0.01", mode: "percent", configuredValue: "5000" },
      expected: { standardAmountMinor: "1", defaultValue: "1", actualValue: "5000", rateMinor: "1", snapshotRate: "0.01", amountMinor: "1", overrideReason: null },
    },
  ] satisfies Array<{ name: string; input: TeacherInput; expected: TeacherResult }>)(
    "$name uses half-up rounding",
    ({ input, expected }) => {
      expect(calculateTeacherCompensation(input)).toEqual(expected);
    },
  );

  it.each([
    {
      name: "numerically equal override",
      input: { ...validTeacherInput, overrideValue: "050000", overrideReason: "Игнорируется" },
      expected: { standardAmountMinor: "70000", defaultValue: "50000", actualValue: "50000", rateMinor: "50000", snapshotRate: "500.00", amountMinor: "50000", overrideReason: null },
    },
    {
      name: "changed override",
      input: { ...validTeacherInput, overrideValue: "60000", overrideReason: "  Согласовано директором  " },
      expected: { standardAmountMinor: "70000", defaultValue: "50000", actualValue: "60000", rateMinor: "60000", snapshotRate: "600.00", amountMinor: "60000", overrideReason: "Согласовано директором" },
    },
    {
      name: "percent validates the overridden value",
      input: { ...validTeacherInput, mode: "percent", configuredValue: "20001", overrideValue: "20000", overrideReason: "  Согласовано директором  " },
      expected: { standardAmountMinor: "70000", defaultValue: "70000", actualValue: "20000", rateMinor: "70000", snapshotRate: "700.00", amountMinor: "140000", overrideReason: "Согласовано директором" },
    },
  ] satisfies Array<{ name: string; input: TeacherInput; expected: TeacherResult }>)(
    "$name returns the complete normalized result",
    ({ input, expected }) => {
      expect(calculateTeacherCompensation(input)).toEqual(expected);
    },
  );

  it.each([
    { name: "duration before every later invalidity", input: { durationMinutes: 0, legacyRateRubles: "bad", mode: "percent", configuredValue: "bad", overrideValue: "bad", overrideReason: " " }, code: "INVALID_LESSON_DURATION" },
    { name: "legacy money before teacher syntax", input: { legacyRateRubles: "bad", mode: "percent", configuredValue: "bad", overrideValue: "bad", overrideReason: " " }, code: "INVALID_MONEY" },
    { name: "teacher syntax before teacher limit", input: { legacyRateRubles: "92233720368547758.08", mode: "standard", configuredValue: "bad", overrideValue: "9223372036854775808" }, code: "INVALID_TEACHER_VALUE" },
    { name: "teacher limit before override prohibition", input: { mode: "standard", configuredValue: "9223372036854775808", overrideValue: "1" }, code: "TEACHER_VALUE_TOO_LARGE" },
    { name: "override prohibition before reason and final limit", input: { legacyRateRubles: "92233720368547758.08", mode: "standard", configuredValue: "0", overrideValue: "1" }, code: "TEACHER_OVERRIDE_NOT_ALLOWED" },
    { name: "percent limit before reason and final limit", input: { legacyRateRubles: "92233720368547758.08", mode: "percent", configuredValue: "0", overrideValue: "20001" }, code: "INVALID_TEACHER_PERCENT" },
    { name: "changed override reason before final limit", input: { legacyRateRubles: "92233720368547758.08", mode: "fixed", configuredValue: "1", overrideValue: "2", overrideReason: " " }, code: "TEACHER_OVERRIDE_REASON_REQUIRED" },
    { name: "final standard limit", input: { legacyRateRubles: "92233720368547758.08", mode: "fixed", configuredValue: "1" }, code: "TEACHER_AMOUNT_TOO_LARGE" },
    { name: "final calculated amount limit", input: { durationMinutes: 61, legacyType: "none", legacyRateRubles: "0", mode: "hourly", configuredValue: "9223372036854775807" }, code: "TEACHER_AMOUNT_TOO_LARGE" },
    { name: "none rejects even an equal override", input: { mode: "none", configuredValue: "0", overrideValue: "0", overrideReason: "Игнорируется" }, code: "TEACHER_OVERRIDE_NOT_ALLOWED" },
  ] satisfies Array<{ name: string; input: Partial<TeacherInput>; code: string }>)(
    "$name",
    ({ input, code }) => {
      expect(() => calculateTeacherCompensation({
        ...validTeacherInput,
        ...input,
      })).toThrow(new LessonSettlementCalculationError(code));
    },
  );
});
