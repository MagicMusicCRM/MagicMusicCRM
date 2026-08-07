import {
  AccessRole,
  CAPABILITY_DEFINITIONS,
  CapabilityEffect,
  CapabilityKey,
} from "./capability-registry";
import { EffectiveAccessEvaluator } from "./effective-access-evaluator";
import { HardInvariantPolicy } from "./hard-invariant.policy";

const hardInvariants = new HardInvariantPolicy();
const evaluator = new EffectiveAccessEvaluator(hardInvariants);

const packageAllows: Readonly<Record<CapabilityKey, readonly AccessRole[]>> = {
  "access.user.role.assign": ["director", "system_admin"],
  "access.user.override.manage": ["director", "system_admin"],
  "crm.client.read.basic": [
    "client",
    "teacher",
    "admin",
    "manager",
    "director",
    "system_admin",
  ],
  "crm.client.read.contacts": [
    "client",
    "admin",
    "manager",
    "director",
    "system_admin",
  ],
  "crm.client.write": ["admin", "manager", "director", "system_admin"],
  "crm.comment.read.shared": [
    "teacher",
    "admin",
    "manager",
    "director",
    "system_admin",
  ],
  "schedule.lesson.read.assigned": [
    "client",
    "teacher",
    "admin",
    "manager",
    "director",
    "system_admin",
  ],
  "schedule.lesson.write": ["admin", "manager", "director", "system_admin"],
  "schedule.attendance.write": ["admin", "manager", "director", "system_admin"],
  "schedule.lesson.complete": ["admin", "manager", "director", "system_admin"],
  "commerce.client_finance.read": [
    "client",
    "admin",
    "manager",
    "director",
    "system_admin",
  ],
  "commerce.client_finance.write": [
    "admin",
    "manager",
    "director",
    "system_admin",
  ],
  "commerce.school_finance.read": ["director", "system_admin"],
  "commerce.package.read": ["admin", "manager", "director", "system_admin"],
  "commerce.package.manage": ["director", "system_admin"],
  "commerce.subscription.issue": [
    "admin",
    "manager",
    "director",
    "system_admin",
  ],
  "workflow.task.read": ["teacher", "manager", "director", "system_admin"],
  "workflow.task.write": ["manager", "director", "system_admin"],
  "report.status.read": ["manager", "director", "system_admin"],
  "report.export.xlsx": ["manager", "director", "system_admin"],
  "config.crm.read": ["director", "system_admin"],
  "config.crm.edit": ["director", "system_admin"],
  "config.crm.publish": ["director", "system_admin"],
  "config.commerce.manage": ["director", "system_admin"],
  "system.settings.manage": ["manager", "director", "system_admin"],
};

function evaluate(
  role: AccessRole,
  capabilityKey: CapabilityKey,
  options: {
    roleEffect?: CapabilityEffect;
    overrideEffect?: CapabilityEffect;
    resourceAllowed?: boolean;
  } = {},
) {
  const definition = CAPABILITY_DEFINITIONS.find(
    (candidate) => candidate.key === capabilityKey,
  );
  if (!definition) {
    throw new Error(`Missing capability definition: ${capabilityKey}`);
  }

  return evaluator.evaluate({
    actor: {
      userId: `${role}-1`,
      role,
      active: true,
    },
    capability: {
      key: capabilityKey,
      active: true,
      overrideMode: definition.overrideMode,
    },
    roleEffect:
      options.roleEffect ??
      (packageAllows[capabilityKey].includes(role) ? "allow" : "deny"),
    overrideEffect: options.overrideEffect,
    resourceAllowed: options.resourceAllowed ?? true,
  });
}

