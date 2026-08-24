import { resolveCapabilityHardInvariant } from "./capability-registry";

describe("resolveCapabilityHardInvariant", () => {
  it.each([
    ["teacher", "schedule.lesson.write", "teacher_hard_deny"],
    ["admin", "config.crm.edit", "config_role_hard_deny"],
    ["admin", "workflow.task.write", "admin_persona_hard_deny"],
    ["manager", "commerce.school_finance.read", "director_or_system_admin_required"],
  ] as const)("denies %s / %s", (role, capabilityKey, reason) => {
    expect(resolveCapabilityHardInvariant(role, capabilityKey)).toEqual({
      allowed: false,
      reason,
    });
  });

  it("does not hard-deny a valid package decision or system_admin", () => {
    expect(resolveCapabilityHardInvariant("manager", "report.status.read")).toBeNull();
    expect(resolveCapabilityHardInvariant("system_admin", "config.crm.edit")).toBeNull();
  });
});
