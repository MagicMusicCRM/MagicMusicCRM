import { promises as fs } from "node:fs";
import { Pool } from "pg";
import { MigrationRunner } from "./migration-runner";

async function main() {
  const direction = process.argv[2] ?? "up";
  const connectionString =
    process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error(
      "MIGRATION_DATABASE_URL or DATABASE_URL is required for migrations.",
    );
  }

  const pool = new Pool({ connectionString });
  const runner = new MigrationRunner(pool);

  try {
    if (direction === "manifest") {
      console.log(JSON.stringify(await runner.manifest(), null, 2));
      return;
    }
    if (direction === "baseline") {
      const manifestPath = process.argv[3];
      if (!manifestPath)
        throw new Error(
          "Provide the path to a reviewed migration checksum manifest.",
        );
      const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
      const baselined = await runner.baselineLegacy(manifest);
      console.log(
        `Baselined legacy migrations: ${baselined.length}. This records reviewed files, not proof of historic SQL execution.`,
      );
      return;
    }
    if (direction === "up") {
      const applied = await runner.up();
      console.log(
        `Applied migrations: ${applied.length ? applied.join(", ") : "none"}`,
      );
      return;
    }

    if (direction === "down") {
      const reverted = await runner.down();
      console.log(`Reverted migration: ${reverted ?? "none"}`);
      return;
    }

    throw new Error(`Unknown migration direction: ${direction}`);
  } finally {
    await pool.end();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
