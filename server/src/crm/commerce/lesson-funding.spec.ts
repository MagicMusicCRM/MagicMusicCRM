import { resolveLessonFunding } from "./lesson-funding";

const charge = { client_type: "student" as const, client_id: "student", charge_type: "subscription" as const, charge_value: "1.00", subscription_id: "subscription" };

describe("lesson funding", () => {
  it("clears an inherited subscription and calculates shared discount/surcharge rules in minor units", () => {
    expect(resolveLessonFunding(charge, {
      clientId: "student", payerStudentId: "payer", chargeType: "personal_account", basePriceMinor: "100001",
      discount: { type: "percent", percent: 10, reason: "Скидка" }, surcharge: { amountMinor: "1999", reason: "Доплата" },
    })).toMatchObject({ chargeType: "personal_account", subscriptionId: null, payerStudentId: "payer", baseChargeMinor: 92000n,
      pricingSnapshot: { basePriceMinor: "100001", finalPriceMinor: "92000" },
    });
  });

  it("requires an explicit personal-account price and rejects pricing attached to subscription funding", () => {
    expect(() => resolveLessonFunding(charge, { clientId: "student", chargeType: "personal_account" })).toThrow();
    expect(() => resolveLessonFunding(charge, { clientId: "student", chargeType: "subscription", basePriceMinor: "100" })).toThrow();
    expect(() => resolveLessonFunding(charge, { clientId: "student", chargeType: "personal_account", basePriceMinor: "100", discount: { type: "fixed", fixedMinor: "101", reason: "Скидка" } })).toThrow();
  });

  it("uses the recipient as the default payer and preserves legacy personal-account pricing", () => {
    expect(resolveLessonFunding({ ...charge, charge_type: "personal_account", charge_value: "321.09", subscription_id: null })).toMatchObject({ payerStudentId: "student", baseChargeMinor: 32109n });
  });

  it("requires a student payer for explicit personal-account funding of a lead", () => {
    const lead = { ...charge, client_type: "lead" as const };
    expect(() => resolveLessonFunding(lead, { clientId: "lead", chargeType: "personal_account", basePriceMinor: "10000" })).toThrow();
    expect(resolveLessonFunding(lead, { clientId: "lead", chargeType: "personal_account", basePriceMinor: "10000", payerStudentId: "payer" })).toMatchObject({ payerStudentId: "payer", baseChargeMinor: 10000n });
    expect(resolveLessonFunding(lead, { clientId: "lead", chargeType: "none" })).toMatchObject({ payerStudentId: null, baseChargeMinor: 0n });
  });
});
