import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { PlatformAuditInput } from "../platform/platform-integrity.types";
import {
  AccessMutationsRepository,
  RolePackageSnapshot,
} from "./access-mutations.repository";
import {
  AccessRole,
  CAPABILITY_DEFINITIONS,
  CapabilityEffect,
  CapabilityKey,
  isCapabilityKey,
} from "./capability-registry";
import {
  HardInvariantPolicy,
  InvariantDecision,
} from "./hard-invariant.policy";
import { RealtimeBus } from "../realtime/realtime-bus";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface AssignRoleCommand extends MutationMetadata {
  userId: string;
  role: AccessRole;
  expectedVersion: number;
  resetOverridesConfirmed: boolean;
  emergencySurface: boolean;
  reasonCode: string;
}

export interface ReplaceRolePackageCommand extends MutationMetadata {
  role: AccessRole;
  expectedVersion: number;
  changes: Array<{
    capabilityKey: CapabilityKey;
    effect: CapabilityEffect;
  }>;
  emergencySurface: boolean;
  reasonCode: string;
}

export interface SetUserOverrideCommand extends MutationMetadata {
  userId: string;
  capabilityKey: string;
  effect: CapabilityEffect;
  expectedVersion: number;
  emergencySurface: boolean;
  reasonCode: string;
}

const businessRoles: readonly AccessRole[] = [
  "client",
  "teacher",
  "admin",
  "manager",
  "director",
];

