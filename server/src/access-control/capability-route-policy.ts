import { AccessRole, CapabilityKey, USER_ROLES } from "./capability-registry";

export type CapabilityResourceScope =
  | "self"
  | "self_or_assigned"
  | "branch"
  | "resource"
  | "global"
  | "emergency";

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
  "admin",
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
  "commerce.teacher_payroll.read": staffRoles,
  "commerce.teacher_payroll.write": staffRoles,
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

const globalSchoolFinancePaths = [
  "/crm/payments",
  "/crm/subscriptions",
  "/crm/student-balances",
  "/crm/expected-payments",
] as const;
const clientFinanceFragments = [
  "/subscriptions",
  "/subscription-payments",
  "/payment-records",
  "/adjustments",
  "/payments",
  "/student-balances",
  "/expected-payments",
] as const;
const scheduleFragments = [
  "/lessons",
  "/schedule",
  "/rooms",
  "/branches",
  "/groups",
] as const;
const contactFragments = [
  "/contacts",
  "/families",
  "/representatives",
] as const;
const facilityRoots = ["/crm/branches", "/crm/rooms"] as const;

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

interface RoutePolicyContext {
  path: string;
  read: boolean;
}

function hasPathFragment(path: string, fragments: readonly string[]): boolean {
  return fragments.some((fragment) => path.includes(fragment));
}

function hasExactPath(path: string, paths: readonly string[]): boolean {
  return paths.includes(path);
}

function isPathAtOrBelow(path: string, root: string): boolean {
  return path === root || path.startsWith(`${root}/`);
}

function isOrganizationHistoryPath(path: string): boolean {
  return facilityRoots.some(
    (root) => path.startsWith(`${root}/`) && path.endsWith("/history"),
  );
}

function isReferenceCatalogPath(path: string): boolean {
  return /^\/crm\/(?:disciplines|loss-reasons|branch-disciplines)(?:\/|$)/.test(
    path,
  );
}

function isConfigurationDraftOrPreview(path: string): boolean {
  return path.endsWith("/draft") || path.endsWith("/preview");
}

function isTeacherPayrollReadPath(path: string): boolean {
  return (
    /^\/crm\/teachers\/[^/]+\/payroll$/.test(path) ||
    path === "/crm/reports/teacher-stats"
  );
}

function isTeacherPayrollWritePath(path: string): boolean {
  return (
    /^\/crm\/teachers\/[^/]+\/(?:payouts|rates)$/.test(path) ||
    path === "/crm/reports/teacher-stats/export"
  );
}

function isExportPath(path: string): boolean {
  return (
    path.includes("/export") || path.endsWith(".xlsx") || path.endsWith(".csv")
  );
}

function isSchoolFinanceReportPath(path: string): boolean {
  return (
    path.includes("/reports/finance") ||
    path.startsWith("/analytics/finance") ||
    path.includes("/expenses")
  );
}

function isClientCommercePath(path: string): boolean {
  return (
    path === "/crm/me/commerce" ||
    /^\/crm\/students\/[^/]+\/commerce$/.test(path)
  );
}

function isLegacySubscriptionIssue(path: string, read: boolean): boolean {
  if (read) return false;
  return (
    path === "/crm/subscriptions" ||
    /^\/crm\/(?:students|leads)\/[^/]+\/subscriptions\/issue$/.test(path)
  );
}

function isSharedTaskClose(path: string): boolean {
  return path.includes("/shared-tasks/") && path.endsWith("/close");
}

function isAttendancePath(path: string): boolean {
  return path.includes("/attendance") || path.includes("/lesson-participation");
}

function isFacilityPath(path: string): boolean {
  return facilityRoots.some((root) => isPathAtOrBelow(path, root));
}

function isAnalyticsOrReportPath(path: string): boolean {
  return path.startsWith("/analytics") || path.includes("/reports");
}

function clientAndStaffRoles(): readonly AccessRole[] {
  return ["client", ...staffRoles];
}

function schoolFinancePolicy(): CapabilityRoutePolicy {
  return policy(
    "commerce.school_finance.read",
    "global",
    rootBusinessRoles,
    "CrmPolicy.assertCanReadSchoolFinance",
  );
}

function resolveAccessMePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!read || path !== "/access/me") return null;
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

function resolveAccessMutationPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!path.startsWith("/access/")) return null;
  if (path.includes("/overrides/"))
    return policy(
      "access.user.override.manage",
      "emergency",
      rootBusinessRoles,
      "AccessMutationsService hard hierarchy and emergency policy",
    );
  return policy(
    "access.user.role.assign",
    "emergency",
    rootBusinessRoles,
    "AccessMutationsService hard hierarchy and emergency policy",
  );
}

function resolvePersonLifecyclePolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (
    !/^\/crm\/(?:teachers|staff)\/[^/]+\/(?:access|offboard|restore|lifecycle-preview|lifecycle-history)$/.test(
      path,
    )
  )
    return null;
  return policy(
    "system.settings.manage",
    "global",
    rootBusinessRoles,
    "PersonAccountService/PersonLifecycleService director-only settings boundary",
  );
}

function resolveLessonDecisionPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!read || path !== "/crm/configuration/lesson-decisions") return null;
  return policy(
    "schedule.lesson.write",
    "branch",
    staffRoles,
    "Read-only effective lesson decision catalog for schedule mutations",
  );
}

function resolveSettlementHistoryPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!read || !/^\/crm\/lessons\/[^/]+\/settlement-history$/.test(path))
    return null;
  return policy(
    "schedule.lesson.write",
    "self_or_assigned",
    staffRoles,
    "Staff-only lesson settlement reasons and correction history",
  );
}

function resolveConfigurationPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!path.startsWith("/crm/configuration")) return null;
  if (read)
    return policy(
      "config.crm.read",
      "resource",
      rootBusinessRoles,
      "CrmConfigurationService effective scope and revision policy",
    );
  if (isConfigurationDraftOrPreview(path))
    return policy(
      "config.crm.edit",
      "resource",
      rootBusinessRoles,
      "CrmConfigurationService effective scope and revision policy",
    );
  return policy(
    "config.crm.publish",
    "resource",
    rootBusinessRoles,
    "CrmConfigurationService effective scope and revision policy",
  );
}

function resolveClientPipelinePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (path === "/crm/client-pipelines" && read)
    return policy(
      "crm.client.read.basic",
      "branch",
      teacherAndStaffRoles,
      "Client pipeline operational effective configuration",
    );
  if (!path.startsWith("/crm/client-pipelines")) return null;
  return policy(
    "system.settings.manage",
    "global",
    rootBusinessRoles,
    "Client pipeline director-only revision configuration",
  );
}

function resolveReferenceCatalogPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!isReferenceCatalogPath(path)) return null;
  if (read && !path.endsWith("/history")) return null;
  return policy(
    "config.crm.edit",
    "global",
    rootBusinessRoles,
    "ReferenceCatalogLifecycleService director-only versioned catalog mutations",
  );
}

function resolveAccessPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveAccessMePolicy(context) ??
    resolveAccessMutationPolicy(context) ??
    resolvePersonLifecyclePolicy(context)
  );
}

function resolveConfigurationPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveLessonDecisionPolicy(context) ??
    resolveSettlementHistoryPolicy(context) ??
    resolveConfigurationPolicy(context) ??
    resolveClientPipelinePolicy(context) ??
    resolveReferenceCatalogPolicy(context)
  );
}

function resolveAccessAndConfigurationPolicy(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveAccessPolicyStage(context) ??
    resolveConfigurationPolicyStage(context)
  );
}

function resolveTeacherPayrollReadPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!isTeacherPayrollReadPath(path)) return null;
  return policy(
    "commerce.teacher_payroll.read",
    "resource",
    staffRoles,
    "CrmPolicy.assertCanReadPayroll with teacher resource scope",
  );
}

function resolveTeacherPayrollHistoryPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!/^\/crm\/teachers\/[^/]+\/(?:payouts|rates)\/[^/]+$/.test(path))
    return null;
  return policy(
    "commerce.teacher_payroll.write",
    "resource",
    rootBusinessRoles,
    "CrmPolicy.assertCanManagePayrollHistory director-only correction/void",
  );
}

function resolveTeacherPayrollWritePolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!isTeacherPayrollWritePath(path)) return null;
  if (path.endsWith("/export"))
    return policy(
      "commerce.teacher_payroll.read",
      "resource",
      staffRoles,
      "Teacher payroll capability with versioned create/correct/void integrity",
    );
  return policy(
    "commerce.teacher_payroll.write",
    "resource",
    staffRoles,
    "Teacher payroll capability with versioned create/correct/void integrity",
  );
}

function resolveGenericExportPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!isExportPath(path)) return null;
  return policy(
    "report.export.xlsx",
    "branch",
    managementRoles,
    "Reporting export capability intersected with source report policy",
  );
}

function resolveSchoolFinanceReportPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  return isSchoolFinanceReportPath(path) ? schoolFinancePolicy() : null;
}

function resolvePayrollPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveTeacherPayrollReadPolicy(context) ??
    resolveTeacherPayrollHistoryPolicy(context) ??
    resolveTeacherPayrollWritePolicy(context)
  );
}

function resolveReportingPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveGenericExportPolicy(context) ??
    resolveSchoolFinanceReportPolicy(context)
  );
}