describe("EffectiveAccessEvaluator", () => {
  it.each([
    ["client", "crm.client.read.basic", true],
    ["client", "workflow.task.read", false],
    ["teacher", "schedule.lesson.read.assigned", true],
    ["teacher", "schedule.lesson.write", false],
    ["admin", "crm.client.write", true],
    ["admin", "access.user.role.assign", false],
    ["admin", "workflow.task.read", false],
    ["admin", "workflow.task.write", false],
    ["manager", "report.status.read", true],
    ["manager", "commerce.school_finance.read", false],
    ["director", "commerce.school_finance.read", true],
    ["director", "access.user.role.assign", true],
    ["system_admin", "workflow.task.read", true],
    ["system_admin", "system.settings.manage", true],
  ] as const)(
    "evaluates the six-role matrix: %s / %s -> %s",
    (role, capabilityKey, expected) => {
      expect(evaluate(role, capabilityKey).allowed).toBe(expected);
    },
  );

  it.each([
    "crm.client.read.contacts",
    "crm.client.write",
    "schedule.lesson.write",
    "schedule.attendance.write",
    "schedule.lesson.complete",
    "commerce.client_finance.read",
    "commerce.package.read",
    "commerce.subscription.issue",
  ] as const)(
    "keeps Teacher hard deny above an incompatible personal allow for %s",
    (capabilityKey) => {
      expect(
        evaluate("teacher", capabilityKey, {
          roleEffect: "allow",
          overrideEffect: "allow",
        }),
      ).toEqual({
        allowed: false,
        source: "hard-invariant",
        reason: "teacher_hard_deny",
      });
    },
  );

  it("grants system_admin root access despite package and personal deny", () => {
    expect(
      evaluate("system_admin", "workflow.task.read", {
        roleEffect: "deny",
        overrideEffect: "deny",
      }),
    ).toEqual({
      allowed: true,
      source: "root",
      reason: "system_admin_root_allow",
    });
  });

  it("still applies resource validation to system_admin", () => {
    expect(
      evaluate("system_admin", "workflow.task.read", {
        resourceAllowed: false,
      }),
    ).toEqual({
      allowed: false,
      source: "resource-scope",
      reason: "resource_scope_denied",
    });
  });

  it("fails closed for inactive actors, unknown capabilities and registry drift", () => {
    const base = {
      actor: { userId: "root-1", role: "system_admin" as const, active: true },
      capability: {
        key: "workflow.task.read",
        active: true,
        overrideMode: "allow_deny" as const,
      },
      roleEffect: "allow" as const,
      resourceAllowed: true,
    };

    expect(
      evaluator.evaluate({
        ...base,
        actor: { ...base.actor, active: false },
      }).reason,
    ).toBe("inactive_actor");
    expect(
      evaluator.evaluate({
        ...base,
        capability: { ...base.capability, key: "unknown.capability.read" },
      }).reason,
    ).toBe("unknown_capability");
    expect(
      evaluator.evaluate({
        ...base,
        capability: { ...base.capability, active: false },
      }).reason,
    ).toBe("inactive_capability");
    expect(
      evaluator.evaluate({
        ...base,
        capability: { ...base.capability, overrideMode: "locked" },
      }).reason,
    ).toBe("capability_contract_mismatch");
  });

  it("enforces override modes and resource scope after package/override", () => {
    expect(
      evaluate("teacher", "workflow.task.read", {
        overrideEffect: "deny",
      }),
    ).toMatchObject({ allowed: false, source: "override" });
    expect(
      evaluate("client", "workflow.task.read", {
        overrideEffect: "allow",
      }),
    ).toMatchObject({ allowed: true, source: "override" });
    expect(
      evaluate("manager", "config.crm.edit", {
        overrideEffect: "allow",
      }),
    ).toMatchObject({ allowed: true, source: "override" });
    expect(
      evaluate("admin", "config.crm.edit", {
        overrideEffect: "allow",
      }),
    ).toMatchObject({
      allowed: false,
      source: "hard-invariant",
      reason: "config_role_hard_deny",
    });
    expect(
      evaluate("admin", "crm.client.read.contacts", {
        roleEffect: "deny",
        overrideEffect: "allow",
      }),
    ).toMatchObject({
      allowed: false,
      source: "override",
      reason: "capability_override_deny_only",
    });
    expect(
      evaluate("manager", "system.settings.manage", {
        overrideEffect: "deny",
      }),
    ).toMatchObject({
      allowed: false,
      source: "override",
      reason: "capability_override_locked",
    });
    expect(
      evaluate("director", "report.status.read", {
        resourceAllowed: false,
      }),
    ).toMatchObject({ allowed: false, source: "resource-scope" });
  });
});

