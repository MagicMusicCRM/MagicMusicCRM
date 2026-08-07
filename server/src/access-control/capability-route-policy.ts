import { AccessRole, CapabilityKey, USER_ROLES } from "./capability-registry";

export type CapabilityResourceScope =
  "self" | "self_or_assigned" | "branch" | "resource" | "global" | "emergency";

export interface CapabilityRoutePolicy {
  capabilityKey: CapabilityKey;
  scope: CapabilityResourceScope;
  legacyAllowedRoles: readonly AccessRole[];
  legacyPolicy: string;
  authenticatedOnly?: boolean;
}

const allRoles = [...USER_ROLES] as readonly AccessRole[];
const staffRoles = [
  "admin",
  "manager",
  "director",
  "system_admin",
] as const satisfies readonly AccessRole[];
const managementRoles = [
  "manager",
  "director",
  "system_admin",
] as const satisfies readonly AccessRole[];
const rootBusinessRoles = [
  "director",
  "system_admin",
] as const satisfies readonly AccessRole[];
const teacherAndStaffRoles = [
  "teacher",
  ...staffRoles,
] as const satisfies readonly AccessRole[];
const taskReaders = [
  "teacher",
  ...managementRoles,
] as const satisfies readonly AccessRole[];

export const BASELINE_CAPABILITY_ROLES: Readonly<
  Record<CapabilityKey, readonly AccessRole[]>
> = {
  "access.user.role.assign": rootBusinessRoles,
  "access.user.override.manage": rootBusinessRoles,
  "crm.client.read.basic": allRoles,
  "crm.client.read.contacts": ["client", ...staffRoles],
  "crm.client.write": staffRoles,
  "crm.comment.read.shared": teacherAndStaffRoles,
  "schedule.lesson.read.assigned": allRoles,
  "schedule.lesson.write": staffRoles,
  "schedule.attendance.write": staffRoles,
  "schedule.lesson.complete": staffRoles,
  "commerce.client_finance.read": ["client", ...staffRoles],
  "commerce.client_finance.write": staffRoles,
  "commerce.school_finance.read": rootBusinessRoles,
  "commerce.package.read": staffRoles,
  "commerce.package.manage": rootBusinessRoles,
  "commerce.subscription.issue": staffRoles,
  "workflow.task.read": taskReaders,
  "workflow.task.write": managementRoles,
  "report.status.read": managementRoles,
  "report.export.xlsx": managementRoles,
  "config.crm.read": rootBusinessRoles,
  "config.crm.edit": rootBusinessRoles,
  "config.crm.publish": rootBusinessRoles,
  "config.commerce.manage": rootBusinessRoles,
  "system.settings.manage": managementRoles,
};

function normalizePath(path: string): string {
  const queryIndex = path.indexOf("?");
  const withoutQuery = queryIndex >= 0 ? path.slice(0, queryIndex) : path;
  const withoutApi = withoutQuery.replace(/^\/api(?=\/|$)/, "");
  return (withoutApi || "/").replace(/\/+/g, "/").replace(/\/$/, "") || "/";
}

function isRead(method: string): boolean {
  return method === "GET" || method === "HEAD" || method === "OPTIONS";
}

function policy(
  capabilityKey: CapabilityKey,
  scope: CapabilityResourceScope,
  legacyAllowedRoles: readonly AccessRole[],
  legacyPolicy: string,
): CapabilityRoutePolicy {
  return { capabilityKey, scope, legacyAllowedRoles, legacyPolicy };
}

