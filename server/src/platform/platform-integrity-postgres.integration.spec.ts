import { ConflictException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { Pool } from "pg";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { PlatformIntegrityRepository } from "./platform-integrity.repository";
import { PlatformIntegrityService } from "./platform-integrity.service";
import {
  VersionedMutationCommand,
  VersionedMutationResultRef,
} from "./platform-integrity.types";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
const localHosts = new Set(["127.0.0.1", "localhost", "[::1]"]);

if (!localHosts.has(parsedDatabaseUrl.hostname)) {
  throw new Error(
    "Platform integration tests require a local PostgreSQL URL in " +
      "V4_PLATFORM_TEST_DATABASE_URL.",
  );
}

jest.setTimeout(60_000);

describe("PlatformIntegrityService (PostgreSQL)", () => {
  let database: DatabaseService;
  let service: PlatformIntegrityService;

  const cleanup = async () => {
    await database.query(
      "delete from app.idempotency_records where actor_key like 'v4-test:%'",
    );
    await database.query(
      "delete from app.audit_events where request_id like 'v4-test:%'",
    );
    await database.query(
      "delete from app.platform_outbox_events " +
        "where aggregate_type like 'v4-test:%'",
    );
    await database.query(
      "delete from app.aggregate_versions " +
        "where aggregate_type like 'v4-test:%'",
    );
  };

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await migrationPool.query(`
        do $$
        begin
          if not exists (
            select 1 from pg_roles where rolname = 'magiccrm_app'
          ) then
            create role magiccrm_app;
          end if;
        end $$
      `);
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }

    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    service = new PlatformIntegrityService(
      database,
      new PlatformIntegrityRepository(),
    );
    await cleanup();
  });

  afterEach(cleanup);

  afterAll(async () => {
    await cleanup();
    await database.onModuleDestroy();
  });

  function command<TResultRef extends VersionedMutationResultRef>(input: {
    actorKey: string;
    idempotencyKey: string;
    aggregateId: string;
    payload: unknown;
    expectedVersion?: number;
    requestId?: string;
    mutate: VersionedMutationCommand<TResultRef>["mutate"];
  }): VersionedMutationCommand<TResultRef> {
    return {
      actorKey: input.actorKey,
      operation: "v4-test:mutate",
      idempotencyKey: input.idempotencyKey,
      payload: input.payload,
      aggregateType: "v4-test:aggregate",
      aggregateId: input.aggregateId,
      expectedVersion: input.expectedVersion ?? 0,
      requestId: input.requestId ?? `v4-test:${randomUUID()}`,
      audit: {
        action: "v4-test.mutated",
        entityType: "v4-test:aggregate",
        entityId: input.aggregateId,
      },
      outbox: {
        type: "v4-test.aggregate.changed",
        payload: {
          contactEmail: "private@example.com",
          accessToken: "private-token",
          note: "Notify private@example.com",
          entityId: input.aggregateId,
          changedFields: ["status"],
        },
      },
      mutate: input.mutate,
    };
  }

  it("replays one result for parallel identical key and fingerprint", async () => {
    const actorKey = `v4-test:${randomUUID()}`;
    const aggregateId = randomUUID();
    const idempotencyKey = randomUUID();
    let mutationCalls = 0;
    const mutate = async () => {
      mutationCalls += 1;
      await new Promise((resolve) => setTimeout(resolve, 75));
      return {
        entityId: aggregateId,
        contactEmail: "private@example.com",
      };
    };

    const [left, right] = await Promise.all([
      service.executeVersionedMutation(
        command({
          actorKey,
          idempotencyKey,
          aggregateId,
          payload: { amount: 1, nested: { a: true, b: false } },
          mutate,
        }),
      ),
      service.executeVersionedMutation(
        command({
          actorKey,
          idempotencyKey,
          aggregateId,
          payload: { nested: { b: false, a: true }, amount: 1 },
          mutate,
        }),
      ),
    ]);

    expect(mutationCalls).toBe(1);
    expect([left.replayed, right.replayed].sort()).toEqual([false, true]);
    expect(left.resultRef).toEqual(right.resultRef);
    expect(left.resultRef.contactEmail).toBe("[PRIVATE]");
    expect(left.version).toBe(1);
    expect(right.version).toBe(1);
    expect(left.auditId).toBe(right.auditId);
    expect(left.eventId).toBe(right.eventId);

    const facts = await database.query<{
      idempotency_count: number | string;
      audit_count: number | string;
      outbox_count: number | string;
      version_count: number | string;
    }>(
      `
        select
          (
            select count(*) from app.idempotency_records
             where actor_key = $1
          ) as idempotency_count,
          (
            select count(*) from app.audit_events
             where request_id like 'v4-test:%'
          ) as audit_count,
          (
            select count(*) from app.platform_outbox_events
             where aggregate_type = 'v4-test:aggregate'
          ) as outbox_count,
          (
            select count(*) from app.aggregate_versions
             where aggregate_type = 'v4-test:aggregate'
               and aggregate_id = $2
          ) as version_count
      `,
      [actorKey, aggregateId],
    );
    expect(facts.rows[0]).toEqual({
      idempotency_count: "1",
      audit_count: "1",
      outbox_count: "1",
      version_count: "1",
    });

    const envelope = await database.query<{
      payload: Record<string, unknown>;
    }>(
      `
        select payload
          from app.platform_outbox_events
         where event_id = $1
      `,
      [left.eventId],
    );
    expect(envelope.rows[0]?.payload).toEqual({
      entityId: aggregateId,
      changedFields: ["status"],
    });
  });

  it("returns 409 for one key with different concurrent fingerprints", async () => {
    const actorKey = `v4-test:${randomUUID()}`;
    const aggregateId = randomUUID();
    const idempotencyKey = randomUUID();
    let mutationCalls = 0;
    const mutate = async () => {
      mutationCalls += 1;
      await new Promise((resolve) => setTimeout(resolve, 75));
      return { entityId: aggregateId };
    };

    const settled = await Promise.allSettled([
      service.executeVersionedMutation(
        command({
          actorKey,
          idempotencyKey,
          aggregateId,
          payload: { value: "left" },
          mutate,
        }),
      ),
      service.executeVersionedMutation(
        command({
          actorKey,
          idempotencyKey,
          aggregateId,
          payload: { value: "right" },
          mutate,
        }),
      ),
    ]);

    expect(mutationCalls).toBe(1);
    expect(settled.filter((item) => item.status === "fulfilled")).toHaveLength(
      1,
    );
    const rejection = settled.find(
      (item): item is PromiseRejectedResult => item.status === "rejected",
    );
    expect(rejection?.reason).toBeInstanceOf(ConflictException);
    expect((rejection?.reason as ConflictException).getStatus()).toBe(409);
    expect((rejection?.reason as ConflictException).getResponse()).toEqual(
      expect.objectContaining({ code: "IDEMPOTENCY_KEY_REUSED" }),
    );
  });

  it("rolls back reservation, version, audit, and outbox on mutation failure", async () => {
    const actorKey = `v4-test:${randomUUID()}`;
    const aggregateId = randomUUID();

    await expect(
      service.executeVersionedMutation(
        command({
          actorKey,
          idempotencyKey: randomUUID(),
          aggregateId,
          payload: { value: "rollback" },
          mutate: async () => {
            throw new Error("simulated domain failure");
          },
        }),
      ),
    ).rejects.toThrow("simulated domain failure");

    const facts = await database.query<{ fact_count: number | string }>(
      `
        select
          (select count(*) from app.idempotency_records where actor_key = $1)
          + (select count(*) from app.aggregate_versions
               where aggregate_type = 'v4-test:aggregate'
                 and aggregate_id = $2)
          + (select count(*) from app.audit_events
               where request_id like 'v4-test:%')
          + (select count(*) from app.platform_outbox_events
               where aggregate_type = 'v4-test:aggregate')
          as fact_count
      `,
      [actorKey, aggregateId],
    );
    expect(facts.rows[0]?.fact_count).toBe("0");
  });

  it("returns 409 for a stale aggregate version without side effects", async () => {
    const actorKey = `v4-test:${randomUUID()}`;
    const aggregateId = randomUUID();
    const mutate = async (_client: unknown, version: number) => ({
      entityId: aggregateId,
      version,
    });

    await service.executeVersionedMutation(
      command({
        actorKey,
        idempotencyKey: randomUUID(),
        aggregateId,
        payload: { revision: 1 },
        mutate,
      }),
    );
    await expect(
      service.executeVersionedMutation(
        command({
          actorKey,
          idempotencyKey: randomUUID(),
          aggregateId,
          payload: { revision: 2 },
          expectedVersion: 0,
          mutate,
        }),
      ),
    ).rejects.toMatchObject({ status: 409 });

    const facts = await database.query<{
      idempotency_count: number | string;
      audit_count: number | string;
      outbox_count: number | string;
      version: number | string;
    }>(
      `
        select
          (
            select count(*) from app.idempotency_records
             where actor_key = $1
          ) as idempotency_count,
          (
            select count(*) from app.audit_events
             where request_id like 'v4-test:%'
          ) as audit_count,
          (
            select count(*) from app.platform_outbox_events
             where aggregate_type = 'v4-test:aggregate'
          ) as outbox_count,
          (
            select version from app.aggregate_versions
             where aggregate_type = 'v4-test:aggregate'
               and aggregate_id = $2
          ) as version
      `,
      [actorKey, aggregateId],
    );
    expect(facts.rows[0]).toEqual({
      idempotency_count: "1",
      audit_count: "1",
      outbox_count: "1",
      version: "1",
    });
  });

  it("claims distinct events and persists retry, publish, and dead-letter state", async () => {
    await database.query(`
      update app.platform_outbox_events
         set published_at = coalesce(published_at, now()),
             claimed_at = null,
             claimed_by = null
       where aggregate_type <> 'v4-test:aggregate'
         and published_at is null
    `);
    const actorKey = `v4-test:${randomUUID()}`;
    for (const aggregateId of [randomUUID(), randomUUID()]) {
      await service.executeVersionedMutation(
        command({
          actorKey,
          idempotencyKey: randomUUID(),
          aggregateId,
          payload: { aggregateId },
          mutate: async () => ({ entityId: aggregateId }),
        }),
      );
    }

    const [left, right] = await Promise.all([
      service.claimOutbox("worker-left", { limit: 1, leaseSeconds: 60 }),
      service.claimOutbox("worker-right", { limit: 1, leaseSeconds: 60 }),
    ]);
    expect(left).toHaveLength(1);
    expect(right).toHaveLength(1);
    expect(left[0]?.eventId).not.toBe(right[0]?.eventId);

    await expect(
      service.markOutboxFailed(
        left[0]!,
        "worker-left",
        new Error("private provider message"),
        { baseSeconds: 1, capSeconds: 1, maxAttempts: 3 },
      ),
    ).resolves.toBe("retry");
    await database.query(
      `
        update app.platform_outbox_events
           set available_at = now() - interval '1 second'
         where event_id = $1
      `,
      [left[0]!.eventId],
    );
    const retried = await service.claimOutbox("worker-retry", {
      limit: 1,
      leaseSeconds: 60,
      maxAttempts: 3,
    });
    expect(retried[0]).toEqual(
      expect.objectContaining({
        eventId: left[0]!.eventId,
        attempts: 2,
      }),
    );
    await expect(
      service.markOutboxPublished(retried[0]!.eventId, "worker-retry"),
    ).resolves.toBe(true);

    await expect(
      service.markOutboxFailed(
        right[0]!,
        "worker-right",
        new TypeError("private provider message"),
        { maxAttempts: 1 },
      ),
    ).resolves.toBe("dead-letter");
    const states = await database.query<{
      event_id: string;
      published_at: Date | null;
      dead_lettered_at: Date | null;
      last_error: string | null;
    }>(
      `
        select event_id, published_at, dead_lettered_at, last_error
          from app.platform_outbox_events
         order by event_id
      `,
    );
    const published = states.rows.find(
      (row) => row.event_id === retried[0]!.eventId,
    );
    const deadLetter = states.rows.find(
      (row) => row.event_id === right[0]!.eventId,
    );
    expect(published?.published_at).not.toBeNull();
    expect(published?.dead_lettered_at).toBeNull();
    expect(deadLetter?.published_at).toBeNull();
    expect(deadLetter?.dead_lettered_at).not.toBeNull();
    expect(deadLetter?.last_error).toBe("TypeError");
  });
});
