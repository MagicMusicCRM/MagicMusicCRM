import {
  BASELINE_CAPABILITY_ROLES,
  resolveCapabilityRoutePolicy,
} from "./capability-route-policy";
import { CAPABILITY_DEFINITIONS } from "./capability-registry";

describe("capability route policy", () => {
  it.each([
    ["PUT", "/access/users/id/role", "access.user.role.assign"],
    ["PUT", "/access/users/id/overrides/key", "access.user.override.manage"],
    ["GET", "/crm/students/id", "crm.client.read.basic"],
    ["PATCH", "/crm/students/id", "crm.client.write"],
    ["GET", "/crm/comments", "crm.client.read.basic"],
    ["POST", "/crm/comments", "crm.comment.read.shared"],
    ["GET", "/crm/tasks", "workflow.task.read"],
    ["PATCH", "/crm/tasks/id", "workflow.task.write"],
    ["GET", "/crm/lessons", "schedule.lesson.read.assigned"],
    ["PATCH", "/crm/lessons/id", "schedule.lesson.write"],
    [
      "GET",
      "/crm/schedule-reference",
      "schedule.lesson.read.assigned",
    ],
    [
      "PUT",
      "/crm/schedule-reference/branches/id/hours",
      "schedule.lesson.write",
    ],
    ["POST", "/crm/lessons/id/attendance", "schedule.attendance.write"],
    ["POST", "/crm/lessons/id/complete", "schedule.lesson.complete"],
    ["GET", "/crm/me/commerce", "commerce.client_finance.read"],
    [
      "GET",
      "/crm/students/id/commerce",
      "commerce.client_finance.read",
    ],
    ["GET", "/crm/payments", "commerce.school_finance.read"],
    ["GET", "/crm/subscriptions", "commerce.school_finance.read"],
    ["GET", "/crm/student-balances", "commerce.school_finance.read"],
    ["GET", "/crm/expected-payments", "commerce.school_finance.read"],
    ["POST", "/crm/subscriptions", "commerce.subscription.issue"],
    [
      "POST",
      "/crm/students/id/subscription-payments",
      "commerce.subscription.issue",
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
    expect(resolveCapabilityRoutePolicy("GET", "/crm/me/commerce")).toMatchObject(
      {
        capabilityKey: "commerce.client_finance.read",
        scope: "self",
      },
    );
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