export function resolveCapabilityRoutePolicy(
  methodInput: string,
  pathInput: string,
): CapabilityRoutePolicy {
  const method = methodInput.toUpperCase();
  const path = normalizePath(pathInput).toLowerCase();
  const read = isRead(method);

  if (read && path === "/access/me") {
    return {
      ...policy(
        "crm.client.read.basic",
        "self",
        allRoles,
        "Authenticated actor reads own effective capability snapshot",
      ),
      authenticatedOnly: true,
    };
  }

  if (path.startsWith("/access/")) {
    return policy(
      path.includes("/overrides/")
        ? "access.user.override.manage"
        : "access.user.role.assign",
      "emergency",
      rootBusinessRoles,
      "AccessMutationsService hard hierarchy and emergency policy",
    );
  }

  if (path.startsWith("/crm/configuration")) {
    const capabilityKey = read
      ? "config.crm.read"
      : path.endsWith("/draft") || path.endsWith("/preview")
        ? "config.crm.edit"
        : "config.crm.publish";
    return policy(
      capabilityKey,
      "resource",
      rootBusinessRoles,
      "CrmConfigurationService effective scope and revision policy",
    );
  }

  if (path === "/crm/client-pipelines" && read) {
    return policy(
      "crm.client.read.basic",
      "branch",
      teacherAndStaffRoles,
      "Client pipeline operational effective configuration",
    );
  }

  if (path.startsWith("/crm/client-pipelines")) {
    return policy(
      "system.settings.manage",
      "global",
      rootBusinessRoles,
      "Client pipeline director-only revision configuration",
    );
  }

  if (
    path.includes("/export") ||
    path.endsWith(".xlsx") ||
    path.endsWith(".csv")
  ) {
    return policy(
      "report.export.xlsx",
      "branch",
      managementRoles,
      "Reporting export capability intersected with source report policy",
    );
  }

  if (
    path.includes("/reports/finance") ||
    path.startsWith("/analytics/finance") ||
    path.includes("/expenses")
  ) {
    return policy(
      "commerce.school_finance.read",
      "global",
      rootBusinessRoles,
      "CrmPolicy.assertCanReadSchoolFinance",
    );
  }

  if (
    read &&
    (path === "/crm/me/commerce" ||
      /^\/crm\/students\/[^/]+\/commerce$/.test(path))
  ) {
    return policy(
      "commerce.client_finance.read",
      path === "/crm/me/commerce" ? "self" : "self_or_assigned",
      ["client", ...staffRoles],
      "CommerceProjectionService actor-scoped client finance",
    );
  }

  if (
    read &&
    [
      "/crm/payments",
      "/crm/subscriptions",
      "/crm/student-balances",
      "/crm/expected-payments",
    ].includes(path)
  ) {
    return policy(
      "commerce.school_finance.read",
      "global",
      rootBusinessRoles,
      "CrmPolicy.assertCanReadSchoolFinance",
    );
  }

  if (path.includes("subscription-packages")) {
    return policy(
      read ? "commerce.package.read" : "commerce.package.manage",
      "global",
      read ? staffRoles : rootBusinessRoles,
      read
        ? "CrmPolicy actor-scoped package catalog"
        : "CrmPolicy.assertCanManageSubscriptionPackages",
    );
  }

  if (
    path.includes("/subscriptions") ||
    path.includes("/subscription-payments") ||
    path.includes("/adjustments") ||
    path.includes("/payments") ||
    path.includes("/student-balances") ||
    path.includes("/expected-payments")
  ) {
    return policy(
      read ? "commerce.client_finance.read" : "commerce.subscription.issue",
      "self_or_assigned",
      read ? ["client", ...staffRoles] : staffRoles,
      "CrmPolicy student-finance/resource scope",
    );
  }

  if (path.includes("/shared-tasks")) {
    const sharedTaskClose =
      path.includes("/shared-tasks/") && path.endsWith("/close");
    return policy(
      read || sharedTaskClose ? "workflow.task.read" : "workflow.task.write",
      "resource",
      read || sharedTaskClose ? taskReaders : managementRoles,
      "SharedTaskService dynamic audience scope",
    );
  }

  if (path.includes("/attendance") || path.includes("/lesson-participation")) {
    return policy(
      read ? "schedule.lesson.read.assigned" : "schedule.attendance.write",
      "self_or_assigned",
      read ? allRoles : staffRoles,
      "Schedule/Attendance repository actor scope",
    );
  }

  if (path.includes("/complete") && path.includes("lesson")) {
    return policy(
      "schedule.lesson.complete",
      "resource",
      staffRoles,
      "Schedule lifecycle transition policy",
    );
  }

  if (path.includes("/schedule-reference")) {
    return policy(
      read ? "schedule.lesson.read.assigned" : "config.crm.edit",
      read ? "self_or_assigned" : "resource",
      read ? teacherAndStaffRoles : rootBusinessRoles,
      "AvailabilityService teacher-self read and delegated settings write policy",
    );
  }

  if (
    !read &&
    (path === "/crm/branches" ||
      path.startsWith("/crm/branches/") ||
      path === "/crm/rooms" ||
      path.startsWith("/crm/rooms/"))
  ) {
    return policy(
      "config.crm.edit",
      "branch",
      rootBusinessRoles,
      "Facilities settings write intersected with assigned branch scope",
    );
  }

  if (
    path.includes("/lessons") ||
    path.includes("/schedule") ||
    path.includes("/rooms") ||
    path.includes("/branches") ||
    path.includes("/groups")
  ) {
    return policy(
      read ? "schedule.lesson.read.assigned" : "schedule.lesson.write",
      "self_or_assigned",
      read ? allRoles : staffRoles,
      "ScheduleService/CRM repository actor scope",
    );
  }

  if (path.includes("/homeworks")) {
    return policy(
      "schedule.lesson.read.assigned",
      "self_or_assigned",
      allRoles,
      "HomeworkService lesson ownership/assignment policy",
    );
  }

  if (path.includes("/comments")) {
    return policy(
      read ? "crm.client.read.basic" : "crm.comment.read.shared",
      "self_or_assigned",
      read ? allRoles : teacherAndStaffRoles,
      "TimelineService assigned/self predicate and per-comment share flag",
    );
  }

  if (
    path.includes("/contacts") ||
    path.includes("/families") ||
    path.includes("/representatives")
  ) {
    return policy(
      read ? "crm.client.read.contacts" : "crm.client.write",
      "self_or_assigned",
      read ? ["client", ...staffRoles] : staffRoles,
      "CRM contact/family resource policy",
    );
  }

  if (path.startsWith("/analytics") || path.includes("/reports")) {
    return policy(
      "report.status.read",
      "branch",
      managementRoles,
      "Analytics/Reporting management policy",
    );
  }

  if (path.includes("/settings") && !read) {
    return policy(
      "system.settings.manage",
      "global",
      managementRoles,
      "CrmPolicy.assertCanManageSystemSettings",
    );
  }

  if (path.startsWith("/crm/") && !read) {
    return policy(
      "crm.client.write",
      "resource",
      staffRoles,
      "CrmPolicy.assertCanWriteCrm plus repository target scope",
    );
  }

  return policy(
    "crm.client.read.basic",
    "resource",
    allRoles,
    "Authenticated compatibility facade; domain service enforces resource scope",
  );
}
