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
    lessonSettlementTypes: school.lessonSettlementTypes,
    teacherCompensationRules: school.teacherCompensationRules,
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
    ["lessonSettlementTypes", "school"],
    ["teacherCompensationRules", "school"],
  ]) as Record<string, "school" | "branch_override">;
}
