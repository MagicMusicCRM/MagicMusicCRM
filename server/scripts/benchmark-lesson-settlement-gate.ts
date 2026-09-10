import { Pool } from "pg";
import { performance } from "node:perf_hooks";
import {
  acquireLessonSettlementCoordinationGate,
  acquireSingleLessonSettlementGate,
  acquireLessonSettlementLocks,
} from "../src/crm/commerce/lesson-settlement-locks";

// A reproducible lock-contention probe, not an application throughput benchmark.
async function main() {
  const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
  if (
    !url ||
    !["localhost", "127.0.0.1"].includes(new URL(url).hostname) ||
    !/test|audit_fix/.test(new URL(url).pathname)
  )
    throw new Error(
      "Set V4_PLATFORM_TEST_DATABASE_URL to an isolated local test database.",
    );
  const pool = new Pool({ connectionString: url, max: 6 });
  const clients = await Promise.all(
    Array.from({ length: 6 }, () => pool.connect()),
  );
  try {
    const samples = [];
    for (const mode of ["exclusive", "single-shared", "same-lesson"] as const) {
      for (let sample = 0; sample < 3; sample++) {
        for (const client of clients) {
          await client.query("begin");
          await client.query("set local lock_timeout='5s'");
        }
        const start = performance.now();
        const waits = await Promise.all(
          clients.map(async (client, index) => {
            try {
              const before = performance.now();
              if (mode === "exclusive")
                await acquireLessonSettlementCoordinationGate(client);
              else await acquireSingleLessonSettlementGate(client);
              await acquireLessonSettlementLocks(client, [
                mode === "same-lesson"
                  ? "benchmark-shared"
                  : `benchmark-independent-${index}`,
              ]);
              const waitMs = performance.now() - before;
              await client.query("select pg_sleep(0.04)");
              await client.query("rollback");
              return waitMs;
            } catch (error) {
              await client.query("rollback");
              throw error;
            }
          }),
        );
        samples.push({
          mode,
          sample,
          commands: 6,
          simulatedWorkMs: 40,
          elapsedMs: Math.round(performance.now() - start),
          maxWaitMs: Math.round(Math.max(...waits)),
        });
      }
    }
    console.log(
      JSON.stringify(
        {
          scope:
            "Local advisory-lock contention only; no business rows modified",
          samples,
        },
        null,
        2,
      ),
    );
  } finally {
    for (const client of clients) client.release();
    await pool.end();
  }
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
