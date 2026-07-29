import { ForbiddenException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { Pool } from "pg";
import type { Server } from "socket.io";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { PlatformIntegrityRepository } from "../platform/platform-integrity.repository";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { AccessMutationsRepository } from "./access-mutations.repository";
import { AccessMutationsService } from "./access-mutations.service";
import { CapabilityRequestAuthorizer } from "./capability-request-authorizer";
import { HardInvariantPolicy } from "./hard-invariant.policy";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)) {
  throw new Error("Access invalidation tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("access/session invalidation (PostgreSQL + realtime)", () => {
  let database: DatabaseService;
  let service: AccessMutationsService;
  let authorizer: CapabilityRequestAuthorizer;
  let fixtureUserIds: string[] = [];

  const requestPrefix = "v4-access-invalidation:";
  const roomListeners = new Map<
    string,
    Set<(event: string, payload: Record<string, unknown>) => void>
  >();

  function subscribe(
    room: string,
    listener: (event: string, payload: Record<string, unknown>) => void,
  ): () => void {
    const listeners = roomListeners.get(room) ?? new Set();
    listeners.add(listener);
    roomListeners.set(room, listeners);
    return () => listeners.delete(listener);
  }

  async function createUser(role: "director" | "manager"): Promise<string> {
    const result = await database.query<{ id: string }>(
      `
        insert into app.users (email, role, email_verified_at)
        values ($1, $2::app.user_role, now())
        returning id
      `,
      [`v4-access-invalidation-${randomUUID()}@example.test`, role],
    );
    const userId = result.rows[0]!.id;
    fixtureUserIds.push(userId);
    return userId;
  }

  async function cleanup(): Promise<void> {
    roomListeners.clear();
    await database.query(
      "delete from app.idempotency_records where operation like 'access.%' and actor_key = any($1::text[])",
      [fixtureUserIds],
    );
    await database.query(
      "delete from app.audit_events where request_id like $1",
      [`${requestPrefix}%`],
    );
    await database.query(
      "delete from app.platform_outbox_events where request_id like $1",
      [`${requestPrefix}%`],
    );
    if (fixtureUserIds.length > 0) {
      await database.query(
        "delete from app.user_capability_overrides where user_id = any($1::uuid[]) or actor_user_id = any($1::uuid[])",
        [fixtureUserIds],
      );
      await database.query(
        "delete from app.aggregate_versions where aggregate_type = 'access:user' and aggregate_id = any($1::text[])",
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
    const realtime = new RealtimeBus();
    realtime.setServer({
      to: (room: string) => ({
        emit: (event: string, payload: Record<string, unknown>) => {
          for (const listener of roomListeners.get(room) ?? []) {
            listener(event, payload);
          }
        },
      }),
    } as unknown as Server);
    service = new AccessMutationsService(
      new AccessMutationsRepository(database),
      new PlatformIntegrityService(
        database,
        new PlatformIntegrityRepository(),
      ),
      new HardInvariantPolicy(),
      realtime,
    );
    authorizer = new CapabilityRequestAuthorizer(database);
  });

  afterEach(cleanup);

  afterAll(async () => {
    await cleanup();
    await database.onModuleDestroy();
  });

  it("revokes both active sessions within five seconds and denies the next request", async () => {
    const directorUserId = await createUser("director");
    const managerUserId = await createUser("manager");
    const actor = { userId: managerUserId, role: "manager" as const };

    await expect(
      authorizer.authorize(actor, "GET", "/analytics/status"),
    ).resolves.toMatchObject({
      policy: { capabilityKey: "report.status.read" },
    });

    const received: Array<Record<string, unknown>> = [];
    const nextRequestChecks: Array<Promise<void>> = [];
    const controlVisible = [true, true];
    const sessionHandler =
      (sessionIndex: number) =>
      (event: string, payload: Record<string, unknown>) => {
        if (event !== "access.invalidated") return;
        controlVisible[sessionIndex] = false;
        received.push(payload);
        nextRequestChecks.push(
          authorizer
            .authorize(actor, "GET", "/analytics/status")
            .then(() => {
              throw new Error("Revoked request unexpectedly passed.");
            })
            .catch((error: unknown) => {
              expect(error).toBeInstanceOf(ForbiddenException);
            }),
        );
      };
    const unsubscribeFirst = subscribe(
      `user:${managerUserId}`,
      sessionHandler(0),
    );
    const unsubscribeSecond = subscribe(
      `user:${managerUserId}`,
      sessionHandler(1),
    );

    const startedAt = Date.now();
    const result = await service.setUserOverride(
      { userId: directorUserId, role: "director" },
      {
        userId: managerUserId,
        capabilityKey: "report.status.read",
        effect: "deny",
        expectedVersion: 1,
        emergencySurface: false,
        reasonCode: "test.session-revoke",
        idempotencyKey: `v4-access-${randomUUID()}`,
        requestId: `${requestPrefix}${randomUUID()}`,
      },
    );
    await Promise.all(nextRequestChecks);
    const invalidationLagMs = Date.now() - startedAt;
    unsubscribeFirst();
    unsubscribeSecond();

    expect(invalidationLagMs).toBeLessThanOrEqual(5_000);
    expect(controlVisible).toEqual([false, false]);
    expect(received).toEqual([
      { accessVersion: 2, scope: "user" },
      { accessVersion: 2, scope: "user" },
    ]);
    expect(result).toMatchObject({
      version: 2,
      replayed: false,
      resultRef: {
        userId: managerUserId,
        capabilityKey: "report.status.read",
        effect: "deny",
        accessVersion: 2,
      },
    });

    const committed = await database.query<{
      access_version: number | string;
      event_payload: Record<string, unknown>;
      audit_count: number | string;
    }>(
      `
        select
          access_version.version as access_version,
          event.payload as event_payload,
          (
            select count(*)
            from app.audit_events audit
            where audit.id = $3
          ) as audit_count
        from app.user_access_versions access_version
        join app.platform_outbox_events event on event.event_id = $2
        where access_version.user_id = $1
      `,
      [managerUserId, result.eventId, result.auditId],
    );
    expect(committed.rows[0]).toEqual({
      access_version: "2",
      event_payload: {
        accessVersion: 2,
        entityId: managerUserId,
        changedFields: ["report.status.read"],
      },
      audit_count: "1",
    });
  });
});
