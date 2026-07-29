import { ConfigService } from "@nestjs/config";
import { readFileSync } from "fs";
import { resolve } from "path";
import { Pool } from "pg";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import {
  CAPABILITY_DEFINITIONS,
  USER_ROLES,
} from "./capability-registry";
import { CapabilityRegistryRepository } from "./capability-registry.repository";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)) {
  throw new Error("Capability registry tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("CapabilityRegistryRepository (PostgreSQL)", () => {
  let database: DatabaseService;
  let repository: CapabilityRegistryRepository;

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    repository = new CapabilityRegistryRepository(database);
  });

  afterAll(async () => {
    await database.onModuleDestroy();
  });

  it("seeds one complete active package for every approved role", async () => {
    const counts = await database.query<{
      definitions: number | string;
      packages: number | string;
      entries: number | string;
      incomplete_packages: number | string;
    }>(
      `
        select
          (select count(*) from app.capability_definitions where active) as definitions,
          (select count(*) from app.role_packages where active) as packages,
          (select count(*) from app.role_package_capabilities) as entries,
          (
            select count(*)
            from (
              select package.id
              from app.role_packages package
              left join app.role_package_capabilities entry
                on entry.package_id = package.id
              where package.active
              group by package.id
              having count(entry.capability_key) <> $1
            ) incomplete
          ) as incomplete_packages
      `,
      [CAPABILITY_DEFINITIONS.length],
    );
    expect(counts.rows[0]).toEqual({
      definitions: String(CAPABILITY_DEFINITIONS.length),
      packages: String(USER_ROLES.length),
      entries: String(CAPABILITY_DEFINITIONS.length * USER_ROLES.length),
      incomplete_packages: "0",
    });
    for (const role of USER_ROLES) {
      const packageSnapshot = await repository.getActivePackage(role);
      expect(packageSnapshot).toEqual(
        expect.objectContaining({
          role,
          version: 1,
        }),
      );
      expect(Object.keys(packageSnapshot!.effects)).toHaveLength(
        CAPABILITY_DEFINITIONS.length,
      );
    }
  });

  it("keeps typed registry and OpenAPI capability snapshot identical", async () => {
    const snapshot = JSON.parse(
      readFileSync(
        resolve(
          process.cwd(),
          "..",
          "docs",
          "contracts",
          "v4-capability-registry.openapi.json",
        ),
        "utf8",
      ),
    ) as {
      components: {
        schemas: {
          CapabilityKey: { enum: string[] };
          AccessRole: { enum: string[] };
        };
      };
    };
    expect(snapshot.components.schemas.CapabilityKey.enum).toEqual(
      CAPABILITY_DEFINITIONS.map((definition) => definition.key),
    );
    expect(snapshot.components.schemas.AccessRole.enum).toEqual(USER_ROLES);

    const databaseDefinitions = await database.query<{
      capability_key: string;
      version: number;
      domain: string;
      risk_level: string;
      override_mode: string;
    }>(
      `
        select capability_key, version, domain, risk_level, override_mode
        from app.capability_definitions
        where active
        order by capability_key
      `,
    );
    expect(databaseDefinitions.rows).toEqual(
      [...CAPABILITY_DEFINITIONS]
        .sort((left, right) => left.key.localeCompare(right.key))
        .map((definition) => ({
          capability_key: definition.key,
          version: definition.version,
          domain: definition.domain,
          risk_level: definition.riskLevel,
          override_mode: definition.overrideMode,
        })),
    );
  });

  it("fails closed for unknown capability or missing package entry", async () => {
    await expect(
      repository.findActiveDefinition("unknown.resource.read"),
    ).resolves.toBeNull();
    await expect(
      repository.resolveRoleEffect("system_admin", "unknown.resource.read"),
    ).resolves.toBe("deny");
  });

  it("seeds equivalent-or-stricter privacy and management boundaries", async () => {
    await expect(
      repository.resolveRoleEffect("teacher", "crm.client.read.contacts"),
    ).resolves.toBe("deny");
    await expect(
      repository.resolveRoleEffect("teacher", "schedule.lesson.write"),
    ).resolves.toBe("deny");
    await expect(
      repository.resolveRoleEffect(
        "teacher",
        "commerce.client_finance.read",
      ),
    ).resolves.toBe("deny");
    await expect(
      repository.resolveRoleEffect("manager", "access.user.role.assign"),
    ).resolves.toBe("deny");
    await expect(
      repository.resolveRoleEffect(
        "manager",
        "commerce.school_finance.read",
      ),
    ).resolves.toBe("deny");
    await expect(
      repository.resolveRoleEffect("manager", "commerce.package.manage"),
    ).resolves.toBe("deny");
    await expect(
      repository.resolveRoleEffect("manager", "system.settings.manage"),
    ).resolves.toBe("allow");
    await expect(
      repository.resolveRoleEffect(
        "director",
        "commerce.school_finance.read",
      ),
    ).resolves.toBe("allow");
    await expect(
      repository.resolveRoleEffect("director", "access.user.role.assign"),
    ).resolves.toBe("allow");
  });

  it("enforces one active package and one active definition version", async () => {
    await expect(
      database.query(
        `
          insert into app.role_packages (role, package_version, active)
          values ('client', 999, true)
        `,
      ),
    ).rejects.toMatchObject({ code: "23505" });
    await expect(
      database.query(
        `
          insert into app.capability_definitions (
            capability_key,
            version,
            description,
            domain,
            risk_level,
            override_mode,
            active
          )
          values (
            'crm.client.read.basic',
            999,
            'duplicate active fixture',
            'crm',
            'medium',
            'allow_deny',
            true
          )
        `,
      ),
    ).rejects.toMatchObject({ code: "23505" });
  });

  it("seeds a monotonic access version for every existing user", async () => {
    const missing = await database.query<{ count: number | string }>(
      `
        select count(*)
        from app.users user_row
        left join app.user_access_versions access_version
          on access_version.user_id = user_row.id
        where access_version.user_id is null
           or access_version.version < 1
      `,
    );
    expect(missing.rows[0]?.count).toBe("0");
  });
});
