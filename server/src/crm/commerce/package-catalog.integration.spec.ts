import {
  ConflictException,
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../../audit/audit.service";
import {
  ActorContext,
  UserRole,
} from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { PlatformIntegrityRepository } from "../../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { SubscriptionsService } from "../subscriptions.service";
import { PackageCatalogRepository } from "./package-catalog.repository";
import { PackageCatalogService } from "./package-catalog.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(
    new URL(databaseUrl).hostname,
  )
) {
  throw new Error("Package catalog tests require local PostgreSQL.");
}

const roles: readonly UserRole[] = [
  "client",
  "teacher",
  "admin",
  "manager",
  "director",
  "system_admin",
];
const readRoles = new Set<UserRole>([
  "admin",
  "manager",
  "director",
  "system_admin",
]);
const manageRoles = new Set<UserRole>(["director", "system_admin"]);
const marker = `v4-package-catalog-${randomUUID()}`;

jest.setTimeout(120_000);

describe("Subscription Package catalog (PostgreSQL)", () => {
  let pool: Pool;
  let database: DatabaseService;
  let catalog: PackageCatalogService;
  let subscriptions: SubscriptionsService;
  let actors: Record<UserRole, ActorContext>;
  let branchId: string;
  let profileId: string;
  let studentId: string;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    database = new DatabaseService({
      getOrThrow: () => databaseUrl,
    } as unknown as ConfigService);

    const repository = new PackageCatalogRepository(database);
    catalog = new PackageCatalogService(
      repository,
      new CrmPolicy(),
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
    );
    subscriptions = new SubscriptionsService(
      database,
      {
        record: jest.fn().mockResolvedValue(undefined),
      } as unknown as AuditService,
      new CrmPolicy(),
      {
        emitCrmChanged: jest.fn(),
        emitFinanceChanged: jest.fn(),
      } as unknown as RealtimeBus,
    );

    const fixture = await createFixture(pool);
    actors = fixture.actors;
    branchId = fixture.branchId;
    profileId = fixture.profileId;
    studentId = fixture.studentId;
  });

  afterAll(async () => {
    if (pool) {
      await cleanupFixture(pool, {
        actorUserIds: actors
          ? roles.map((role) => actors[role].userId)
          : [],
        branchId,
        profileId,
        studentId,
      });
    }
    if (database) await database.onModuleDestroy();
    if (pool) await pool.end();
  });

  it("enforces the six-role read/mutate matrix", async () => {
    const visible = await createPackage(
      actors.director,
      "actor-matrix-visible",
      {
        unitCount: 1.5,
        basePriceMinor: "800050",
      },
    );
    expect(visible).toMatchObject({
      name: `${marker}-actor-matrix-visible`,
      unitCount: 1.5,
      lessonsTotal: 1.5,
      basePriceMinor: "800050",
      price: 8000.5,
      currencyCode: "RUB",
      active: true,
      isActive: true,
      version: 1,
    });

    for (const role of roles) {
      const actor = actors[role];
      if (readRoles.has(role)) {
        await expect(catalog.list(actor, {})).resolves.toEqual({
          items: expect.arrayContaining([
            expect.objectContaining({ id: visible.id, active: true }),
          ]),
        });
      } else {
        await expect(catalog.list(actor, {})).rejects.toBeInstanceOf(
          ForbiddenException,
        );
      }

      const mutation = catalog.create(
        actor,
        packageInput(`actor-matrix-${role}`),
        mutationMetadata(`actor-matrix-${role}`),
      );
      if (manageRoles.has(role)) {
        const created = await mutation;
        expect(created.version).toBe(1);
        expect(created.active).toBe(true);
      } else {
        await expect(mutation).rejects.toBeInstanceOf(ForbiddenException);
      }
    }
  });

  it("keeps archived rows root-visible and restores the same versioned row", async () => {
    const created = await createPackage(
      actors.director,
      "archive-restore",
      { unitCount: 2.25 },
    );
    const archived = await catalog.archive(
      actors.director,
      created.id,
      created.version,
      mutationMetadata("archive"),
    );
    expect(archived).toMatchObject({
      id: created.id,
      active: false,
      isActive: false,
      version: 2,
    });
    expect(archived.archivedAt).not.toBeNull();

    for (const role of ["admin", "manager"] as const) {
      const active = await catalog.list(actors[role], {});
      expect(active.items.some((item) => item.id === created.id)).toBe(false);
      await expect(
        catalog.list(actors[role], { includeArchived: true }),
      ).rejects.toBeInstanceOf(ForbiddenException);
    }
    for (const role of ["director", "system_admin"] as const) {
      const all = await catalog.list(actors[role], {
        includeArchived: true,
      });
      expect(all.items).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            id: created.id,
            active: false,
            version: 2,
          }),
        ]),
      );
    }

    const restored = await catalog.restore(
      actors.system_admin,
      created.id,
      archived.version,
      mutationMetadata("restore"),
    );
    expect(restored).toMatchObject({
      id: created.id,
      active: true,
      isActive: true,
      version: 3,
      archivedAt: null,
    });
    const activeAgain = await catalog.list(actors.manager, {});
    expect(activeAgain.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: created.id, version: 3 }),
      ]),
    );

    await expectPackageAndAggregateVersion(created.id, 3);
    const facts = await catalogFactCounts(created.id);
    expect(facts).toEqual({
      audits: 3,
      outbox: 3,
      idempotency: 3,
    });
  });

  it("replays the same key and rejects a changed fingerprint", async () => {
    const metadata = mutationMetadata("idempotency");
    const input = packageInput("idempotency", {
      unitCount: 1.5,
      basePriceMinor: "640075",
    });
    const first = await catalog.create(actors.director, input, metadata);
    const replay = await catalog.create(actors.director, input, metadata);

    expect(replay).toEqual(first);
    expect(replay).toMatchObject({
      name: input.name,
      unitCount: 1.5,
      basePriceMinor: "640075",
      price: 6400.75,
      version: 1,
    });
    await expect(
      catalog.create(
        actors.director,
        { ...input, name: `${input.name}-changed` },
        metadata,
      ),
    ).rejects.toBeInstanceOf(ConflictException);

    const persisted = await pool.query<{ count: string }>(
      "select count(*)::text as count from app.subscription_packages where id = $1",
      [first.id],
    );
    expect(persisted.rows[0]!.count).toBe("1");
    expect(await catalogFactCounts(first.id)).toEqual({
      audits: 1,
      outbox: 1,
      idempotency: 1,
    });

    const updated = await catalog.update(
      actors.director,
      first.id,
      {
        expectedVersion: first.version,
        name: `${input.name}-version-2`,
        basePriceMinor: "700000",
      },
      mutationMetadata("idempotency-later-update"),
    );
    expect(updated).toMatchObject({
      name: `${input.name}-version-2`,
      basePriceMinor: "700000",
      version: 2,
    });

    // A late transport retry must return the exact v1 result recorded by the
    // original create, never the now-current v2 catalog row.
    const lateReplay = await catalog.create(
      actors.director,
      input,
      metadata,
    );
    expect(lateReplay).toEqual(first);
    await expectPackageAndAggregateVersion(first.id, 2);
    expect(await catalogFactCounts(first.id)).toEqual({
      audits: 2,
      outbox: 2,
      idempotency: 2,
    });
    const history = await pool.query<{ versions: string[] }>(
      `
        select array_agg(version::text order by version) as versions
        from app.subscription_package_versions
        where package_id = $1
      `,
      [first.id],
    );
    expect(history.rows[0]!.versions).toEqual(["1", "2"]);
    await expect(
      pool.query(
        `
          update app.subscription_package_versions
          set name = 'tampered'
          where package_id = $1 and version = 1
        `,
        [first.id],
      ),
    ).rejects.toMatchObject({
      code: "23514",
      message: "subscription package version history is immutable",
    });
  });

  it("allows one concurrent writer and keeps audit/outbox/version in sync", async () => {
    const created = await createPackage(
      actors.director,
      "concurrent-version",
    );
    const outcomes = await Promise.allSettled([
      catalog.update(
        actors.director,
        created.id,
        {
          expectedVersion: created.version,
          name: `${marker}-concurrent-director`,
        },
        mutationMetadata("concurrent-director"),
      ),
      catalog.update(
        actors.system_admin,
        created.id,
        {
          expectedVersion: created.version,
          name: `${marker}-concurrent-system-admin`,
        },
        mutationMetadata("concurrent-system-admin"),
      ),
    ]);
    const fulfilled = outcomes.filter(
      (outcome): outcome is PromiseFulfilledResult<
        Awaited<ReturnType<PackageCatalogService["update"]>>
      > => outcome.status === "fulfilled",
    );
    const rejected = outcomes.filter(
      (outcome): outcome is PromiseRejectedResult =>
        outcome.status === "rejected",
    );

    expect(fulfilled).toHaveLength(1);
    expect(fulfilled[0]!.value.version).toBe(2);
    expect(rejected).toHaveLength(1);
    expect(rejected[0]!.reason).toBeInstanceOf(ConflictException);
    await expectPackageAndAggregateVersion(created.id, 2);
    expect(await catalogFactCounts(created.id)).toEqual({
      audits: 2,
      outbox: 2,
      idempotency: 2,
    });
  });

  it("issues immutable snapshots before and after catalog update, then archives a used package", async () => {
    const created = await createPackage(
      actors.director,
      "issued-snapshot-v1",
      {
        unitCount: 1.5,
        basePriceMinor: "800000",
        validityDays: 90,
      },
    );
    const firstIssue = await subscriptions.issueSubscription(
      actors.director,
      studentId,
      { packageId: created.id },
    );
    const firstBefore = await loadIssuedSnapshot(firstIssue.id);
    const frozenSnapshot = structuredClone(firstBefore.commercial_snapshot);
    expect(firstBefore).toMatchObject({
      package_version: "1",
      base_price_minor: "800000",
    });
    expect(frozenSnapshot).toMatchObject({
      snapshotVersion: 1,
      packageVersion: 1,
      displayName: created.name,
      basePriceMinor: "800000",
      currencyCode: "RUB",
      discount: { type: "none" },
      finalPriceMinor: "800000",
    });
    expect(Number(frozenSnapshot.unitCount)).toBe(1.5);

    const updated = await catalog.update(
      actors.director,
      created.id,
      {
        expectedVersion: created.version,
        name: `${marker}-issued-snapshot-v2`,
        unitCount: 2.25,
        basePriceMinor: "900050",
      },
      mutationMetadata("issued-update"),
    );
    expect(updated).toMatchObject({
      unitCount: 2.25,
      basePriceMinor: "900050",
      price: 9000.5,
      version: 2,
    });

    const firstAfter = await loadIssuedSnapshot(firstIssue.id);
    expect(firstAfter.commercial_snapshot).toEqual(frozenSnapshot);
    expect(firstAfter).toMatchObject({
      package_version: "1",
      base_price_minor: "800000",
    });

    const secondIssue = await subscriptions.issueSubscription(
      actors.director,
      studentId,
      { packageId: created.id },
    );
    const second = await loadIssuedSnapshot(secondIssue.id);
    expect(second).toMatchObject({
      package_version: "2",
      base_price_minor: "900050",
    });
    expect(second.commercial_snapshot).toMatchObject({
      snapshotVersion: 1,
      packageVersion: 2,
      displayName: `${marker}-issued-snapshot-v2`,
      basePriceMinor: "900050",
      currencyCode: "RUB",
      finalPriceMinor: "900050",
    });
    expect(Number(second.commercial_snapshot.unitCount)).toBe(2.25);

    const archived = await catalog.archive(
      actors.system_admin,
      created.id,
      updated.version,
      mutationMetadata("issued-archive"),
    );
    expect(archived).toMatchObject({
      id: created.id,
      active: false,
      version: 3,
    });
    const issuedRows = await pool.query<{ count: string }>(
      `
        select count(*)::text as count
        from app.subscriptions
        where package_id = $1 and commercial_snapshot is not null
      `,
      [created.id],
    );
    expect(issuedRows.rows[0]!.count).toBe("2");
    expect((await loadIssuedSnapshot(firstIssue.id)).commercial_snapshot).toEqual(
      frozenSnapshot,
    );
    await expect(
      subscriptions.issueSubscription(
        actors.director,
        studentId,
        { packageId: created.id },
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expectPackageAndAggregateVersion(created.id, 3);
  });

  it("revokes runtime history mutation and blocks destructive rollback", async () => {
    const created = await createPackage(
      actors.director,
      "rollback-history",
    );
    await catalog.update(
      actors.director,
      created.id,
      {
        expectedVersion: created.version,
        name: `${created.name}-v2`,
      },
      mutationMetadata("rollback-history-update"),
    );

    const privileges = await pool.query<{
      role_exists: boolean;
      can_update: boolean;
      can_delete: boolean;
    }>(
      `
        select
          exists (
            select 1 from pg_roles where rolname = 'magiccrm_app'
          ) as role_exists,
          case when exists (
            select 1 from pg_roles where rolname = 'magiccrm_app'
          ) then has_table_privilege(
            'magiccrm_app',
            'app.subscription_package_versions',
            'UPDATE'
          ) else false end as can_update,
          case when exists (
            select 1 from pg_roles where rolname = 'magiccrm_app'
          ) then has_table_privilege(
            'magiccrm_app',
            'app.subscription_package_versions',
            'DELETE'
          ) else false end as can_delete
      `,
    );
    expect(privileges.rows[0]).toEqual({
      role_exists: true,
      can_update: false,
      can_delete: false,
    });

    const runner = new MigrationRunner(pool);
    const peeledMigrations: string[] = [];
    while (true) {
      const latest = await pool.query<{ id: string }>(
        `
          select id
          from app_schema_migrations
          order by applied_at desc
          limit 1
        `,
      );
      if (latest.rows[0]?.id === "0090_commerce_package_aggregate_versions") {
        break;
      }
      const rolledBack = await runner.down();
      if (!rolledBack) throw new Error("Migration chain ended before 0090.");
      peeledMigrations.push(rolledBack);
    }
    expect(peeledMigrations).toEqual(
      expect.arrayContaining([
        "0091_commerce_issued_subscription_aggregate_versions",
        "0092_shared_tasks_audience_schema",
      ]),
    );
    try {
      await expect(runner.down()).rejects.toMatchObject({
        code: "23514",
        message:
          "catalog version history exists; rollback would break idempotent replay",
      });
      const applied = await pool.query<{ count: string }>(
        `
          select count(*)::text as count
          from app_schema_migrations
          where id = '0090_commerce_package_aggregate_versions'
        `,
      );
      expect(applied.rows[0]!.count).toBe("1");
    } finally {
      const restored = await runner.up();
      expect(restored).toEqual(expect.arrayContaining(peeledMigrations));
    }
  });

  function packageInput(
    suffix: string,
    overrides: Partial<{
      unitCount: number;
      basePriceMinor: string;
      validityDays: number;
    }> = {},
  ) {
    return {
      name: `${marker}-${suffix}`,
      unitCount: overrides.unitCount ?? 8,
      basePriceMinor: overrides.basePriceMinor ?? "640000",
      currencyCode: "RUB",
      validityDays: overrides.validityDays ?? 60,
      sortOrder: 0,
    };
  }

  async function createPackage(
    actor: ActorContext,
    suffix: string,
    overrides: Partial<{
      unitCount: number;
      basePriceMinor: string;
      validityDays: number;
    }> = {},
  ) {
    return catalog.create(
      actor,
      packageInput(suffix, overrides),
      mutationMetadata(`create-${suffix}`),
    );
  }

  function mutationMetadata(suffix: string) {
    const id = randomUUID();
    return {
      idempotencyKey: `catalog-${suffix}-${id}`,
      requestId: `catalog-${suffix}-${id}`,
    };
  }

  async function expectPackageAndAggregateVersion(
    packageId: string,
    version: number,
  ) {
    const result = await pool.query<{
      package_version: string;
      aggregate_version: string;
    }>(
      `
        select
          package.version::text as package_version,
          aggregate.version::text as aggregate_version
        from app.subscription_packages package
        join app.aggregate_versions aggregate
          on aggregate.aggregate_type = 'commerce:subscription-package'
         and aggregate.aggregate_id = package.id::text
        where package.id = $1
      `,
      [packageId],
    );
    expect(result.rows[0]).toEqual({
      package_version: String(version),
      aggregate_version: String(version),
    });
  }

  async function catalogFactCounts(packageId: string) {
    const result = await pool.query<{
      audits: string;
      outbox: string;
      idempotency: string;
    }>(
      `
        select
          (
            select count(*)::text
            from app.audit_events
            where entity_type = 'subscription_package'
              and entity_id = $1
          ) as audits,
          (
            select count(*)::text
            from app.platform_outbox_events
            where aggregate_type = 'commerce:subscription-package'
              and aggregate_id = $1
          ) as outbox,
          (
            select count(*)::text
            from app.idempotency_records
            where result_ref->>'packageId' = $1
          ) as idempotency
      `,
      [packageId],
    );
    const row = result.rows[0]!;
    return {
      audits: Number(row.audits),
      outbox: Number(row.outbox),
      idempotency: Number(row.idempotency),
    };
  }

  async function loadIssuedSnapshot(subscriptionId: string) {
    const result = await pool.query<{
      commercial_snapshot: Record<string, unknown>;
      package_version: string;
      base_price_minor: string;
    }>(
      `
        select
          commercial_snapshot,
          package_version::text,
          base_price_minor::text
        from app.subscriptions
        where id = $1
      `,
      [subscriptionId],
    );
    return result.rows[0]!;
  }
});

