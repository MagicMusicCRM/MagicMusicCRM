import { isDeepStrictEqual } from "node:util";
import type {
  ConfigBranchPatch,
  ConfigSnapshot,
} from "./crm-configuration.contracts";

export function sameCrmConfigurationValue(
  left: unknown,
  right: unknown,
): boolean {
  return isDeepStrictEqual(
    JSON.parse(JSON.stringify(left)),
    JSON.parse(JSON.stringify(right)),
  );
}

export function createCrmConfigurationBranchPatch(
  school: ConfigSnapshot,
  desired: ConfigSnapshot,
): ConfigBranchPatch {
  const defaults = new Map(
    school.businessSettings.map((setting) => [setting.key, setting]),
  );
  return {
    businessSettings: desired.businessSettings.filter(
      (setting) => setting.value !== defaults.get(setting.key)?.value,
    ),
    ...(!sameCrmConfigurationValue(
      desired.lessonSettlementTypes,
      school.lessonSettlementTypes,
    )
      ? { lessonSettlementTypes: desired.lessonSettlementTypes }
      : {}),
    ...(!sameCrmConfigurationValue(
      desired.teacherCompensationRules,
      school.teacherCompensationRules,
    )
      ? { teacherCompensationRules: desired.teacherCompensationRules }
      : {}),
  };
}

export function applyCrmConfigurationBranchPatch(
  school: ConfigSnapshot,
  patch: ConfigBranchPatch,
): ConfigSnapshot {
  const overrides = new Map(
    (patch.businessSettings ?? []).map((setting) => [setting.key, setting]),
  );
  return {
    ...school,
    businessSettings: school.businessSettings.map(
      (setting) => overrides.get(setting.key) ?? setting,
    ),
    lessonSettlementTypes:
      patch.lessonSettlementTypes ?? school.lessonSettlementTypes,
    teacherCompensationRules:
      patch.teacherCompensationRules ?? school.teacherCompensationRules,
  };
}

export function getCrmConfigurationSettingSources(
  snapshot: ConfigSnapshot,
  school: ConfigSnapshot,
): Record<string, "school" | "branch_override"> {
  const defaults = new Map(
    school.businessSettings.map((setting) => [setting.key, setting.value]),
  );
  return Object.fromEntries([
    ...snapshot.businessSettings.map((setting) => [
      setting.key,
      setting.value === defaults.get(setting.key)
        ? "school"
        : "branch_override",
    ]),
    [
      "lessonSettlementTypes",
      sameCrmConfigurationValue(
        snapshot.lessonSettlementTypes,
        school.lessonSettlementTypes,
      )
        ? "school"
        : "branch_override",
    ],
    [
      "teacherCompensationRules",
      sameCrmConfigurationValue(
        snapshot.teacherCompensationRules,
        school.teacherCompensationRules,
      )
        ? "school"
        : "branch_override",
    ],
  ]) as Record<string, "school" | "branch_override">;
}
