import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import * as path from "node:path";
import { Pool } from "pg";

const migrationTable = "app_schema_migrations";

// Migrations whose first lines contain this marker run OUTSIDE a transaction
// block, so statements like `CREATE INDEX CONCURRENTLY` (forbidden inside a
// transaction) can be used on large/high-write tables without a write lock.
// Such migration bodies must be safe under autocommit: statements should use
// `IF NOT EXISTS` / `IF EXISTS` so a partial failure can be safely re-run.
const NO_TRANSACTION_MARKER = /^\s*--\s*migrate:no-transaction/im;

interface MigrationFile {
  id: string;
  upPath: string;
  downPath: string;
  upSql: string;
  downSql: string;
  checksum: string;
}

export class MigrationRunner {
  constructor(
    private readonly pool: Pool,
    private readonly migrationsDir = path.resolve(
      process.cwd(),
      "db/migrations",
    ),
  ) {}

  async up(): Promise<string[]> {
    await this.ensureMigrationTable();
    const migrations = await this.readMigrationFiles();
    const applied = await this.verifiedAppliedIds(migrations);
    const pending = migrations.filter(
      (migration) => !applied.has(migration.id),
    );
    const completed: string[] = [];

    for (const migration of pending) {
      const sql = migration.upSql;
      if (NO_TRANSACTION_MARKER.test(sql)) {
        await this.runNoTransactionSql(sql);
        await this.pool.query(
          `insert into ${migrationTable} (id, applied_at, checksum, checksum_origin) values ($1, now(), $2, 'applied')`,
          [migration.id, migration.checksum],
        );
        completed.push(migration.id);
        continue;
      }
      const client = await this.pool.connect();
      try {
        await client.query("begin");
        await client.query(sql);
        await client.query(
          `insert into ${migrationTable} (id, applied_at, checksum, checksum_origin) values ($1, now(), $2, 'applied')`,
          [migration.id, migration.checksum],
        );
        await client.query("commit");
        completed.push(migration.id);
      } catch (error) {
        await client.query("rollback");
        throw error;
      } finally {
        client.release();
      }
    }

    return completed;
  }

  async down(): Promise<string | null> {
    await this.ensureMigrationTable();
    const migrations = await this.readMigrationFiles();
    await this.verifiedAppliedIds(migrations);
    const latest = await this.pool.query<{ id: string }>(
      `select id from ${migrationTable} order by applied_at desc, id desc limit 1`,
    );

    const migrationId = latest.rows[0]?.id;
    if (!migrationId) return null;

    const migration = migrations.find((item) => item.id === migrationId);
    if (!migration)
      throw new Error(`Missing down migration for ${migrationId}`);

    const sql = migration.downSql;
    if (NO_TRANSACTION_MARKER.test(sql)) {
      await this.runNoTransactionSql(sql);
      await this.pool.query(`delete from ${migrationTable} where id = $1`, [
        migrationId,
      ]);
      return migrationId;
    }
    const client = await this.pool.connect();
    try {
      await client.query("begin");
      await client.query(sql);
      await client.query(`delete from ${migrationTable} where id = $1`, [
        migrationId,
      ]);
      await client.query("commit");
      return migrationId;
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }

  private async ensureMigrationTable() {
    await this.pool.query(`
      create table if not exists ${migrationTable} (
        id text primary key,
        applied_at timestamptz not null default now()
      )
    `);
    await this.pool.query(
      `alter table ${migrationTable} add column if not exists checksum text, add column if not exists checksum_origin text`,
    );
  }

  async manifest(): Promise<Record<string, string>> {
    return Object.fromEntries(
      (await this.readMigrationFiles()).map((item) => [item.id, item.checksum]),
    );
  }

  async baselineLegacy(manifest: Record<string, string>): Promise<string[]> {
    await this.ensureMigrationTable();
    const files = await this.readMigrationFiles();
    const applied = await this.pool.query<{
      id: string;
      checksum: string | null;
    }>(`select id, checksum from ${migrationTable}`);
    const pending: MigrationFile[] = [];
    for (const row of applied.rows) {
      const file = files.find((item) => item.id === row.id);
      if (
        !file ||
        (row.checksum && row.checksum !== file.checksum) ||
        (!row.checksum && manifest?.[row.id] !== file.checksum)
      )
        throw new Error(`Migration checksum baseline mismatch: ${row.id}`);
      if (!row.checksum) pending.push(file);
    }
    const client = await this.pool.connect();
    try {
      await client.query("begin");
      for (const file of pending)
        await client.query(
          `update ${migrationTable} set checksum=$2, checksum_origin='legacy_baseline' where id=$1 and checksum is null`,
          [file.id, file.checksum],
        );
      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
    return pending.map((item) => item.id);
  }

  private async verifiedAppliedIds(
    migrations: MigrationFile[],
  ): Promise<Set<string>> {
    const result = await this.pool.query<{
      id: string;
      checksum: string | null;
    }>(`select id, checksum from ${migrationTable}`);
    for (const row of result.rows) {
      const file = migrations.find((item) => item.id === row.id);
      if (!file) throw new Error(`Missing applied migration: ${row.id}`);
      if (!row.checksum)
        throw new Error(
          `Legacy migration checksum baseline required: ${row.id}. Review release SQL and run baseline with a verified manifest.`,
        );
      if (row.checksum !== file.checksum)
        throw new Error(
          `Migration checksum mismatch: ${row.id}. Restore the applied SQL and create a new migration.`,
        );
    }
    return new Set(result.rows.map((row) => row.id));
  }

  private async runNoTransactionSql(sql: string): Promise<void> {
    const statements = sql
      .split(";")
      .map((statement) => statement.trim())
      .filter((statement) => statement.length > 0);

    for (const statement of statements) {
      await this.pool.query(statement);
    }
  }

  private async readMigrationFiles(): Promise<MigrationFile[]> {
    const files = await fs.readdir(this.migrationsDir);
    const upFiles = files.filter((file) => file.endsWith(".up.sql")).sort();

    return Promise.all(
      upFiles.map(async (file) => {
        const id = file.replace(/\.up\.sql$/, "");
        const upSql = await fs.readFile(
          path.join(this.migrationsDir, file),
          "utf8",
        );
        const downSql = await fs.readFile(
          path.join(this.migrationsDir, `${id}.down.sql`),
          "utf8",
        );
        const checksum = createHash("sha256")
          .update(upSql.replace(/\r\n/g, "\n"))
          .update("\0")
          .update(downSql.replace(/\r\n/g, "\n"))
          .digest("hex");
        return {
          upSql,
          downSql,
          checksum,
          id,
          upPath: path.join(this.migrationsDir, file),
          downPath: path.join(this.migrationsDir, `${id}.down.sql`),
        };
      }),
    );
  }
}
