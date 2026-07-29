import {
  ForbiddenException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { readFileSync } from "fs";
import { resolve } from "path";
import { Pool } from "pg";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { PlatformIntegrityRepository } from "../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { AccessMutationsRepository } from "./access-mutations.repository";
import { AccessMutationsService } from "./access-mutations.service";
import { AccessRole } from "./capability-registry";
import { HardInvariantPolicy } from "./hard-invariant.policy";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)) {
  throw new Error("Access mutation tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("AccessMutationsService (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: AccessMutationsService;
  let originalManagerPackage: {
    id: string;
    version: number;
  };
  let fixtureUserIds: string[] = [];

  const requestId = () => `v4-access:${randomUUID()}`;
  const idempotencyKey = () => `v4-access-${randomUUID()}`;

  async function createUser(role: AccessRole): Promise<ActorContext> {
    const result = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, $2::app.user_role, now())
        returning id
      `,
      [`v4-access-${randomUUID()}@example.test`, role],
    );
    const userId = result.rows[0]!.id;
    fixtureUserIds.push(userId);
    return { userId, role };
  }

  async function cleanup(): Promise<void> {
    await database.query(
      `
        delete from app.idempotency_records
        where actor_key like 'v4-access:%'
           or actor_key = any($1::text[])
      `,
      [fixtureUserIds],
    );
    await database.query(
      "delete from app.audit_events where request_id like 'v4-access:%'",
    );
    await database.query(
      "delete from app.platform_outbox_events where request_id like 'v4-access:%'",
    );
    await database.query(
      `
        update app.role_packages
           set active = false
         where role = 'manager'
           and id <> $1
      `,
      [originalManagerPackage.id],
    );
    await database.query(
      "update app.role_packages set active = true where id = $1",
      [originalManagerPackage.id],
    );
    await database.query(
      `
        delete from app.role_package_capabilities
        where package_id in (
          select id
          from app.role_packages
          where role = 'manager' and id <> $1
        )
      `,
      [originalManagerPackage.id],
    );
    await database.query(
      `
        delete from app.role_packages
        where role = 'manager' and id <> $1
      `,
      [originalManagerPackage.id],
    );
    await database.query(
      `
        update app.aggregate_versions
           set version = $1,
               updated_at = now()
         where aggregate_type = 'access:role-package'
           and aggregate_id = 'manager'
      `,
      [originalManagerPackage.version],
    );
    if (fixtureUserIds.length > 0) {
      await database.query(
        `
          delete from app.user_capability_overrides
          where user_id = any($1::uuid[])
             or actor_user_id = any($1::uuid[])
        `,
        [fixtureUserIds],
      );
      await database.query(
        `
          delete from app.aggregate_versions
          where aggregate_type = 'access:user'
            and aggregate_id = any($1::text[])
        `,
        [fixtureUserIds],
      );
      await database.query(
        "delete from app.users where id = any($1::uuid[])",
        [fixtureUserIds],
      );
    }
    fixtureUserIds = [];
  }

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
    await database.query(`
      delete from app.idempotency_records
      where operation like 'access.%'
        and actor_key in (
          select id::text from app.users
          where email like 'v4-access-%@example.test'
        );
      delete from app.audit_events where request_id like 'v4-access:%';
      delete from app.platform_outbox_events where request_id like 'v4-access:%';
      update app.role_packages
         set active = (id = '21000000-0000-0000-0000-000000000004')
       where role = 'manager';
      delete from app.role_package_capabilities
       where package_id in (
         select id from app.role_packages
          where role = 'manager'
            and id <> '21000000-0000-0000-0000-000000000004'
       );
      delete from app.role_packages
       where role = 'manager'
         and id <> '21000000-0000-0000-0000-000000000004';
      update app.aggregate_versions
         set version = 1, updated_at = now()
       where aggregate_type = 'access:role-package'
         and aggregate_id = 'manager';
      delete from app.aggregate_versions
       where aggregate_type = 'access:user'
         and aggregate_id in (
           select id::text from app.users
           where email like 'v4-access-%@example.test'
         );
      delete from app.user_capability_overrides
       where user_id in (
         select id from app.users
          where email like 'v4-access-%@example.test'
       )
          or actor_user_id in (
            select id from app.users
             where email like 'v4-access-%@example.test'
          );
      delete from app.users where email like 'v4-access-%@example.test';
    `);
    const repository = new AccessMutationsRepository(database);
    service = new AccessMutationsService(
      repository,
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new HardInvariantPolicy(),
      {
        emitUserAccessInvalidated: jest.fn(),
        emitRoleAccessInvalidated: jest.fn(),
      } as unknown as RealtimeBus,
    );
    const managerPackage = await repository.getActivePackage("manager");
    originalManagerPackage = {
      id: managerPackage.id,
      version: managerPackage.version,
    };
  });

  afterEach(cleanup);

  afterAll(async () => {
    await cleanup();
    await database.onModuleDestroy();
  });

  it("returns 403 to Manager and commits no partial access facts", async () => {
    const manager = await createUser("manager");
    const subject = await createUser("client");
    const commandRequestId = requestId();

    await expect(
      service.assignRole(manager, {
        userId: subject.userId,
        role: "teacher",
        expectedVersion: 1,
        resetOverridesConfirmed: true,
        emergencySurface: false,
        reasonCode: "test.manager-denied",
        idempotencyKey: idempotencyKey(),
        requestId: commandRequestId,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const facts = await database.query<{
      role: AccessRole;
      version: number | string;
      audit_count: number | string;
      outbox_count: number | string;
    }>(
      `
        select
          user_row.role,
          access_version.version,
          (
            select count(*) from app.audit_events where request_id = $2
          ) as audit_count,
          (
            select count(*) from app.platform_outbox_events
             where request_id = $2
          ) as outbox_count
        from app.users user_row
        join app.user_access_versions access_version
          on access_version.user_id = user_row.id
        where user_row.id = $1
      `,
      [subject.userId, commandRequestId],
    );
    expect(facts.rows[0]).toEqual({
      role: "client",
      version: "1",
      audit_count: "0",
      outbox_count: "0",
    });
  });

  it("atomically assigns a lower role, resets confirmed overrides, audits and emits", async () => {
    const director = await createUser("director");
    const subject = await createUser("client");
    await database.query(
      `
        insert into app.user_capability_overrides (
          user_id,
          capability_key,
          capability_version,
          effect,
          reason_code,
          actor_user_id
        )
        values ($1, 'workflow.task.read', 1, 'allow', 'test.fixture', $2)
      `,
      [subject.userId, director.userId],
    );

    const base = {
      userId: subject.userId,
      role: "manager" as const,
      expectedVersion: 1,
      emergencySurface: false,
      reasonCode: "test.role-assignment",
      idempotencyKey: idempotencyKey(),
      requestId: requestId(),
    };
    await expect(
      service.assignRole(director, {
        ...base,
        resetOverridesConfirmed: false,
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);

    const result = await service.assignRole(director, {
      ...base,
      idempotencyKey: idempotencyKey(),
      requestId: requestId(),
      resetOverridesConfirmed: true,
    });
    expect(result).toMatchObject({
      version: 2,
      replayed: false,
      resultRef: {
        userId: subject.userId,
        role: "manager",
        accessVersion: 2,
        overridesReset: 1,
      },
    });

    const facts = await database.query<{
      role: AccessRole;
      version: number | string;
      active_overrides: number | string;
      audit_before: Record<string, unknown>;
      audit_after: Record<string, unknown>;
      audit_reason: string;
      event_payload: Record<string, unknown>;
    }>(
      `
        select
          user_row.role,
          access_version.version,
          (
            select count(*) from app.user_capability_overrides
             where user_id = user_row.id and active
          ) as active_overrides,
          audit.before_ref as audit_before,
          audit.after_ref as audit_after,
          audit.reason as audit_reason,
          event.payload as event_payload
        from app.users user_row
        join app.user_access_versions access_version
          on access_version.user_id = user_row.id
        join app.audit_events audit on audit.id = $2
        join app.platform_outbox_events event on event.event_id = $3
        where user_row.id = $1
      `,
      [subject.userId, result.auditId, result.eventId],
    );
    expect(facts.rows[0]).toMatchObject({
      role: "manager",
      version: "2",
      active_overrides: "0",
      audit_before: {
        role: "client",
        accessVersion: 1,
        activeOverrideCount: 1,
      },
      audit_after: {
        userId: subject.userId,
        role: "manager",
        accessVersion: 2,
      },
      audit_reason: "test.role-assignment",
      event_payload: {
        accessVersion: 2,
        entityId: subject.userId,
        changedFields: ["role", "overrides"],
      },
    });
  });

  it("enforces Director hierarchy and explicit system_admin emergency flow", async () => {
    const director = await createUser("director");
    const root = await createUser("system_admin");
    const subject = await createUser("client");

    await expect(
      service.assignRole(director, {
        userId: director.userId,
        role: "manager",
        expectedVersion: 1,
        resetOverridesConfirmed: true,
        emergencySurface: false,
        reasonCode: "test.director-self",
        idempotencyKey: idempotencyKey(),
        requestId: requestId(),
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.assignRole(root, {
        userId: subject.userId,
        role: "system_admin",
        expectedVersion: 1,
        resetOverridesConfirmed: true,
        emergencySurface: false,
        reasonCode: "test.root-surface",
        idempotencyKey: idempotencyKey(),
        requestId: requestId(),
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);

    await expect(
      service.assignRole(root, {
        userId: subject.userId,
        role: "system_admin",
        expectedVersion: 1,
        resetOverridesConfirmed: true,
        emergencySurface: true,
        reasonCode: "test.root-promote",
        idempotencyKey: idempotencyKey(),
        requestId: requestId(),
      }),
    ).resolves.toMatchObject({
      version: 2,
      resultRef: { role: "system_admin" },
    });
  });

  it("sets one versioned override idempotently and rejects Manager", async () => {
    const manager = await createUser("manager");
    const director = await createUser("director");
    const subject = await createUser("client");
    const key = idempotencyKey();
    const commandRequestId = requestId();
    const command = {
      userId: subject.userId,
      capabilityKey: "workflow.task.read",
      effect: "allow" as const,
      expectedVersion: 1,
      emergencySurface: false,
      reasonCode: "test.override",
      idempotencyKey: key,
      requestId: commandRequestId,
    };

    await expect(
      service.setUserOverride(manager, {
        ...command,
        idempotencyKey: idempotencyKey(),
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const first = await service.setUserOverride(director, command);
    const replay = await service.setUserOverride(director, command);
    expect(first).toMatchObject({ version: 2, replayed: false });
    expect(replay).toEqual({ ...first, replayed: true });

    const counts = await database.query<{
      active_overrides: number | string;
      audit_count: number | string;
      outbox_count: number | string;
    }>(
      `
        select
          (
            select count(*) from app.user_capability_overrides
             where user_id = $1 and active
          ) as active_overrides,
          (
            select count(*) from app.audit_events where request_id = $2
          ) as audit_count,
          (
            select count(*) from app.platform_outbox_events
             where request_id = $2
          ) as outbox_count
      `,
      [subject.userId, commandRequestId],
    );
    expect(counts.rows[0]).toEqual({
      active_overrides: "1",
      audit_count: "1",
      outbox_count: "1",
    });
  });

  it("replaces a complete package and rolls back stale or hard-denied changes", async () => {
    const director = await createUser("director");
    const first = await service.replaceRolePackage(director, {
      role: "manager",
      expectedVersion: originalManagerPackage.version,
      changes: [
        {
          capabilityKey: "report.export.xlsx",
          effect: "deny",
        },
      ],
      emergencySurface: false,
      reasonCode: "test.package",
      idempotencyKey: idempotencyKey(),
      requestId: requestId(),
    });
    expect(first).toMatchObject({
      version: originalManagerPackage.version + 1,
      resultRef: {
        role: "manager",
        packageVersion: originalManagerPackage.version + 1,
      },
    });
    const active = await service.getRolePackage(director, "manager");
    expect(Object.keys(active.effects)).toHaveLength(20);
    expect(active.effects["report.export.xlsx"]).toBe("deny");

    await expect(
      service.replaceRolePackage(director, {
        role: "manager",
        expectedVersion: originalManagerPackage.version,
        changes: [
          {
            capabilityKey: "workflow.task.read",
            effect: "deny",
          },
        ],
        emergencySurface: false,
        reasonCode: "test.package-stale",
        idempotencyKey: idempotencyKey(),
        requestId: requestId(),
      }),
    ).rejects.toMatchObject({ status: 409 });
    await expect(
      service.replaceRolePackage(director, {
        role: "manager",
        expectedVersion: originalManagerPackage.version + 1,
        changes: [
          {
            capabilityKey: "commerce.school_finance.read",
            effect: "allow",
          },
        ],
        emergencySurface: false,
        reasonCode: "test.package-hard-deny",
        idempotencyKey: idempotencyKey(),
        requestId: requestId(),
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);

    const packageFacts = await database.query<{
      active_version: number | string;
      package_count: number | string;
    }>(
      `
        select
          max(package_version) filter (where active) as active_version,
          count(*) as package_count
        from app.role_packages
        where role = 'manager'
      `,
    );
    expect(packageFacts.rows[0]).toEqual({
      active_version: originalManagerPackage.version + 1,
      package_count: "2",
    });
  });

  it("keeps the controller routes and OpenAPI mutation contract in parity", () => {
    const contract = JSON.parse(
      readFileSync(
        resolve(
          process.cwd(),
          "..",
          "docs",
          "contracts",
          "v4-access-mutations.openapi.json",
        ),
        "utf8",
      ),
    ) as {
      paths: Record<string, Record<string, { operationId: string }>>;
    };
    expect(
      Object.values(contract.paths)
        .flatMap((path) => Object.values(path))
        .map((operation) => operation.operationId)
        .sort(),
    ).toEqual([
      "assignRole",
      "getRolePackage",
      "getUserAccess",
      "listRolePackages",
      "replaceRolePackage",
      "setUserOverride",
    ]);
  });
});
