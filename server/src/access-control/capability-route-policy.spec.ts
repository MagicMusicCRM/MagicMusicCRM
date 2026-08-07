import {
  BASELINE_CAPABILITY_ROLES,
  resolveCapabilityRoutePolicy,
} from "./capability-route-policy";
import { CAPABILITY_DEFINITIONS } from "./capability-registry";

describe("capability route policy", () => {
  it.each([
    ["GET", "/access/me", "crm.client.read.basic"],
    ["PUT", "/access/users/id/role", "access.user.role.assign"],
    ["PUT", "/access/users/id/overrides/key", "access.user.override.manage"],
    ["GET", "/crm/students/id", "crm.client.read.basic"],
    ["PATCH", "/crm/students/id", "crm.client.write"],
    ["GET", "/crm/clients/student/id/internal-note", "crm.client.write"],
    ["PUT", "/crm/clients/lead/id/internal-note", "crm.client.write"],
    [
      "GET",
      "/crm/clients/student/id/operational-history",
      "crm.client.write",
    ],
    ["GET", "/crm/client-pipelines", "crm.client.read.basic"],
    ["GET", "/crm/client-pipelines/revisions", "system.settings.manage"],
    ["POST", "/crm/client-pipelines/preview", "system.settings.manage"],
    ["POST", "/crm/client-pipelines/publish", "system.settings.manage"],
    ["GET", "/crm/comments", "crm.client.read.basic"],
    ["POST", "/crm/comments", "crm.comment.read.shared"],
    ["GET", "/crm/lessons", "schedule.lesson.read.assigned"],
    ["GET", "/crm/schedule-plans", "schedule.lesson.read.assigned"],
    ["POST", "/crm/schedule-plans", "schedule.lesson.write"],
    ["GET", "/crm/schedule-plans/id/tray", "schedule.lesson.read.assigned"],
    ["POST", "/crm/schedule-plans/id/end/preview", "schedule.lesson.write"],
    ["POST", "/crm/schedule-plans/id/end", "schedule.lesson.write"],
    ["PATCH", "/crm/schedule-plans/id", "schedule.lesson.write"],
    [
      "GET",
      "/crm/configuration/lesson-decisions",
      "schedule.lesson.write",
    ],
    [
      "POST",
      "/crm/lessons/constraints/preview",
      "schedule.lesson.write",
    ],
    ["PATCH", "/crm/lessons/id", "schedule.lesson.write"],
    ["GET", "/crm/schedule-reference", "schedule.lesson.read.assigned"],
    ["PUT", "/crm/schedule-reference/branches/id/hours", "config.crm.edit"],
    ["POST", "/crm/branches", "config.crm.edit"],
    ["PATCH", "/crm/branches/id", "config.crm.edit"],
    ["POST", "/crm/rooms", "config.crm.edit"],
    ["DELETE", "/crm/rooms/id", "config.crm.edit"],
    ["POST", "/crm/lessons/id/attendance", "schedule.attendance.write"],
    ["POST", "/crm/lessons/id/complete", "schedule.lesson.complete"],
    ["GET", "/crm/me/commerce", "commerce.client_finance.read"],
    ["GET", "/crm/students/id/commerce", "commerce.client_finance.read"],
    ["GET", "/crm/payments", "commerce.school_finance.read"],
    ["GET", "/crm/subscriptions", "commerce.school_finance.read"],
    ["GET", "/crm/student-balances", "commerce.school_finance.read"],
    ["GET", "/crm/expected-payments", "commerce.school_finance.read"],
    ["POST", "/crm/subscriptions", "commerce.subscription.issue"],
    [
      "POST",
      "/crm/students/id/subscription-payments",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/subscriptions/purchase/preview",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/subscriptions/id/replace",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/subscriptions/id/cancel",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/subscriptions/issue",
      "commerce.subscription.issue",
    ],
    [
      "POST",
      "/crm/leads/id/subscriptions/issue",
      "commerce.subscription.issue",
    ],
    [
      "POST",
      "/crm/students/id/payment-records",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/payment-records/id/transition",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/payment-records/id/reversal/preview",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/payment-records/id/reversal",
      "commerce.client_finance.write",
    ],
    [
      "POST",
      "/crm/students/id/adjustments",
      "commerce.client_finance.write",
    ],
    ["GET", "/crm/subscription-packages", "commerce.package.read"],
    ["POST", "/crm/subscription-packages", "commerce.package.manage"],
    ["PATCH", "/crm/subscription-packages/id", "commerce.package.manage"],
    ["DELETE", "/crm/subscription-packages/id", "commerce.package.manage"],
    [
      "POST",
      "/crm/subscription-packages/id/restore",
      "commerce.package.manage",
    ],
    ["GET", "/crm/reports/finance", "commerce.school_finance.read"],
    ["GET", "/analytics/status", "report.status.read"],
    ["GET", "/analytics/export", "report.export.xlsx"],
    ["PATCH", "/settings/admin-chat-avatar", "system.settings.manage"],
  ])("maps %s %s to %s", (method, path, expected) => {
    expect(resolveCapabilityRoutePolicy(method, path)).toMatchObject({
      capabilityKey: expected,
    });
  });

  it("separates client commerce resources from global school finance", () => {
    expect(
      resolveCapabilityRoutePolicy("GET", "/crm/me/commerce"),
    ).toMatchObject({
      capabilityKey: "commerce.client_finance.read",
      scope: "self",
    });
    expect(
      resolveCapabilityRoutePolicy(
        "GET",
        "/crm/students/00000000-0000-0000-0000-000000000001/commerce",
      ),
    ).toMatchObject({
      capabilityKey: "commerce.client_finance.read",
      scope: "self_or_assigned",
    });
    expect(
      resolveCapabilityRoutePolicy("GET", "/crm/student-balances"),
    ).toMatchObject({
      capabilityKey: "commerce.school_finance.read",
      scope: "global",
      legacyAllowedRoles: ["director", "system_admin"],
    });
  });

  it("keeps shared tasks outside the Administrator persona", () => {
    expect(
      resolveCapabilityRoutePolicy("GET", "/crm/shared-tasks"),
    ).toMatchObject({
      capabilityKey: "workflow.task.read",
      legacyAllowedRoles: ["teacher", "manager", "director", "system_admin"],
    });
    expect(
      resolveCapabilityRoutePolicy("POST", "/crm/shared-tasks"),
    ).toMatchObject({
      capabilityKey: "workflow.task.write",
      legacyAllowedRoles: ["manager", "director", "system_admin"],
    });
  });

  it("keeps every route mapping inside the versioned registry with a scope", () => {
    const registered = new Set<string>(
      CAPABILITY_DEFINITIONS.map((definition) => definition.key),
    );
    for (const [capabilityKey, roles] of Object.entries(
      BASELINE_CAPABILITY_ROLES,
    )) {
      expect(registered.has(capabilityKey)).toBe(true);
      expect(roles.length).toBeGreaterThan(0);
    }
    expect(Object.keys(BASELINE_CAPABILITY_ROLES)).toHaveLength(
      CAPABILITY_DEFINITIONS.length,
    );
  });
});
