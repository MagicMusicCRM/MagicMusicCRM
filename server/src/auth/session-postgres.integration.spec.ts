import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { randomUUID } from "node:crypto";
import { DatabaseService } from "../db/database.service";
import { AuditService } from "../audit/audit.service";
import { SessionService } from "./session.service";
const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
if (
  url &&
  (!["localhost", "127.0.0.1"].includes(new URL(url).hostname) ||
    !/test|audit_fix/.test(new URL(url).pathname))
)
  throw new Error("Isolated test database required");
(url ? describe : describe.skip)(
  "Session rotation concurrency (PostgreSQL)",
  () => {
    let db: DatabaseService;
    let service: SessionService;
    const users: string[] = [];
    beforeAll(() => {
      const config = {
        getOrThrow: (key: string) =>
          key === "DATABASE_URL"
            ? url
            : "test-secret-test-secret-test-secret-123",
        get: (_key: string, fallback: unknown) => fallback,
      } as unknown as ConfigService;
      db = new DatabaseService(config);
      service = new SessionService(
        db,
        new JwtService(),
        config,
        new AuditService(db),
      );
    });
    afterAll(async () => {
      await db?.onModuleDestroy();
    });
    it("consumes a refresh token once and commits family revocation on reuse", async () => {
      const id = randomUUID();
      users.push(id);
      await db.query(
        "insert into app.users(id,email,role) values($1,$2,'client')",
        [id, id + "@example.test"],
      );
      const pair = await service.issueForUser({
        id,
        email: id + "@example.test",
        role: "client",
      });
      // Force both unprotected reads to finish before either can consume the token.
      // A correct implementation reads the session inside the locked transaction.
      let reads = 0;
      let release!: () => void;
      const barrier = new Promise<void>((resolve) => {
        release = resolve;
      });
      const originalQuery = db.query.bind(db);
      const query = jest
        .spyOn(db, "query")
        .mockImplementation(async (sql: any, params?: any[]) => {
          const result = await originalQuery(sql, params);
          if (typeof sql === "string" && sql.includes("select rs.id")) {
            if (++reads === 2) release();
            await barrier;
          }
          return result;
        });
      const result = await Promise.allSettled([
        service.rotate(pair.refreshToken),
        service.rotate(pair.refreshToken),
      ]);
      query.mockRestore();
      expect(result.filter((r) => r.status === "fulfilled").length).toBe(1);
      const state = await db.query(
        "select count(*) filter(where revoked_at is null)::int as active,count(*)::int as total from app.refresh_sessions where user_id=$1",
        [id],
      );
      expect(state.rows[0]).toEqual({ active: 0, total: 2 });
      expect(
        (
          await db.query(
            "select id from app.audit_events where actor_user_id=$1 and action='auth.refresh_reuse_detected'",
            [id],
          )
        ).rows,
      ).toHaveLength(1);
    });
  },
);
