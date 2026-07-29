import { Injectable } from "@nestjs/common";
import {
  AccessRole,
  CapabilityEffect,
  CapabilityKey,
  CapabilityOverrideMode,
} from "./capability-registry";

export interface InvariantDecision {
  allowed: boolean;
  reason: string;
}

export interface RoleAssignmentInvariantInput {
  actorUserId: string;
  actorRole: AccessRole;
  subjectUserId: string;
  subjectRole: AccessRole;
  subjectActive: boolean;
  targetRole: AccessRole;
  activeSystemAdminCount: number;
  emergencySurface: boolean;
}

export interface UserDeactivationInvariantInput {
  actorUserId: string;
  actorRole: AccessRole;
  subjectUserId: string;
  subjectRole: AccessRole;
  subjectActive: boolean;
  activeSystemAdminCount: number;
  emergencySurface: boolean;
}

export interface OverrideMutationInvariantInput {
  actorUserId: string;
  actorRole: AccessRole;
  subjectUserId: string;
  subjectRole: AccessRole;
  capabilityKey: CapabilityKey;
  effect: CapabilityEffect;
  overrideMode: CapabilityOverrideMode;
  emergencySurface: boolean;
}

export interface PackageMutationInvariantInput {
  actorRole: AccessRole;
  targetRole: AccessRole;
  emergencySurface: boolean;
}

const ROLE_LEVEL: Readonly<Record<Exclude<AccessRole, "system_admin">, number>> = {
  client: 0,
  teacher: 1,
  admin: 2,
  manager: 3,
  director: 4,
};

const TEACHER_HARD_DENIES = new Set<CapabilityKey>([
  "crm.client.read.contacts",
  "crm.client.write",
  "schedule.lesson.write",
  "schedule.attendance.write",
  "schedule.lesson.complete",
  "commerce.client_finance.read",
  "commerce.package.read",
  "commerce.subscription.issue",
]);

const DIRECTOR_ONLY_CAPABILITIES = new Set<CapabilityKey>([
  "access.user.role.assign",
  "access.user.override.manage",
  "commerce.school_finance.read",
  "commerce.package.manage",
]);

function allow(reason: string): InvariantDecision {
  return { allowed: true, reason };
}

function deny(reason: string): InvariantDecision {
  return { allowed: false, reason };
}

@Injectable()
export class HardInvariantPolicy {
  capabilityDecision(
    role: AccessRole,
    capabilityKey: CapabilityKey,
  ): InvariantDecision | null {
    if (role === "system_admin") {
      return null;
    }

    if (role === "teacher" && TEACHER_HARD_DENIES.has(capabilityKey)) {
      return deny("teacher_hard_deny");
    }

    if (
      DIRECTOR_ONLY_CAPABILITIES.has(capabilityKey) &&
      role !== "director"
    ) {
      return deny("director_or_system_admin_required");
    }

    return null;
  }

  roleAssignmentDecision(
    input: RoleAssignmentInvariantInput,
  ): InvariantDecision {
    if (input.actorRole === "system_admin") {
      if (!input.emergencySurface) {
        return deny("system_admin_emergency_surface_required");
      }
      if (
        input.subjectActive &&
        input.subjectRole === "system_admin" &&
        input.targetRole !== "system_admin" &&
        input.activeSystemAdminCount <= 1
      ) {
        return deny("last_active_system_admin");
      }
      return allow("system_admin_emergency_role_assignment");
    }

    if (input.actorRole !== "director") {
      return deny("director_or_system_admin_required");
    }
    if (input.actorUserId === input.subjectUserId) {
      return deny("director_self_role_mutation");
    }
    if (
      input.subjectRole === "system_admin" ||
      ROLE_LEVEL[input.subjectRole] >= ROLE_LEVEL.director
    ) {
      return deny("director_subject_must_be_lower");
    }
    if (
      input.targetRole === "system_admin" ||
      ROLE_LEVEL[input.targetRole] >= ROLE_LEVEL.director
    ) {
      return deny("director_target_role_must_be_lower");
    }

    return allow("director_lower_role_assignment");
  }

  userDeactivationDecision(
    input: UserDeactivationInvariantInput,
  ): InvariantDecision {
    if (input.actorRole === "system_admin") {
      if (!input.emergencySurface) {
        return deny("system_admin_emergency_surface_required");
      }
      if (
        input.subjectActive &&
        input.subjectRole === "system_admin" &&
        input.activeSystemAdminCount <= 1
      ) {
        return deny("last_active_system_admin");
      }
      return allow("system_admin_emergency_deactivation");
    }

    if (input.actorRole !== "director") {
      return deny("director_or_system_admin_required");
    }
    if (input.actorUserId === input.subjectUserId) {
      return deny("director_self_deactivation");
    }
    if (
      input.subjectRole === "system_admin" ||
      ROLE_LEVEL[input.subjectRole] >= ROLE_LEVEL.director
    ) {
      return deny("director_subject_must_be_lower");
    }

    return allow("director_lower_role_deactivation");
  }

  overrideMutationDecision(
    input: OverrideMutationInvariantInput,
  ): InvariantDecision {
    if (input.actorRole === "system_admin") {
      if (!input.emergencySurface) {
        return deny("system_admin_emergency_surface_required");
      }
    } else {
      if (input.actorRole !== "director") {
        return deny("director_or_system_admin_required");
      }
      if (input.actorUserId === input.subjectUserId) {
        return deny("director_self_override_mutation");
      }
      if (
        input.subjectRole === "system_admin" ||
        ROLE_LEVEL[input.subjectRole] >= ROLE_LEVEL.director
      ) {
        return deny("director_subject_must_be_lower");
      }
    }

    if (input.overrideMode === "locked") {
      return deny("capability_override_locked");
    }
    if (input.overrideMode === "deny_only" && input.effect === "allow") {
      return deny("capability_override_deny_only");
    }
    if (
      input.effect === "allow" &&
      this.capabilityDecision(input.subjectRole, input.capabilityKey)?.allowed ===
        false
    ) {
      return deny("hard_deny_cannot_be_overridden");
    }

    return allow("override_mutation_allowed");
  }

  packageMutationDecision(
    input: PackageMutationInvariantInput,
  ): InvariantDecision {
    if (input.actorRole === "system_admin") {
      return input.emergencySurface
        ? allow("system_admin_emergency_package_mutation")
        : deny("system_admin_emergency_surface_required");
    }
    if (input.actorRole !== "director") {
      return deny("director_or_system_admin_required");
    }
    if (
      input.targetRole === "system_admin" ||
      ROLE_LEVEL[input.targetRole] >= ROLE_LEVEL.director
    ) {
      return deny("director_target_role_must_be_lower");
    }
    return allow("director_lower_package_mutation");
  }
}