async function createFixture(pool: Pool): Promise<{
  actors: Record<UserRole, ActorContext>;
  branchId: string;
  profileId: string;
  studentId: string;
}> {
  const client = await pool.connect();
  await client.query("begin");
  try {
    const actors = {} as Record<UserRole, ActorContext>;
    for (const role of roles) {
      const result = await client.query<{ id: string }>(
        `
          insert into app.users (email, role, email_verified_at)
          values ($1, $2, now())
          returning id
        `,
        [`${marker}-${role}@example.test`, role],
      );
      actors[role] = { userId: result.rows[0]!.id, role };
    }
    const branch = await client.query<{ id: string }>(
      `
        insert into app.branches (name, timezone_name)
        values ($1, 'Europe/Moscow')
        returning id
      `,
      [`${marker}-branch`],
    );
    const profile = await client.query<{ id: string }>(
      `
        insert into app.profiles (user_id, first_name, last_name)
        values ($1, 'Catalog', 'Client')
        returning id
      `,
      [actors.client.userId],
    );
    const student = await client.query<{ id: string }>(
      `
        insert into app.students (profile_id, branch_id)
        values ($1, $2)
        returning id
      `,
      [profile.rows[0]!.id, branch.rows[0]!.id],
    );
    await client.query("commit");
    return {
      actors,
      branchId: branch.rows[0]!.id,
      profileId: profile.rows[0]!.id,
      studentId: student.rows[0]!.id,
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function cleanupFixture(
  pool: Pool,
  input: {
    actorUserIds: string[];
    branchId?: string;
    profileId?: string;
    studentId?: string;
  },
): Promise<void> {
  const client = await pool.connect();
  await client.query("begin");
  try {
    await client.query("set local session_replication_role = replica");
    const packages = await client.query<{ id: string }>(
      "select id from app.subscription_packages where name like $1",
      [`${marker}%`],
    );
    const packageIds = packages.rows.map((row) => row.id);
    const payments =
      packageIds.length === 0
        ? { rows: [] as { id: string }[] }
        : await client.query<{ id: string }>(
            `
              select payment_id as id
              from app.subscriptions
              where package_id = any($1::uuid[]) and payment_id is not null
            `,
            [packageIds],
          );
    const paymentIds = payments.rows.map((row) => row.id);
    const paymentRecords = input.studentId
      ? await client.query<{ id: string }>(
          `
            select id
            from app.client_payment_records
            where student_id = $1
               or actual_payment_id = any($2::uuid[])
          `,
          [input.studentId, paymentIds],
        )
      : { rows: [] as { id: string }[] };
    const paymentRecordIds = paymentRecords.rows.map((row) => row.id);

    await deleteByIds(
      client,
      "app.idempotency_records",
      "actor_key",
      input.actorUserIds,
      "text",
    );
    await deleteByIds(
      client,
      "app.platform_outbox_events",
      "aggregate_id",
      packageIds,
      "text",
    );
    await deleteByIds(
      client,
      "app.audit_events",
      "entity_id",
      packageIds,
      "text",
    );
    await deleteByIds(
      client,
      "app.aggregate_versions",
      "aggregate_id",
      packageIds,
      "text",
    );
    await deleteByIds(
      client,
      "app.subscription_package_versions",
      "package_id",
      packageIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.client_payment_status_events",
      "payment_record_id",
      paymentRecordIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.client_payment_records",
      "id",
      paymentRecordIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscriptions",
      "package_id",
      packageIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.payments",
      "id",
      paymentIds,
      "uuid",
    );
    await deleteByIds(
      client,
      "app.subscription_packages",
      "id",
      packageIds,
      "uuid",
    );
    if (input.studentId) {
      await client.query("delete from app.students where id = $1", [
        input.studentId,
      ]);
    }
    if (input.profileId) {
      await client.query("delete from app.profiles where id = $1", [
        input.profileId,
      ]);
    }
    if (input.branchId) {
      await client.query("delete from app.branches where id = $1", [
        input.branchId,
      ]);
    }
    await deleteByIds(
      client,
      "app.users",
      "id",
      input.actorUserIds,
      "uuid",
    );
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function deleteByIds(
  client: PoolClient,
  table: string,
  column: string,
  ids: string[],
  cast: "text" | "uuid",
): Promise<void> {
  if (ids.length === 0) return;
  await client.query(
    `delete from ${table} where ${column} = any($1::${cast}[])`,
    [ids],
  );
}
