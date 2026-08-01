import { Pool } from "pg";
import { requiredMigrations, runMigrationDryRun } from "./v4-migrate-dry-run";

const databaseUrl = process.env.V4_PLATFORM_TEST_DATABASE_URL
  ?? process.env.DATABASE_URL
  ?? "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";

describe("T8.3.2 migration dry-run", () => {
  const pool = new Pool({ connectionString: databaseUrl, max: 1 });

  afterAll(async () => pool.end());

  it("is read-only, complete, drift-free and stable on repeat", async () => {
    const first = await runMigrationDryRun(pool);
    const second = await runMigrationDryRun(pool);

    expect(first.missingMigrations).toEqual([]);
    expect(first.requiredMigrations).toEqual(requiredMigrations);
    const restoreReadiness = first.invariants.find(
      (invariant) => invariant.id === "platform.foreign-key-restore-readiness",
    );
    const domainViolations = first.invariants
      .filter((invariant) => invariant !== restoreReadiness)
      .reduce((total, invariant) => total + invariant.violations, 0);
    expect(first.summary.invariants).toBe(8);
    expect(first.summary.pendingBatches).toBe(0);
    expect(domainViolations).toBe(0);
    // Other PostgreSQL integration suites can intentionally bypass FK triggers
    // for fixture teardown. The dedicated staging CLI gate, executed on a
    // freshly restored copy, owns the strict zero assertion for this invariant.
    expect(first.summary.violations).toBe(restoreReadiness?.violations ?? 0);
    expect(first.proof.transactionReadOnly).toBe(true);
    expect(second.proof.digestSha256).toBe(first.proof.digestSha256);
  });
});
