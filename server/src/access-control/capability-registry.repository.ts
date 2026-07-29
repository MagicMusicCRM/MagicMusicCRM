import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import {
  AccessRole,
  CapabilityEffect,
  CapabilityOverrideMode,
} from "./capability-registry";

interface CapabilityRow {
  capability_key: string;
  version: number;
  override_mode: CapabilityOverrideMode;
  active: boolean;
}

interface PackageEffectRow {
  package_id: string;
  package_version: number;
  effect: CapabilityEffect;
  capability_version: number;
}

@Injectable()
export class CapabilityRegistryRepository {
  constructor(private readonly database: DatabaseService) {}

  async findActiveDefinition(key: string): Promise<{
    key: string;
    version: number;
    overrideMode: CapabilityOverrideMode;
  } | null> {
    const result = await this.database.query<CapabilityRow>(
      `
        select capability_key, version, override_mode, active
          from app.capability_definitions
         where capability_key = $1 and active = true
      `,
      [key],
    );
    const row = result.rows[0];
    return row
      ? {
          key: row.capability_key,
          version: row.version,
          overrideMode: row.override_mode,
        }
      : null;
  }

  async resolveRoleEffect(
    role: AccessRole,
    capabilityKey: string,
  ): Promise<CapabilityEffect> {
    const result = await this.database.query<PackageEffectRow>(
      `
        select
          package.id as package_id,
          package.package_version,
          entry.effect,
          entry.capability_version
        from app.role_packages package
        join app.role_package_capabilities entry
          on entry.package_id = package.id
        join app.capability_definitions definition
          on definition.capability_key = entry.capability_key
         and definition.version = entry.capability_version
         and definition.active = true
        where package.role = $1::app.user_role
          and package.active = true
          and entry.capability_key = $2
      `,
      [role, capabilityKey],
    );
    return result.rows[0]?.effect ?? "deny";
  }

  async getActivePackage(role: AccessRole): Promise<{
    id: string;
    role: AccessRole;
    version: number;
    effects: Record<string, CapabilityEffect>;
  } | null> {
    const result = await this.database.query<{
      package_id: string;
      package_version: number;
      capability_key: string;
      effect: CapabilityEffect;
    }>(
      `
        select
          package.id as package_id,
          package.package_version,
          entry.capability_key,
          entry.effect
        from app.role_packages package
        join app.role_package_capabilities entry
          on entry.package_id = package.id
        where package.role = $1::app.user_role
          and package.active = true
        order by entry.capability_key
      `,
      [role],
    );
    const first = result.rows[0];
    if (!first) return null;
    return {
      id: first.package_id,
      role,
      version: Number(first.package_version),
      effects: Object.fromEntries(
        result.rows.map((row) => [row.capability_key, row.effect]),
      ),
    };
  }
}
