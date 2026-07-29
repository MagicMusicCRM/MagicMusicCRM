import { Injectable } from "@nestjs/common";
import {
  AccessRole,
  CAPABILITY_DEFINITIONS,
  CapabilityEffect,
  CapabilityOverrideMode,
  isCapabilityKey,
} from "./capability-registry";
import { HardInvariantPolicy } from "./hard-invariant.policy";

export type AccessDecisionSource =
  | "actor"
  | "capability-registry"
  | "root"
  | "hard-invariant"
  | "role-package"
  | "override"
  | "resource-scope";

export interface EffectiveAccessDecision {
  allowed: boolean;
  source: AccessDecisionSource;
  reason: string;
}

export interface EffectiveAccessInput {
  actor: {
    userId: string;
    role: AccessRole;
    active: boolean;
  };
  capability: {
    key: string;
    active: boolean;
    overrideMode: CapabilityOverrideMode;
  };
  roleEffect?: CapabilityEffect | null;
  overrideEffect?: CapabilityEffect | null;
  resourceAllowed: boolean;
}

const capabilityDefinitionsByKey = new Map(
  CAPABILITY_DEFINITIONS.map((definition) => [definition.key, definition]),
);

function decision(
  allowed: boolean,
  source: AccessDecisionSource,
  reason: string,
): EffectiveAccessDecision {
  return { allowed, source, reason };
}

@Injectable()
export class EffectiveAccessEvaluator {
  constructor(private readonly hardInvariants: HardInvariantPolicy) {}

  evaluate(input: EffectiveAccessInput): EffectiveAccessDecision {
    if (!input.actor.active) {
      return decision(false, "actor", "inactive_actor");
    }
    if (!isCapabilityKey(input.capability.key)) {
      return decision(false, "capability-registry", "unknown_capability");
    }

    const definition = capabilityDefinitionsByKey.get(input.capability.key);
    if (
      !definition ||
      !input.capability.active ||
      definition.overrideMode !== input.capability.overrideMode
    ) {
      return decision(
        false,
        "capability-registry",
        !input.capability.active
          ? "inactive_capability"
          : "capability_contract_mismatch",
      );
    }

    if (input.actor.role === "system_admin") {
      if (!input.resourceAllowed) {
        return decision(false, "resource-scope", "resource_scope_denied");
      }
      return decision(true, "root", "system_admin_root_allow");
    }

    const invariant = this.hardInvariants.capabilityDecision(
      input.actor.role,
      input.capability.key,
    );
    if (invariant?.allowed === false) {
      return decision(false, "hard-invariant", invariant.reason);
    }

    let allowed = input.roleEffect === "allow";
    let source: AccessDecisionSource = "role-package";
    let reason =
      input.roleEffect === "allow"
        ? "role_package_allow"
        : "role_package_deny";

    if (input.overrideEffect) {
      if (definition.overrideMode === "locked") {
        return decision(false, "override", "capability_override_locked");
      }
      if (
        definition.overrideMode === "deny_only" &&
        input.overrideEffect === "allow"
      ) {
        return decision(false, "override", "capability_override_deny_only");
      }
      allowed = input.overrideEffect === "allow";
      source = "override";
      reason =
        input.overrideEffect === "allow" ? "personal_allow" : "personal_deny";
    }

    if (!allowed) {
      return decision(false, source, reason);
    }
    if (!input.resourceAllowed) {
      return decision(false, "resource-scope", "resource_scope_denied");
    }

    return decision(true, source, reason);
  }
}
