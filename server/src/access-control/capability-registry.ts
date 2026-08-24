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
  {
    key: "access.user.role.assign",
    version: 1,
    domain: "access",
    riskLevel: "critical",
    overrideMode: "locked",
  },
  {
    key: "access.user.override.manage",
    version: 1,
    domain: "access",
    riskLevel: "critical",
    overrideMode: "locked",
  },
  {
    key: "crm.client.read.basic",
    version: 1,
    domain: "crm",
    riskLevel: "medium",
    overrideMode: "allow_deny",
  },
  {
    key: "crm.client.read.contacts",
    version: 1,
    domain: "crm",
    riskLevel: "high",
    overrideMode: "deny_only",
  },
  {
    key: "crm.client.write",
    version: 1,
    domain: "crm",
    riskLevel: "high",
    overrideMode: "deny_only",
  },
  {
    key: "crm.comment.read.shared",
    version: 1,
    domain: "crm",
    riskLevel: "medium",
    overrideMode: "allow_deny",
  },
  {
    key: "schedule.lesson.read.assigned",
    version: 1,
    domain: "schedule",
    riskLevel: "medium",
    overrideMode: "allow_deny",
  },
  {
    key: "schedule.lesson.write",
    version: 1,
    domain: "schedule",
    riskLevel: "high",
    overrideMode: "deny_only",
  },
  {
    key: "schedule.attendance.write",
    version: 1,
    domain: "schedule",
    riskLevel: "critical",
    overrideMode: "locked",
  },
  {
    key: "schedule.lesson.complete",
    version: 1,
    domain: "schedule",
    riskLevel: "critical",
    overrideMode: "locked",
  },
  {
    key: "commerce.client_finance.read",
    version: 1,
    domain: "commerce",
    riskLevel: "high",
    overrideMode: "deny_only",
  },
  {
    key: "commerce.client_finance.write",
    version: 1,
    domain: "commerce",
    riskLevel: "critical",
    overrideMode: "deny_only",
  },
  {
    key: "commerce.school_finance.read",
    version: 1,
    domain: "commerce",
    riskLevel: "critical",
    overrideMode: "locked",
  },
  {
    key: "commerce.teacher_payroll.read",
    version: 1,
    domain: "commerce",
    riskLevel: "high",
    overrideMode: "deny_only",
  },
  {
    key: "commerce.teacher_payroll.write",
    version: 1,
    domain: "commerce",
    riskLevel: "critical",
    overrideMode: "deny_only",
  },
  {
    key: "commerce.package.read",
    version: 1,
    domain: "commerce",
    riskLevel: "medium",
    overrideMode: "allow_deny",
  },
  {
    key: "commerce.package.manage",
    version: 1,
    domain: "commerce",
    riskLevel: "critical",
    overrideMode: "locked",
  },
  {
    key: "commerce.subscription.issue",
    version: 1,
    domain: "commerce",
    riskLevel: "critical",
    overrideMode: "deny_only",
  },
  {
    key: "workflow.task.read",
    version: 1,
    domain: "workflow",
    riskLevel: "medium",
    overrideMode: "allow_deny",
  },
  {
    key: "workflow.task.write",
    version: 1,
    domain: "workflow",
    riskLevel: "high",
    overrideMode: "deny_only",
  },
  {
    key: "report.status.read",
    version: 1,
    domain: "report",
    riskLevel: "high",
    overrideMode: "allow_deny",
  },
  {
    key: "report.export.xlsx",
    version: 1,
    domain: "report",
    riskLevel: "high",
    overrideMode: "allow_deny",
  },
  {
    key: "config.crm.read",
    version: 1,
    domain: "config",
    riskLevel: "medium",
    overrideMode: "allow_deny",
  },
  {
    key: "config.crm.edit",
    version: 1,
    domain: "config",
    riskLevel: "high",
    overrideMode: "allow_deny",
  },
  {
    key: "config.crm.publish",
    version: 1,
    domain: "config",
    riskLevel: "critical",
    overrideMode: "allow_deny",
  },
  {
    key: "config.commerce.manage",
    version: 1,
    domain: "config",
    riskLevel: "critical",
    overrideMode: "locked",
  },
  {
    key: "system.settings.manage",
    version: 1,
    domain: "system",
    riskLevel: "critical",
    overrideMode: "locked",
  },
] as const satisfies readonly CapabilityDefinitionContract[];

export type CapabilityKey = (typeof CAPABILITY_DEFINITIONS)[number]["key"];

const capabilityKeySet = new Set<string>(
  CAPABILITY_DEFINITIONS.map((definition) => definition.key),
);

export function isCapabilityKey(value: string): value is CapabilityKey {
  return capabilityKeySet.has(value);
}

const TEACHER_HARD_DENIES = new Set<CapabilityKey>([
  "crm.client.read.contacts",
  "crm.client.write",
  "schedule.lesson.write",
  "schedule.attendance.write",
  "schedule.lesson.complete",
  "commerce.client_finance.read",
  "commerce.client_finance.write",
  "commerce.package.read",
  "commerce.subscription.issue",
]);

const DIRECTOR_ONLY_CAPABILITIES = new Set<CapabilityKey>([
  "access.user.role.assign",
  "access.user.override.manage",
  "commerce.school_finance.read",
  "commerce.package.manage",
  "config.commerce.manage",
]);

const CONFIG_CAPABILITIES = new Set<CapabilityKey>([
  "config.crm.read",
  "config.crm.edit",
  "config.crm.publish",
  "config.commerce.manage",
]);

const ADMIN_PERSONA_DENIED_CAPABILITIES = new Set<CapabilityKey>([
  "workflow.task.write",
]);

export interface CapabilityHardInvariantDecision {
  allowed: false;
  reason: string;
}

export function resolveCapabilityHardInvariant(
  role: AccessRole,
  capabilityKey: CapabilityKey,
): CapabilityHardInvariantDecision | null {
  if (role === "system_admin") return null;
  if (role === "teacher" && TEACHER_HARD_DENIES.has(capabilityKey)) {
    return { allowed: false, reason: "teacher_hard_deny" };
  }
  if (
    (role === "client" || role === "teacher" || role === "admin") &&
    CONFIG_CAPABILITIES.has(capabilityKey)
  ) {
    return { allowed: false, reason: "config_role_hard_deny" };
  }
  if (role === "admin" && ADMIN_PERSONA_DENIED_CAPABILITIES.has(capabilityKey)) {
    return { allowed: false, reason: "admin_persona_hard_deny" };
  }
  if (DIRECTOR_ONLY_CAPABILITIES.has(capabilityKey) && role !== "director") {
    return { allowed: false, reason: "director_or_system_admin_required" };
  }
  return null;
}