function resolvePayrollAndReportingPolicy(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolvePayrollPolicyStage(context) ??
    resolveReportingPolicyStage(context)
  );
}

function resolveClientCommercePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!read || !isClientCommercePath(path)) return null;
  if (path === "/crm/me/commerce")
    return policy(
      "commerce.client_finance.read",
      "self",
      clientAndStaffRoles(),
      "CommerceProjectionService actor-scoped client finance",
    );
  return policy(
    "commerce.client_finance.read",
    "self_or_assigned",
    clientAndStaffRoles(),
    "CommerceProjectionService actor-scoped client finance",
  );
}

function resolveClientInternalContextPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (
    !/^\/crm\/clients\/[^/]+\/[^/]+\/(?:internal-note|operational-history)$/.test(
      path,
    )
  )
    return null;
  return policy(
    "crm.client.write",
    "resource",
    staffRoles,
    "ClientInternalContextService staff-only ClientRef scope",
  );
}

function resolveGlobalSchoolFinancePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  return read && hasExactPath(path, globalSchoolFinancePaths)
    ? schoolFinancePolicy()
    : null;
}

function resolveSubscriptionPackagePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!path.includes("subscription-packages")) return null;
  if (read)
    return policy(
      "commerce.package.read",
      "global",
      staffRoles,
      "CrmPolicy actor-scoped package catalog",
    );
  return policy(
    "commerce.package.manage",
    "global",
    rootBusinessRoles,
    "CrmPolicy.assertCanManageSubscriptionPackages",
  );
}

function resolveLegacySubscriptionIssuePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!isLegacySubscriptionIssue(path, read)) return null;
  return policy(
    "commerce.subscription.issue",
    "self_or_assigned",
    staffRoles,
    "Legacy subscription issue adapter with client resource scope",
  );
}

function resolveClientFinanceResourcePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!hasPathFragment(path, clientFinanceFragments)) return null;
  if (read)
    return policy(
      "commerce.client_finance.read",
      "self_or_assigned",
      clientAndStaffRoles(),
      "CrmPolicy student-finance/resource scope",
    );
  return policy(
    "commerce.client_finance.write",
    "self_or_assigned",
    staffRoles,
    "CrmPolicy student-finance/resource scope",
  );
}

function resolveSharedTaskPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!path.includes("/shared-tasks")) return null;
  if (read || isSharedTaskClose(path))
    return policy(
      "workflow.task.read",
      "resource",
      taskReaders,
      "SharedTaskService dynamic audience scope",
    );
  return policy(
    "workflow.task.write",
    "resource",
    managementRoles,
    "SharedTaskService dynamic audience scope",
  );
}

function resolveCommerceContextPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveClientCommercePolicy(context) ??
    resolveClientInternalContextPolicy(context) ??
    resolveGlobalSchoolFinancePolicy(context) ??
    resolveSubscriptionPackagePolicy(context)
  );
}

function resolveSubscriptionAndTaskPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveLegacySubscriptionIssuePolicy(context) ??
    resolveClientFinanceResourcePolicy(context) ??
    resolveSharedTaskPolicy(context)
  );
}

function resolveClientCommerceAndTasksPolicy(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveCommerceContextPolicyStage(context) ??
    resolveSubscriptionAndTaskPolicyStage(context)
  );
}

function resolveAttendancePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!isAttendancePath(path)) return null;
  if (read)
    return policy(
      "schedule.lesson.read.assigned",
      "self_or_assigned",
      allRoles,
      "Schedule/Attendance repository actor scope",
    );
  return policy(
    "schedule.attendance.write",
    "self_or_assigned",
    staffRoles,
    "Schedule/Attendance repository actor scope",
  );
}

function resolveLessonCompletionPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!path.includes("/complete") || !path.includes("lesson")) return null;
  return policy(
    "schedule.lesson.complete",
    "resource",
    staffRoles,
    "Schedule lifecycle transition policy",
  );
}

function resolveScheduleReferencePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!path.includes("/schedule-reference")) return null;
  if (read)
    return policy(
      "schedule.lesson.read.assigned",
      "self_or_assigned",
      teacherAndStaffRoles,
      "AvailabilityService teacher-self read and delegated settings write policy",
    );
  return policy(
    "config.crm.edit",
    "resource",
    rootBusinessRoles,
    "AvailabilityService teacher-self read and delegated settings write policy",
  );
}

function resolveOrganizationHistoryPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!read || !isOrganizationHistoryPath(path)) return null;
  return policy(
    "config.crm.edit",
    "branch",
    rootBusinessRoles,
    "Organization lifecycle director-only immutable history",
  );
}

function resolveFacilityWritePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (read || !isFacilityPath(path)) return null;
  return policy(
    "config.crm.edit",
    "branch",
    rootBusinessRoles,
    "Facilities settings write intersected with assigned branch scope",
  );
}

function resolveScheduleResourcePolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!hasPathFragment(path, scheduleFragments)) return null;
  if (read)
    return policy(
      "schedule.lesson.read.assigned",
      "self_or_assigned",
      allRoles,
      "Schedule owners/CRM repository actor scope",
    );
  return policy(
    "schedule.lesson.write",
    "self_or_assigned",
    staffRoles,
    "Schedule owners/CRM repository actor scope",
  );
}

function resolveHomeworkPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  return path.includes("/homeworks")
    ? policy(
        "schedule.lesson.read.assigned",
        "self_or_assigned",
        allRoles,
        "HomeworkService lesson ownership/assignment policy",
      )
    : null;
}

function resolveLessonSchedulePolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveAttendancePolicy(context) ??
    resolveLessonCompletionPolicy(context) ??
    resolveScheduleReferencePolicy(context)
  );
}

function resolveFacilitiesPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveOrganizationHistoryPolicy(context) ??
    resolveFacilityWritePolicy(context) ??
    resolveScheduleResourcePolicy(context) ??
    resolveHomeworkPolicy(context)
  );
}

function resolveScheduleAndFacilitiesPolicy(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveLessonSchedulePolicyStage(context) ??
    resolveFacilitiesPolicyStage(context)
  );
}

function resolveCommentPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!path.includes("/comments")) return null;
  if (read)
    return policy(
      "crm.client.read.basic",
      "self_or_assigned",
      allRoles,
      "TimelineService assigned/self predicate and per-comment share flag",
    );
  return policy(
    "crm.comment.read.shared",
    "self_or_assigned",
    teacherAndStaffRoles,
    "TimelineService assigned/self predicate and per-comment share flag",
  );
}

function resolveContactPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (!hasPathFragment(path, contactFragments)) return null;
  if (read)
    return policy(
      "crm.client.read.contacts",
      "self_or_assigned",
      clientAndStaffRoles(),
      "CRM contact/family resource policy",
    );
  return policy(
    "crm.client.write",
    "self_or_assigned",
    staffRoles,
    "CRM contact/family resource policy",
  );
}

function resolveAnalyticsReportingPolicy({
  path,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  return isAnalyticsOrReportPath(path)
    ? policy(
        "report.status.read",
        "branch",
        managementRoles,
        "Analytics/Reporting management policy",
      )
    : null;
}

function resolveSettingsPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (read || !path.includes("/settings")) return null;
  return policy(
    "system.settings.manage",
    "global",
    managementRoles,
    "CrmPolicy.assertCanManageSystemSettings",
  );
}

function resolveCrmMutationPolicy({
  path,
  read,
}: RoutePolicyContext): CapabilityRoutePolicy | null {
  if (read || !path.startsWith("/crm/")) return null;
  return policy(
    "crm.client.write",
    "resource",
    staffRoles,
    "CrmPolicy.assertCanWriteCrm plus repository target scope",
  );
}

function resolveDefaultPolicy(): CapabilityRoutePolicy {
  return policy(
    "crm.client.read.basic",
    "resource",
    allRoles,
    "Authenticated compatibility facade; domain service enforces resource scope",
  );
}

function resolveTimelineContactsAndReportingPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy | null {
  return (
    resolveCommentPolicy(context) ??
    resolveContactPolicy(context) ??
    resolveAnalyticsReportingPolicy(context)
  );
}

function resolveSettingsMutationAndDefaultPolicyStage(
  context: RoutePolicyContext,
): CapabilityRoutePolicy {
  return (
    resolveSettingsPolicy(context) ??
    resolveCrmMutationPolicy(context) ??
    resolveDefaultPolicy()
  );
}

function resolveGenericCrmAndDefaultPolicy(
  context: RoutePolicyContext,
): CapabilityRoutePolicy {
  return (
    resolveTimelineContactsAndReportingPolicyStage(context) ??
    resolveSettingsMutationAndDefaultPolicyStage(context)
  );
}

export function resolveCapabilityRoutePolicy(
  methodInput: string,
  pathInput: string,
): CapabilityRoutePolicy {
  const context = {
    path: normalizePath(pathInput).toLowerCase(),
    read: isRead(methodInput.toUpperCase()),
  };
  return (
    resolveAccessAndConfigurationPolicy(context) ??
    resolvePayrollAndReportingPolicy(context) ??
    resolveClientCommerceAndTasksPolicy(context) ??
    resolveScheduleAndFacilitiesPolicy(context) ??
    resolveGenericCrmAndDefaultPolicy(context)
  );
}
