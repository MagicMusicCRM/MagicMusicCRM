import {
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../db/database.service";
import {
  AccessRole,
  CapabilityEffect,
  CapabilityKey,
  CapabilityOverrideMode,
} from "./capability-registry";

export interface AccessUserRecord {
  id: string;
  role: AccessRole;
  active: boolean;
  accessVersion: number;
}

export interface RolePackageSnapshot {
  id: string;
  role: AccessRole;
  version: number;
  effects: Record<CapabilityKey, CapabilityEffect>;
}

export interface UserOverrideSnapshot {
  capabilityKey: CapabilityKey;
  effect: CapabilityEffect;
  reasonCode: string;
}

interface UserRow {
  id: string;
  role: AccessRole;
  deleted_at: Date | null;
  access_version: number | string | null;
}

interface PackageRow {
  id: string;
  role: AccessRole;
  package_version: number | string;
  capability_key: CapabilityKey;
  effect: CapabilityEffect;
}

export interface EffectiveAccessSnapshotRow {
  userId: string;
  role: AccessRole;
  active: boolean;
  accessVersion: number;
  capabilityKey: CapabilityKey;
  capabilityActive: boolean;
  overrideMode: CapabilityOverrideMode;
  roleEffect: CapabilityEffect | null;
  overrideEffect: CapabilityEffect | null;
}

@Injectable()
export class AccessMutationsRepository {
  constructor(private readonly database: DatabaseService) {}

  async listActivePackages(): Promise<RolePackageSnapshot[]> {
    const result = await this.database.query<PackageRow>(
      `
        select
          package.id,
          package.role,
          package.package_version,
          entry.capability_key,
          entry.effect
        from app.role_packages package
        join app.role_package_capabilities entry
          on entry.package_id = package.id
        where package.active
        order by package.role, entry.capability_key
      `,
    );
    const grouped = new Map<AccessRole, RolePackageSnapshot>();
    for (const row of result.rows) {
      const snapshot = grouped.get(row.role) ?? {
        id: row.id,
        role: row.role,
        version: Number(row.package_version),
        effects: {} as Record<CapabilityKey, CapabilityEffect>,
      };
      snapshot.effects[row.capability_key] = row.effect;
      grouped.set(row.role, snapshot);
    }
    return [...grouped.values()];
  }

  async getActivePackage(role: AccessRole): Promise<RolePackageSnapshot> {
    const packages = await this.listActivePackages();
    const snapshot = packages.find((candidate) => candidate.role === role);
    if (!snapshot) {
      throw new NotFoundException({
        code: "ROLE_PACKAGE_NOT_FOUND",
        message: "Active role package was not found.",
      });
    }
    return snapshot;
  }

  async getUserAccessSnapshot(userId: string): Promise<{
    user: AccessUserRecord;
    overrides: UserOverrideSnapshot[];
  }> {
    const user = await this.database.query<UserRow>(
      `
        select
          user_row.id,
          user_row.role,
          user_row.deleted_at,
          access_version.version as access_version
        from app.users user_row
        left join app.user_access_versions access_version
          on access_version.user_id = user_row.id
        where user_row.id = $1
      `,
      [userId],
    );
    const row = user.rows[0];
    if (!row) {
      throw new NotFoundException({
        code: "ACCESS_USER_NOT_FOUND",
        message: "Access subject was not found.",
      });
    }
    const overrides = await this.database.query<{
      capability_key: CapabilityKey;
      effect: CapabilityEffect;
      reason_code: string;
    }>(
      `
        select capability_key, effect, reason_code
        from app.user_capability_overrides
        where user_id = $1 and active
        order by capability_key
      `,
      [userId],
    );
    return {
      user: this.mapUser(row),
      overrides: overrides.rows.map((override) => ({
        capabilityKey: override.capability_key,
        effect: override.effect,
        reasonCode: override.reason_code,
      })),
    };
  }

  async getEffectiveAccessSnapshot(
    userId: string,
  ): Promise<EffectiveAccessSnapshotRow[]> {
    const result = await this.database.query<{
      user_id: string;
      role: AccessRole;
      active: boolean;
      access_version: number | string | null;
      capability_key: CapabilityKey;
      capability_active: boolean;
      override_mode: CapabilityOverrideMode;
      role_effect: CapabilityEffect | null;
      override_effect: CapabilityEffect | null;
    }>(
      `
        select
          user_row.id as user_id,
          user_row.role,
          (user_row.deleted_at is null) as active,
          coalesce(access_version.version, 1) as access_version,
          definition.capability_key,
          definition.active as capability_active,
          definition.override_mode,
          package_entry.effect as role_effect,
          personal_override.effect as override_effect
        from app.users user_row
        cross join app.capability_definitions definition
        left join app.user_access_versions access_version
          on access_version.user_id = user_row.id
        left join app.role_packages package
          on package.role = user_row.role
         and package.active
        left join app.role_package_capabilities package_entry
          on package_entry.package_id = package.id
         and package_entry.capability_key = definition.capability_key
         and package_entry.capability_version = definition.version
        left join app.user_capability_overrides personal_override
          on personal_override.user_id = user_row.id
         and personal_override.capability_key = definition.capability_key
         and personal_override.capability_version = definition.version
         and personal_override.active
        where user_row.id = $1
          and definition.active
        order by definition.capability_key
      `,
      [userId],
    );
    if (result.rows.length === 0) {
      throw new NotFoundException({
        code: "ACCESS_USER_NOT_FOUND",
        message: "Access subject or active capability registry was not found.",
      });
    }
    return result.rows.map((row) => ({
      userId: row.user_id,
      role: row.role,
      active: row.active,
      accessVersion: Number(row.access_version ?? 1),
      capabilityKey: row.capability_key,
      capabilityActive: row.capability_active,
      overrideMode: row.override_mode,
      roleEffect: row.role_effect,
      overrideEffect: row.override_effect,
    }));
  }

  async lockUser(
    client: PoolClient,
    userId: string,
  ): Promise<AccessUserRecord> {
    const result = await client.query<UserRow>(
      `
        select
          user_row.id,
          user_row.role,
          user_row.deleted_at,
          access_version.version as access_version
        from app.users user_row
        left join app.user_access_versions access_version
          on access_version.user_id = user_row.id
        where user_row.id = $1
        for update of user_row
      `,
      [userId],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException({
        code: "ACCESS_USER_NOT_FOUND",
        message: "Access subject was not found.",
      });
    }
    return this.mapUser(row);
  }

  async countActiveSystemAdmins(client: PoolClient): Promise<number> {
    await client.query(
      "select pg_advisory_xact_lock(hashtext('access:last-system-admin'))",
    );
    const result = await client.query<{ count: number | string }>(
      `
        select count(*) as count
        from app.users
        where role = 'system_admin' and deleted_at is null
      `,
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  async countActiveOverrides(
    client: PoolClient,
    userId: string,
  ): Promise<number> {
    const result = await client.query<{ count: number | string }>(
      `
        select count(*) as count
        from app.user_capability_overrides
        where user_id = $1 and active
      `,
      [userId],
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  async assignRoleAndResetOverrides(
    client: PoolClient,
    input: {
      userId: string;
      role: AccessRole;
      nextVersion: number;
    },
  ): Promise<number> {
    const updated = await client.query(
      `
        update app.users
           set role = $2::app.user_role,
               updated_at = now()
         where id = $1 and deleted_at is null
      `,
      [input.userId, input.role],
    );
    if (updated.rowCount !== 1) {
      throw new NotFoundException({
        code: "ACCESS_USER_NOT_ACTIVE",
        message: "Access subject is not active.",
      });
    }
    // Staff card role is a projection of the canonical app role. Keeping it in
    // the same transaction prevents a settings-only role change from leaving
    // a misleading role in the employee card.
    await client.query(
      `update app.staff_members staff
       set role = $2, updated_at = now()
       from app.profiles profile
       where profile.user_id = $1
         and profile.id = staff.profile_id
         and profile.deleted_at is null
         and staff.deleted_at is null`,
      [input.userId, input.role],
    );
    const revoked = await client.query(
      `
        update app.user_capability_overrides
           set active = false,
               revoked_at = now()
         where user_id = $1 and active
      `,
      [input.userId],
    );
    await this.setUserAccessVersion(client, input.userId, input.nextVersion);
    return revoked.rowCount ?? 0;
  }

  async lockActivePackage(
    client: PoolClient,
    role: AccessRole,
  ): Promise<RolePackageSnapshot> {
    const result = await client.query<PackageRow>(
      `
        select
          package.id,
          package.role,
          package.package_version,
          entry.capability_key,
          entry.effect
        from app.role_packages package
        join app.role_package_capabilities entry
          on entry.package_id = package.id
        where package.role = $1::app.user_role and package.active
        order by entry.capability_key
        for update of package
      `,
      [role],
    );
    const first = result.rows[0];
    if (!first) {
      throw new NotFoundException({
        code: "ROLE_PACKAGE_NOT_FOUND",
        message: "Active role package was not found.",
      });
    }
    return {
      id: first.id,
      role: first.role,
      version: Number(first.package_version),
      effects: Object.fromEntries(
        result.rows.map((row) => [row.capability_key, row.effect]),
      ) as Record<CapabilityKey, CapabilityEffect>,
    };
  }

  async replaceRolePackage(
    client: PoolClient,
    input: {
      currentPackageId: string;
      role: AccessRole;
      nextVersion: number;
      actorUserId: string;
      effects: Record<CapabilityKey, CapabilityEffect>;
    },
  ): Promise<string> {
    const deactivated = await client.query(
      `
        update app.role_packages
           set active = false
         where id = $1 and active
      `,
      [input.currentPackageId],
    );
    if (deactivated.rowCount !== 1) {
      throw new ConflictException({
        code: "ROLE_PACKAGE_CHANGED",
        message: "Active role package changed concurrently.",
      });
    }
    const inserted = await client.query<{ id: string }>(
      `
        insert into app.role_packages (
          role,
          package_version,
          active,
          created_by
        )
        values ($1::app.user_role, $2, true, $3)
        returning id
      `,
      [input.role, input.nextVersion, input.actorUserId],
    );
    const packageId = inserted.rows[0]!.id;
    const entries = Object.entries(input.effects).map(
      ([capabilityKey, effect]) => ({
        capability_key: capabilityKey,
        effect,
      }),
    );
    await client.query(
      `
        insert into app.role_package_capabilities (
          package_id,
          capability_key,
          capability_version,
          effect
        )
        select
          $1,
          change.capability_key,
          definition.version,
          change.effect
        from jsonb_to_recordset($2::jsonb)
          as change(capability_key text, effect text)
        join app.capability_definitions definition
          on definition.capability_key = change.capability_key
         and definition.active
      `,
      [packageId, JSON.stringify(entries)],
    );
    return packageId;
  }

  async findActiveDefinition(
    client: PoolClient,
    capabilityKey: string,
  ): Promise<{
    key: CapabilityKey;
    version: number;
    overrideMode: CapabilityOverrideMode;
  } | null> {
    const result = await client.query<{
      capability_key: CapabilityKey;
      version: number;
      override_mode: CapabilityOverrideMode;
    }>(
      `
        select capability_key, version, override_mode
        from app.capability_definitions
        where capability_key = $1 and active
      `,
      [capabilityKey],
    );
    const row = result.rows[0];
    return row
      ? {
          key: row.capability_key,
          version: Number(row.version),
          overrideMode: row.override_mode,
        }
      : null;
  }

  async setUserOverride(
    client: PoolClient,
    input: {
      userId: string;
      capabilityKey: CapabilityKey;
      capabilityVersion: number;
      effect: CapabilityEffect;
      reasonCode: string;
      actorUserId: string;
      nextVersion: number;
    },
  ): Promise<void> {
    await client.query(
      `
        update app.user_capability_overrides
           set active = false,
               revoked_at = now()
         where user_id = $1
           and capability_key = $2
           and active
      `,
      [input.userId, input.capabilityKey],
    );
    await client.query(
      `
        insert into app.user_capability_overrides (
          user_id,
          capability_key,
          capability_version,
          effect,
          reason_code,
          actor_user_id
        )
        values ($1, $2, $3, $4, $5, $6)
      `,
      [
        input.userId,
        input.capabilityKey,
        input.capabilityVersion,
        input.effect,
        input.reasonCode,
        input.actorUserId,
      ],
    );
    await this.setUserAccessVersion(client, input.userId, input.nextVersion);
  }

  private async setUserAccessVersion(
    client: PoolClient,
    userId: string,
    nextVersion: number,
  ): Promise<void> {
    const result = await client.query(
      `
        insert into app.user_access_versions (user_id, version, changed_at)
        values ($1, $2, now())
        on conflict (user_id) do update
          set version = excluded.version,
              changed_at = excluded.changed_at
          where app.user_access_versions.version = excluded.version - 1
      `,
      [userId, nextVersion],
    );
    if (result.rowCount !== 1) {
      throw new ConflictException({
        code: "STALE_ACCESS_VERSION",
        message: "User access version changed concurrently.",
      });
    }
  }

  private mapUser(row: UserRow): AccessUserRecord {
    return {
      id: row.id,
      role: row.role,
      active: row.deleted_at === null,
      accessVersion: Number(row.access_version ?? 0),
    };
  }
}