describe("HardInvariantPolicy access mutations", () => {
  const roleAssignment = {
    actorUserId: "director-1",
    actorRole: "director" as const,
    subjectUserId: "user-1",
    subjectRole: "admin" as const,
    subjectActive: true,
    targetRole: "manager" as const,
    activeSystemAdminCount: 1,
    emergencySurface: false,
  };

  it.each([
    ["admin", false],
    ["manager", false],
    ["director", true],
  ] as const)(
    "allows role mutation only at the Director boundary: %s -> %s",
    (actorRole, expected) => {
      expect(
        hardInvariants.roleAssignmentDecision({
          ...roleAssignment,
          actorRole,
        }).allowed,
      ).toBe(expected);
    },
  );

  it("lets Director assign only lower roles and never mutate self", () => {
    expect(
      hardInvariants.roleAssignmentDecision({
        ...roleAssignment,
        targetRole: "director",
      }).allowed,
    ).toBe(false);
    expect(
      hardInvariants.roleAssignmentDecision({
        ...roleAssignment,
        subjectRole: "director",
        targetRole: "manager",
      }).allowed,
    ).toBe(false);
    expect(
      hardInvariants.roleAssignmentDecision({
        ...roleAssignment,
        subjectUserId: roleAssignment.actorUserId,
      }).allowed,
    ).toBe(false);
  });

  it("requires the emergency surface for system_admin mutations", () => {
    expect(
      hardInvariants.roleAssignmentDecision({
        ...roleAssignment,
        actorRole: "system_admin",
        emergencySurface: false,
      }).reason,
    ).toBe("system_admin_emergency_surface_required");
    expect(
      hardInvariants.roleAssignmentDecision({
        ...roleAssignment,
        actorRole: "system_admin",
        targetRole: "system_admin",
        emergencySurface: true,
      }).allowed,
    ).toBe(true);
  });

  it("protects the last active system_admin from demotion and deactivation", () => {
    const lastRoot = {
      ...roleAssignment,
      actorRole: "system_admin" as const,
      subjectRole: "system_admin" as const,
      targetRole: "director" as const,
      activeSystemAdminCount: 1,
      emergencySurface: true,
    };

    expect(hardInvariants.roleAssignmentDecision(lastRoot).reason).toBe(
      "last_active_system_admin",
    );
    expect(
      hardInvariants.userDeactivationDecision({
        ...lastRoot,
      }).reason,
    ).toBe("last_active_system_admin");
    expect(
      hardInvariants.roleAssignmentDecision({
        ...lastRoot,
        activeSystemAdminCount: 2,
      }).allowed,
    ).toBe(true);
  });

  it("rejects invalid override mutations before persistence", () => {
    const overrideInput = {
      actorUserId: "director-1",
      actorRole: "director" as const,
      subjectUserId: "teacher-1",
      subjectRole: "teacher" as const,
      capabilityKey: "schedule.lesson.write" as const,
      effect: "allow" as const,
      overrideMode: "allow_deny" as const,
      emergencySurface: false,
    };

    expect(hardInvariants.overrideMutationDecision(overrideInput).reason).toBe(
      "hard_deny_cannot_be_overridden",
    );
    expect(
      hardInvariants.overrideMutationDecision({
        ...overrideInput,
        capabilityKey: "commerce.package.read",
      }).reason,
    ).toBe("hard_deny_cannot_be_overridden");
    expect(
      hardInvariants.overrideMutationDecision({
        ...overrideInput,
        capabilityKey: "workflow.task.read",
        overrideMode: "deny_only",
      }).reason,
    ).toBe("capability_override_deny_only");
    expect(
      hardInvariants.overrideMutationDecision({
        ...overrideInput,
        capabilityKey: "workflow.task.read",
        effect: "deny",
        overrideMode: "allow_deny",
      }).allowed,
    ).toBe(true);
    expect(
      hardInvariants.overrideMutationDecision({
        ...overrideInput,
        subjectUserId: "manager-1",
        subjectRole: "manager",
        capabilityKey: "config.crm.edit",
      }).allowed,
    ).toBe(true);
    expect(
      hardInvariants.overrideMutationDecision({
        ...overrideInput,
        subjectUserId: "admin-1",
        subjectRole: "admin",
        capabilityKey: "config.crm.edit",
      }).reason,
    ).toBe("hard_deny_cannot_be_overridden");
  });
});