@Injectable()
export class AccessMutationsService {
  constructor(
    private readonly repository: AccessMutationsRepository,
    private readonly integrity: PlatformIntegrityService,
    private readonly hardInvariants: HardInvariantPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  async listRolePackages(actor: ActorContext): Promise<RolePackageSnapshot[]> {
    this.assertAccessManager(actor);
    const packages = await this.repository.listActivePackages();
    return actor.role === "system_admin"
      ? packages
      : packages.filter((rolePackage) => rolePackage.role !== "system_admin");
  }

  async getRolePackage(
    actor: ActorContext,
    role: AccessRole,
  ): Promise<RolePackageSnapshot> {
    this.assertAccessManager(actor);
    if (actor.role !== "system_admin" && role === "system_admin") {
      throw new ForbiddenException({
        code: "HIDDEN_ROOT_PACKAGE",
        message: "The root role package is available only in emergency flow.",
      });
    }
    return this.repository.getActivePackage(role);
  }

  async getUserAccess(actor: ActorContext, userId: string) {
    this.assertAccessManager(actor);
    const snapshot = await this.repository.getUserAccessSnapshot(userId);
    if (
      actor.role !== "system_admin" &&
      (snapshot.user.role === "system_admin" ||
        snapshot.user.role === "director")
    ) {
      throw new ForbiddenException({
        code: "DIRECTOR_SUBJECT_MUST_BE_LOWER",
        message: "Director may inspect access only for lower roles.",
      });
    }
    const rolePackage = await this.repository.getActivePackage(
      snapshot.user.role,
    );
    return { ...snapshot, rolePackage };
  }

  async assignRole(actor: ActorContext, command: AssignRoleCommand) {
    this.assertMetadata(command);
    this.assertReason(command.reasonCode);
    const audit: PlatformAuditInput = {
      action: "access.user.role_assigned",
      entityType: "access:user",
      entityId: command.userId,
      reason: command.reasonCode,
    };

    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "access.user.role.assign",
      idempotencyKey: command.idempotencyKey,
      payload: {
        userId: command.userId,
        role: command.role,
        resetOverridesConfirmed: command.resetOverridesConfirmed,
        emergencySurface: command.emergencySurface,
        reasonCode: command.reasonCode,
      },
      aggregateType: "access:user",
      aggregateId: command.userId,
      expectedVersion: command.expectedVersion,
      requestId: command.requestId,
      audit,
      outbox: {
        type: "access.invalidated",
        payload: {
          entityId: command.userId,
          changedFields: ["role", "overrides"],
        },
      },
      mutate: async (client, nextVersion) => {
        const subject = await this.repository.lockUser(client, command.userId);
        if (!subject.active) {
          throw new NotFoundException({
            code: "ACCESS_USER_NOT_ACTIVE",
            message: "Access subject is not active.",
          });
        }
        if (subject.role === command.role) {
          throw new BadRequestException({
            code: "ROLE_UNCHANGED",
            message: "Target role is already assigned.",
          });
        }
        const activeSystemAdminCount =
          await this.repository.countActiveSystemAdmins(client);
        this.assertInvariant(
          this.hardInvariants.roleAssignmentDecision({
            actorUserId: actor.userId,
            actorRole: actor.role,
            subjectUserId: subject.id,
            subjectRole: subject.role,
            subjectActive: subject.active,
            targetRole: command.role,
            activeSystemAdminCount,
            emergencySurface: command.emergencySurface,
          }),
        );
        const activeOverrideCount =
          await this.repository.countActiveOverrides(client, subject.id);
        if (activeOverrideCount > 0 && !command.resetOverridesConfirmed) {
          throw new UnprocessableEntityException({
            code: "OVERRIDE_RESET_CONFIRMATION_REQUIRED",
            message: "Role change requires explicit override reset confirmation.",
          });
        }
        audit.beforeRef = {
          role: subject.role,
          accessVersion: subject.accessVersion,
          activeOverrideCount,
        };
        const overridesReset =
          await this.repository.assignRoleAndResetOverrides(client, {
            userId: subject.id,
            role: command.role,
            nextVersion,
          });
        return {
          userId: subject.id,
          role: command.role,
          accessVersion: nextVersion,
          overridesReset,
        };
      },
    });
    if (!result.replayed) {
      this.realtime.emitUserAccessInvalidated(command.userId, result.version);
    }
    return result;
  }

  async replaceRolePackage(
    actor: ActorContext,
    command: ReplaceRolePackageCommand,
  ) {
    this.assertMetadata(command);
    this.assertReason(command.reasonCode);
    this.assertPackageChanges(command.changes);
    const audit: PlatformAuditInput = {
      action: "access.role_package_replaced",
      entityType: "access:role-package",
      entityId: command.role,
      reason: command.reasonCode,
    };

    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "access.role_package.replace",
      idempotencyKey: command.idempotencyKey,
      payload: {
        role: command.role,
        changes: command.changes,
        emergencySurface: command.emergencySurface,
        reasonCode: command.reasonCode,
      },
      aggregateType: "access:role-package",
      aggregateId: command.role,
      expectedVersion: command.expectedVersion,
      requestId: command.requestId,
      audit,
      outbox: {
        type: "access.package.changed",
        payload: {
          scope: command.role,
          changedFields: command.changes.map(
            (change) => change.capabilityKey,
          ),
        },
      },
      mutate: async (client, nextVersion) => {
        this.assertInvariant(
          this.hardInvariants.packageMutationDecision({
            actorRole: actor.role,
            targetRole: command.role,
            emergencySurface: command.emergencySurface,
          }),
        );
        const current = await this.repository.lockActivePackage(
          client,
          command.role,
        );
        if (
          current.version !== command.expectedVersion ||
          nextVersion !== current.version + 1
        ) {
          throw new ConflictException({
            code: "STALE_ROLE_PACKAGE_VERSION",
            message: "Role package version changed concurrently.",
          });
        }
        const nextEffects = { ...current.effects };
        for (const change of command.changes) {
          const definition = await this.repository.findActiveDefinition(
            client,
            change.capabilityKey,
          );
          if (!definition) {
            throw new UnprocessableEntityException({
              code: "UNKNOWN_CAPABILITY",
              message: "Capability is not active in the registry.",
            });
          }
          if (
            change.effect === "allow" &&
            this.hardInvariants.capabilityDecision(
              command.role,
              change.capabilityKey,
            )?.allowed === false
          ) {
            throw new UnprocessableEntityException({
              code: "HARD_DENY_CANNOT_BE_PACKAGED",
              message: "A hard-denied capability cannot be allowed by a package.",
            });
          }
          nextEffects[change.capabilityKey] = change.effect;
        }
        audit.beforeRef = {
          role: command.role,
          packageVersion: current.version,
          effects: current.effects,
        };
        const packageId = await this.repository.replaceRolePackage(client, {
          currentPackageId: current.id,
          role: command.role,
          nextVersion,
          actorUserId: actor.userId,
          effects: nextEffects,
        });
        return {
          packageId,
          role: command.role,
          packageVersion: nextVersion,
          effects: nextEffects,
        };
      },
    });
    if (!result.replayed) {
      this.realtime.emitRoleAccessInvalidated(command.role, result.version);
    }
    return result;
  }

  async setUserOverride(actor: ActorContext, command: SetUserOverrideCommand) {
    this.assertMetadata(command);
    this.assertReason(command.reasonCode);
    if (!isCapabilityKey(command.capabilityKey)) {
      throw new UnprocessableEntityException({
        code: "UNKNOWN_CAPABILITY",
        message: "Capability is not active in the registry.",
      });
    }
    const capabilityKey = command.capabilityKey;
    const audit: PlatformAuditInput = {
      action: "access.user.override_set",
      entityType: "access:user",
      entityId: command.userId,
      reason: command.reasonCode,
    };

    const result = await this.integrity.executeVersionedMutation({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      operation: "access.user.override.set",
      idempotencyKey: command.idempotencyKey,
      payload: {
        userId: command.userId,
        capabilityKey,
        effect: command.effect,
        emergencySurface: command.emergencySurface,
        reasonCode: command.reasonCode,
      },
      aggregateType: "access:user",
      aggregateId: command.userId,
      expectedVersion: command.expectedVersion,
      requestId: command.requestId,
      audit,
      outbox: {
        type: "access.invalidated",
        payload: {
          entityId: command.userId,
          changedFields: [capabilityKey],
        },
      },
      mutate: async (client, nextVersion) => {
        const subject = await this.repository.lockUser(client, command.userId);
        if (!subject.active) {
          throw new NotFoundException({
            code: "ACCESS_USER_NOT_ACTIVE",
            message: "Access subject is not active.",
          });
        }
        const definition = await this.repository.findActiveDefinition(
          client,
          capabilityKey,
        );
        if (!definition) {
          throw new UnprocessableEntityException({
            code: "UNKNOWN_CAPABILITY",
            message: "Capability is not active in the registry.",
          });
        }
        this.assertInvariant(
          this.hardInvariants.overrideMutationDecision({
            actorUserId: actor.userId,
            actorRole: actor.role,
            subjectUserId: subject.id,
            subjectRole: subject.role,
            capabilityKey,
            effect: command.effect,
            overrideMode: definition.overrideMode,
            emergencySurface: command.emergencySurface,
          }),
        );
        audit.beforeRef = {
          role: subject.role,
          accessVersion: subject.accessVersion,
        };
        await this.repository.setUserOverride(client, {
          userId: subject.id,
          capabilityKey,
          capabilityVersion: definition.version,
          effect: command.effect,
          reasonCode: command.reasonCode,
          actorUserId: actor.userId,
          nextVersion,
        });
        return {
          userId: subject.id,
          role: subject.role,
          capabilityKey,
          effect: command.effect,
          accessVersion: nextVersion,
        };
      },
    });
    if (!result.replayed) {
      this.realtime.emitUserAccessInvalidated(command.userId, result.version);
    }
    return result;
  }

  private assertAccessManager(actor: ActorContext): void {
    if (actor.role !== "director" && actor.role !== "system_admin") {
      throw new ForbiddenException({
        code: "DIRECTOR_OR_SYSTEM_ADMIN_REQUIRED",
        message: "Access management requires Director or system administrator.",
      });
    }
  }

  private assertInvariant(decision: InvariantDecision): void {
    if (decision.allowed) return;
    const body = {
      code: decision.reason.toUpperCase(),
      message: "Access mutation violates a hard invariant.",
    };
    if (
      decision.reason === "last_active_system_admin" ||
      decision.reason.startsWith("capability_override") ||
      decision.reason === "hard_deny_cannot_be_overridden"
    ) {
      throw new UnprocessableEntityException(body);
    }
    throw new ForbiddenException(body);
  }

  private assertMetadata(metadata: MutationMetadata): void {
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(metadata.idempotencyKey)) {
      throw new BadRequestException({
        code: "INVALID_IDEMPOTENCY_KEY",
        message: "Idempotency-Key must be 8-128 safe characters.",
      });
    }
    if (
      !metadata.requestId ||
      metadata.requestId.length > 128 ||
      /[\r\n]/.test(metadata.requestId)
    ) {
      throw new BadRequestException({
        code: "INVALID_REQUEST_ID",
        message: "x-request-id must be present and no longer than 128 characters.",
      });
    }
  }

  private assertReason(reasonCode: string): void {
    if (!/^[A-Za-z0-9._:-]{1,120}$/.test(reasonCode)) {
      throw new BadRequestException({
        code: "INVALID_REASON_CODE",
        message: "A safe reason code is required.",
      });
    }
  }

  private assertPackageChanges(
    changes: ReplaceRolePackageCommand["changes"],
  ): void {
    if (changes.length < 1 || changes.length > CAPABILITY_DEFINITIONS.length) {
      throw new BadRequestException({
        code: "INVALID_PACKAGE_CHANGES",
        message: "Role package changes must be a bounded non-empty list.",
      });
    }
    const keys = new Set<string>();
    for (const change of changes) {
      if (
        !isCapabilityKey(change.capabilityKey) ||
        !["allow", "deny"].includes(change.effect) ||
        keys.has(change.capabilityKey)
      ) {
        throw new BadRequestException({
          code: "INVALID_PACKAGE_CHANGES",
          message: "Role package changes contain duplicates or invalid values.",
        });
      }
      keys.add(change.capabilityKey);
    }
  }
}

export const ACCESS_BUSINESS_ROLES = businessRoles;
