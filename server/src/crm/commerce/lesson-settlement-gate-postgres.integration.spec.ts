import { Pool, PoolClient } from "pg";
import {
  acquireSingleLessonSettlementGate,
  acquireLessonSettlementCoordinationGate,
  acquireLessonSettlementLocks,
} from "./lesson-settlement-locks";
const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
if (
  url &&
  (!["localhost", "127.0.0.1"].includes(new URL(url).hostname) ||
    !/test|audit_fix/.test(new URL(url).pathname))
)
  throw new Error("Isolated local test database required");
(url ? describe : describe.skip)(
  "Settlement gate concurrency (PostgreSQL)",
  () => {
    let pool: Pool;
    let a: PoolClient;
    let b: PoolClient;
    beforeAll(() => {
      pool = new Pool({ connectionString: url });
    });
    beforeEach(async () => {
      a = await pool.connect();
      b = await pool.connect();
      for (const c of [a, b]) {
        await c.query("begin");
        await c.query("set local lock_timeout='300ms'");
      }
    });
    afterEach(async () => {
      await a.query("rollback");
      await b.query("rollback");
      a.release();
      b.release();
    });
    afterAll(async () => pool.end());
    it("allows independent single-lesson commands concurrently", async () => {
      await acquireSingleLessonSettlementGate(a);
      await acquireLessonSettlementLocks(a, ["gate-test-a"]);
      await expect(
        acquireSingleLessonSettlementGate(b),
      ).resolves.toBeUndefined();
      await acquireLessonSettlementLocks(b, ["gate-test-b"]);
    });
    it("still serializes two commands on the same lesson", async () => {
      await acquireSingleLessonSettlementGate(a);
      await acquireLessonSettlementLocks(a, ["gate-test-a"]);
      await acquireSingleLessonSettlementGate(b);
      await expect(
        acquireLessonSettlementLocks(b, ["gate-test-a"]),
      ).rejects.toMatchObject({ code: "55P03" });
    });
    it("excludes dynamic batches while a single command is active", async () => {
      await acquireSingleLessonSettlementGate(a);
      await expect(
        acquireLessonSettlementCoordinationGate(b),
      ).rejects.toMatchObject({ code: "55P03" });
    });
    it("coordinates with existing exclusive writers during mixed-version rollout", async () => {
      await acquireLessonSettlementCoordinationGate(a);
      await expect(acquireSingleLessonSettlementGate(b)).rejects.toMatchObject({
        code: "55P03",
      });
    });
  },
);
