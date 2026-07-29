import { ForbiddenException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { readFileSync } from "fs";
import { basename, dirname, resolve } from "path";
import { Pool } from "pg";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import {
  BASELINE_CAPABILITY_ROLES,
  resolveCapabilityRoutePolicy,
} from "./capability-route-policy";
import { CapabilityRequestAuthorizer } from "./capability-request-authorizer";
import {
  AccessRole,
  CapabilityKey,
  USER_ROLES,
} from "./capability-registry";

interface CoveredRoute {
  id: string;
  verb: string;
  route: string;
  boundary: "jwt-capability" | "public-or-external";
  capabilityKey?: CapabilityKey;
  scope?: string;
}

interface CoverageReport {
  result: "PASS" | "FAIL";
  summary: {
    privateRoutes: number;
    unmappedPrivateRoutes: number;
    missingResourceScopes: number;
  };
  routes: CoveredRoute[];
}

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)) {
  throw new Error("Actor matrix tests require local PostgreSQL.");
}

function repositoryRoot(): string {
  const cwd = process.cwd();
  return basename(cwd).toLowerCase() === "server" ? dirname(cwd) : cwd;
}

jest.setTimeout(120_000);

describe("v4 six-actor route matrix (PostgreSQL)", () => {
  let database: DatabaseService;
  let authorizer: CapabilityRequestAuthorizer;
  const actorIds = new Map<AccessRole, string>();

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
    await database.query(
      "delete from app.users where email like 'v4-actor-matrix-%@example.test'",
    );
    for (const role of USER_ROLES) {
      const created = await database.query<{ id: string }>(
        `
          insert into app.users (email, role, email_verified_at)
          values ($1, $2::app.user_role, now())
          returning id
        `,
        [`v4-actor-matrix-${role}-${randomUUID()}@example.test`, role],
      );
      actorIds.set(role, created.rows[0]!.id);
    }
    authorizer = new CapabilityRequestAuthorizer(database);
  });

  afterAll(async () => {
    await database.query(
      "delete from app.users where id = any($1::uuid[])",
      [[...actorIds.values()]],
    );
    await database.onModuleDestroy();
  });

  it("matches every private route to registry allow/deny facts for all six actors", async () => {
    const report = JSON.parse(
      readFileSync(
        resolve(
          repositoryRoot(),
          "docs",
          "audits",
          "v4-access-coverage.json",
        ),
        "utf8",
      ),
    ) as CoverageReport;
    const routes = report.routes.filter(
      (route) => route.boundary === "jwt-capability",
    );
    expect(report.result).toBe("PASS");
    expect(report.summary).toMatchObject({
      privateRoutes: routes.length,
      unmappedPrivateRoutes: 0,
      missingResourceScopes: 0,
    });
    expect(routes).toHaveLength(255);

    const deviations: string[] = [];
    let allowed = 0;
    let denied = 0;
    for (const route of routes) {
      const policy = resolveCapabilityRoutePolicy(route.verb, route.route);
      if (
        policy.capabilityKey !== route.capabilityKey ||
        policy.scope !== route.scope
      ) {
        deviations.push(`${route.id}: stale coverage policy`);
        continue;
      }
      for (const role of USER_ROLES) {
        const expectedAllowed =
          role === "system_admin" ||
          BASELINE_CAPABILITY_ROLES[policy.capabilityKey].includes(role);
        const actor = { userId: actorIds.get(role)!, role };
        try {
          const decision = await authorizer.authorize(
            actor,
            route.verb,
            route.route,
          );
          if (!expectedAllowed) {
            deviations.push(`${route.id} :: ${role}: unexplained allow`);
          } else {
            allowed++;
            expect(decision.policy).toMatchObject({
              capabilityKey: route.capabilityKey,
              scope: route.scope,
            });
          }
        } catch (error) {
          if (expectedAllowed) {
            deviations.push(
              `${route.id} :: ${role}: unexpected ${error instanceof Error ? error.name : "error"}`,
            );
          } else if (!(error instanceof ForbiddenException)) {
            deviations.push(`${route.id} :: ${role}: non-403 denial`);
          } else {
            denied++;
          }
        }
      }
    }

    expect(deviations).toEqual([]);
    expect(allowed + denied).toBe(routes.length * USER_ROLES.length);
    expect(allowed).toBe(1_224);
    expect(denied).toBe(306);
  });
});
