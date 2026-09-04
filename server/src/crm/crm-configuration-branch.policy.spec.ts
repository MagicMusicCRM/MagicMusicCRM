import { buildCrmConfigurationBaseline } from "./crm-configuration-baseline";
import {
  applyCrmConfigurationBranchPatch,
  createCrmConfigurationBranchPatch,
  getCrmConfigurationSettingSources,
} from "./crm-configuration-branch.policy";

describe("CRM configuration branch policy", () => {
  it("stores only changed branch-overridable settings", () => {
    const school = buildCrmConfigurationBaseline([]);
    const desired = structuredClone(school);
    desired.businessSettings[0].value = 45;
    desired.lessonSettlementTypes[0].label = "Обычное занятие";

    const patch = createCrmConfigurationBranchPatch(school, desired);

    expect(patch).toEqual({
      businessSettings: [desired.businessSettings[0]],
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
      lessonSettlementTypes: "school",
      teacherCompensationRules: "school",
    });
  });

  it("ignores a legacy protected-catalog patch over the school snapshot", () => {
    const school = buildCrmConfigurationBaseline([]);
    const desired = structuredClone(school);
    desired.businessSettings[1].value = 7;
    desired.teacherCompensationRules[0].label = "Без оплаты";

    const effective = applyCrmConfigurationBranchPatch(school, {
      businessSettings: [desired.businessSettings[1]],
      teacherCompensationRules: desired.teacherCompensationRules,
    });

    expect(effective.businessSettings[1]).toEqual(
      desired.businessSettings[1],
    );
    expect(effective.teacherCompensationRules).toEqual(
      school.teacherCompensationRules,
    );
  });
});
