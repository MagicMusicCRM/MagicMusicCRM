export const USER_ROLES = [
  "client",
  "teacher",
  "admin",
  "manager",
  "director",
  "system_admin",
] as const;

export type AccessRole = (typeof USER_ROLES)[number];
export type CapabilityEffect = "allow" | "deny";
export type CapabilityOverrideMode = "allow_deny" | "deny_only" | "locked";
export type CapabilityRisk = "low" | "medium" | "high" | "critical";

export interface CapabilityDefinitionContract {
  key: string;
  version: 1;
  domain: string;
  riskLevel: CapabilityRisk;
  overrideMode: CapabilityOverrideMode;
}

export const CAPABILITY_DEFINITIONS = [
  { key: "access.user.role.assign", version: 1, domain: "access", riskLevel: "critical", overrideMode: "locked" },
  { key: "access.user.override.manage", version: 1, domain: "access", riskLevel: "critical", overrideMode: "locked" },
  { key: "crm.client.read.basic", version: 1, domain: "crm", riskLevel: "medium", overrideMode: "allow_deny" },
  { key: "crm.client.read.contacts", version: 1, domain: "crm", riskLevel: "high", overrideMode: "deny_only" },
  { key: "crm.client.write", version: 1, domain: "crm", riskLevel: "high", overrideMode: "deny_only" },
  { key: "crm.comment.read.shared", version: 1, domain: "crm", riskLevel: "medium", overrideMode: "allow_deny" },
  { key: "schedule.lesson.read.assigned", version: 1, domain: "schedule", riskLevel: "medium", overrideMode: "allow_deny" },
  { key: "schedule.lesson.write", version: 1, domain: "schedule", riskLevel: "high", overrideMode: "deny_only" },
  { key: "schedule.attendance.write", version: 1, domain: "schedule", riskLevel: "critical", overrideMode: "locked" },
  { key: "schedule.lesson.complete", version: 1, domain: "schedule", riskLevel: "critical", overrideMode: "locked" },
  { key: "commerce.client_finance.read", version: 1, domain: "commerce", riskLevel: "high", overrideMode: "deny_only" },
  { key: "commerce.school_finance.read", version: 1, domain: "commerce", riskLevel: "critical", overrideMode: "locked" },
  { key: "commerce.package.read", version: 1, domain: "commerce", riskLevel: "medium", overrideMode: "allow_deny" },
  { key: "commerce.package.manage", version: 1, domain: "commerce", riskLevel: "critical", overrideMode: "locked" },
  { key: "commerce.subscription.issue", version: 1, domain: "commerce", riskLevel: "critical", overrideMode: "deny_only" },
  { key: "workflow.task.read", version: 1, domain: "workflow", riskLevel: "medium", overrideMode: "allow_deny" },
  { key: "workflow.task.write", version: 1, domain: "workflow", riskLevel: "high", overrideMode: "deny_only" },
  { key: "report.status.read", version: 1, domain: "report", riskLevel: "high", overrideMode: "allow_deny" },
  { key: "report.export.xlsx", version: 1, domain: "report", riskLevel: "high", overrideMode: "allow_deny" },
  { key: "system.settings.manage", version: 1, domain: "system", riskLevel: "critical", overrideMode: "locked" },
] as const satisfies readonly CapabilityDefinitionContract[];

export type CapabilityKey = (typeof CAPABILITY_DEFINITIONS)[number]["key"];

const capabilityKeySet = new Set<string>(
  CAPABILITY_DEFINITIONS.map((definition) => definition.key),
);

export function isCapabilityKey(value: string): value is CapabilityKey {
  return capabilityKeySet.has(value);
}
