import { buildCrmConfigurationBaseline } from "./crm-configuration-baseline";
import {
  applyCrmConfigurationBranchPatch,
  createCrmConfigurationBranchPatch,
  getCrmConfigurationSettingSources,
} from "./crm-configuration-branch.policy";

describe("CRM configuration branch policy", () => {
  it("stores only changed branch settings and commerce catalogs", () => {
    const school = buildCrmConfigurationBaseline([]);
    const desired = structuredClone(school);
    desired.businessSettings[0].value = 45;
    desired.lessonSettlementTypes[0].label = "Обычное занятие";

    const patch = createCrmConfigurationBranchPatch(school, desired);

    expect(patch).toEqual({
      businessSettings: [desired.businessSettings[0]],
      lessonSettlementTypes: desired.lessonSettlementTypes,
    });
  });

  it("attributes inherited and overridden values to their source", () => {
    const school = buildCrmConfigurationBaseline([]);
    const desired = structuredClone(school);
    desired.businessSettings[0].value = 45;
    desired.lessonSettlementTypes[0].label = "Обычное занятие";

    expect(getCrmConfigurationSettingSources(desired, school)).toMatchObject({
      default_lesson_duration_minutes: "branch_override",
      payment_reminder_days: "school",
      lessonSettlementTypes: "branch_override",
      teacherCompensationRules: "school",
    });
  });

  it("round-trips a sparse patch over its school snapshot", () => {
    const school = buildCrmConfigurationBaseline([]);
    const desired = structuredClone(school);
    desired.businessSettings[1].value = 7;
    desired.teacherCompensationRules[0].label = "Без оплаты";

    expect(
      applyCrmConfigurationBranchPatch(
        school,
        createCrmConfigurationBranchPatch(school, desired),
      ),
    ).toEqual(desired);
  });
});
