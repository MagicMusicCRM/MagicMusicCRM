import { promises as fs } from "node:fs";
import { randomUUID } from "node:crypto";
import * as os from "node:os";
import * as path from "node:path";
import { Pool } from "pg";
import { MigrationRunner } from "./migration-runner";

const url = process.env.V4_PLATFORM_TEST_DATABASE_URL;
if (
  url &&
  (!["localhost", "127.0.0.1"].includes(new URL(url).hostname) ||
    !/test|audit_fix/.test(new URL(url).pathname))
)
  throw new Error("Isolated local test database required");
(url ? describe : describe.skip)("Migration checksums (PostgreSQL)", () => {
  let pool: Pool;
  let admin: Pool;
  let dir: string;
  let schema: string;
  beforeEach(async () => {
    schema = "migration_test_" + randomUUID().replaceAll("-", "");
    admin = new Pool({ connectionString: url });
    await admin.query(`create schema ${schema}`);
    pool = new Pool({
      connectionString: url,
      options: `-c search_path=${schema}`,
    });
    dir = await fs.mkdtemp(path.join(os.tmpdir(), "mmcrm-checksum-"));
    await fs.writeFile(
      path.join(dir, "0001_example.up.sql"),
      "create table example(id int);",
    );
    await fs.writeFile(
      path.join(dir, "0001_example.down.sql"),
      "drop table example;",
    );
  });
  afterEach(async () => {
    await pool.end();
    await admin.query(`drop schema ${schema} cascade`);
    await admin.end();
    const resolved = path.resolve(dir);
    if (
      !resolved.startsWith(path.resolve(os.tmpdir()) + path.sep) ||
      !path.basename(resolved).startsWith("mmcrm-checksum-")
    )
      throw new Error("Unexpected test directory");
    await fs.rm(resolved, { recursive: true, force: true });
  });
  it("requires an explicit verified baseline for legacy history", async () => {
    await pool.query(
      "create table app_schema_migrations(id text primary key,applied_at timestamptz not null default now())",
    );
    await pool.query(
      "insert into app_schema_migrations(id) values('0001_example')",
    );
    const runner = new MigrationRunner(pool, dir);
    await expect(runner.up()).rejects.toThrow(/baseline required/);
    await expect(
      runner.baselineLegacy({ "0001_example": "wrong" }),
    ).rejects.toThrow(/baseline mismatch/);
    expect(
      (await pool.query("select checksum from app_schema_migrations")).rows[0]
        .checksum,
    ).toBeNull();
    const manifest = await runner.manifest();
    expect(await runner.baselineLegacy(manifest)).toEqual(["0001_example"]);
    expect(await runner.up()).toEqual([]);
    expect(
      (await pool.query("select checksum_origin from app_schema_migrations"))
        .rows[0].checksum_origin,
    ).toBe("legacy_baseline");
    await fs.appendFile(path.join(dir, "0001_example.up.sql"), "-- changed");
    await expect(runner.up()).rejects.toThrow(/checksum mismatch/);
    await expect(
      runner.baselineLegacy(await runner.manifest()),
    ).rejects.toThrow(/baseline mismatch/);
  });
  it.each(["up", "down"])(
    "rejects changed %s SQL before applying anything",
    async (direction) => {
      const runner = new MigrationRunner(pool, dir);
      await runner.up();
      await fs.appendFile(
        path.join(dir, `0001_example.${direction}.sql`),
        "\n-- changed",
      );
      await fs.writeFile(
        path.join(dir, "0002_pending.up.sql"),
        "create table pending(id int);",
      );
      await fs.writeFile(
        path.join(dir, "0002_pending.down.sql"),
        "drop table pending;",
      );
      await expect(runner.up()).rejects.toThrow(/checksum/i);
      expect(
        (await pool.query("select to_regclass('pending') as id")).rows[0].id,
      ).toBeNull();
      await expect(runner.down()).rejects.toThrow(/checksum/i);
    },
  );
});
