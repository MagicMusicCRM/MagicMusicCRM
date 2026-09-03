import { ValidationPipe } from "@nestjs/common";
import { ConfiguredLessonFinancialDecisionDto } from "./lesson-financial-decision.dto";
import { resolveLessonFunding } from "../commerce/lesson-funding";

const clientId = "10000000-0000-4000-8000-000000000001";
const pipe = new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true });
const payload = (clientDecision: Record<string, unknown>) => ({
  settlementTypeKey: "lesson",
  teacherCompensationRuleKey: "standard",
  clientDecisions: [{ clientId, chargeType: "personal_account", basePriceMinor: "100001", ...clientDecision }],
});
const validate = (value: unknown) => pipe.transform(value, {
  type: "body", metatype: ConfiguredLessonFinancialDecisionDto,
}) as Promise<ConfiguredLessonFinancialDecisionDto>;

describe("lesson financial decision HTTP contract", () => {
  it("accepts manual fractional percent and calculates it in minor units", async () => {
    const dto = await validate(payload({ discount: { type: "percent", percent: "12.5", reason: "Скидка" } }));
    expect(dto.clientDecisions?.[0]?.discount?.percent).toBe(12.5);
    expect(resolveLessonFunding({ client_id: clientId, client_type: "student", charge_type: "none", charge_value: "0", subscription_id: null }, dto.clientDecisions?.[0])).toMatchObject({ baseChargeMinor: 87501n });
  });

  it("accepts omitted adjustments for personal account and free funding", async () => {
    await expect(validate(payload({}))).resolves.toMatchObject({ clientDecisions: [{ basePriceMinor: "100001" }] });
    const dto = await validate({ settlementTypeKey: "free_lesson", teacherCompensationRuleKey: "standard", clientDecisions: [{ clientId, chargeType: "none" }] });
    expect(resolveLessonFunding({ client_id: clientId, client_type: "student", charge_type: "personal_account", charge_value: "100", subscription_id: null }, dto.clientDecisions?.[0])).toMatchObject({ chargeType: "none", payerStudentId: null, baseChargeMinor: 0n });
  });

  it.each([
    { discount: { type: "percent", percentBasisPoints: 1250, reason: "Скидка" } },
    { discount: { type: "none" } },
    { surcharge: { type: "none" } },
    { basePriceMinor: "-1" },
  ])("rejects projection-only or invalid pricing shapes: %j", async (invalid) => {
    await expect(validate(payload(invalid))).rejects.toMatchObject({ status: 400 });
  });

  it("rejects caller-supplied server-owned teacher rate snapshots", async () => {
    await expect(validate({ ...payload({}), teacherRateSnapshot: { type: "hourly", value: "9999" } })).rejects.toMatchObject({ status: 400 });
  });

  it("accepts exact client and teacher partial durations", async () => {
    await expect(validate({
      settlementTypeKey: "partially_paid_lesson",
      teacherCompensationRuleKey: "percent",
      teacherCreditedDurationMinutes: 45,
      teacherCompensationSource: "manual",
      clientDecisions: [{ clientId, chargeDurationMinutes: 30 }],
    })).resolves.toMatchObject({
      teacherCreditedDurationMinutes: 45,
      teacherCompensationSource: "manual",
      clientDecisions: [{ clientId, chargeDurationMinutes: 30 }],
    });
  });

  it.each([
    { teacherCreditedDurationMinutes: -1 },
    { teacherCreditedDurationMinutes: 1.5 },
    { teacherCompensationSource: "inferred" },
    { clientDecisions: [{ clientId, chargeDurationMinutes: -1 }] },
    { clientDecisions: [{ clientId, chargeDurationMinutes: 1.5 }] },
  ])("rejects invalid partial duration shape: %j", async (invalid) => {
    await expect(validate({
      settlementTypeKey: "partially_paid_lesson",
      teacherCompensationRuleKey: "percent",
      ...invalid,
    })).rejects.toMatchObject({ status: 400 });
  });

  it("does not interpret an explicit null price as the old subscription snapshot value", async () => {
    const dto = await validate(payload({ basePriceMinor: null }));
    expect(() => resolveLessonFunding({ client_id: clientId, client_type: "student", charge_type: "subscription", charge_value: "1", subscription_id: clientId }, dto.clientDecisions?.[0])).toThrow();
  });
});
