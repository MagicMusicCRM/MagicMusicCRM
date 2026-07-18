import { promises as fs } from 'node:fs';
import * as path from 'node:path';
import { Pool } from 'pg';

const migrationTable = 'app_schema_migrations';

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
}

export class MigrationRunner {
  constructor(
    private readonly pool: Pool,
    private readonly migrationsDir = path.resolve(process.cwd(), 'db/migrations')
  ) {}

  async up(): Promise<string[]> {
    await this.ensureMigrationTable();
    const migrations = await this.readMigrationFiles();
    const applied = await this.appliedIds();
    const pending = migrations.filter((migration) => !applied.has(migration.id));
    const completed: string[] = [];

    for (const migration of pending) {
      const sql = await fs.readFile(migration.upPath, 'utf8');
      if (NO_TRANSACTION_MARKER.test(sql)) {
        await this.runNoTransactionSql(sql);
        await this.pool.query(
          `insert into ${migrationTable} (id, applied_at) values ($1, now())`,
          [migration.id]
        );
        completed.push(migration.id);
        continue;
      }
      const client = await this.pool.connect();
      try {
        await client.query('begin');
        await client.query(sql);
        await client.query(
          `insert into ${migrationTable} (id, applied_at) values ($1, now())`,
          [migration.id]
        );
        await client.query('commit');
        completed.push(migration.id);
      } catch (error) {
        await client.query('rollback');
        throw error;
      } finally {
        client.release();
      }
    }

    return completed;
  }

  async down(): Promise<string | null> {
    await this.ensureMigrationTable();
    const latest = await this.pool.query<{ id: string }>(
      `select id from ${migrationTable} order by applied_at desc limit 1`
    );

    const migrationId = latest.rows[0]?.id;
    if (!migrationId) return null;

    const migrations = await this.readMigrationFiles();
    const migration = migrations.find((item) => item.id === migrationId);
    if (!migration) throw new Error(`Missing down migration for ${migrationId}`);

    const sql = await fs.readFile(migration.downPath, 'utf8');
    if (NO_TRANSACTION_MARKER.test(sql)) {
      await this.runNoTransactionSql(sql);
      await this.pool.query(`delete from ${migrationTable} where id = $1`, [
        migrationId
      ]);
      return migrationId;
    }
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      await client.query(sql);
      await client.query(`delete from ${migrationTable} where id = $1`, [
        migrationId
      ]);
      await client.query('commit');
      return migrationId;
    } catch (error) {
      await client.query('rollback');
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
  }

  private async appliedIds(): Promise<Set<string>> {
    const result = await this.pool.query<{ id: string }>(
      `select id from ${migrationTable}`
    );
    return new Set(result.rows.map((row) => row.id));
  }

  private async runNoTransactionSql(sql: string): Promise<void> {
    const statements = sql
      .split(';')
      .map((statement) => statement.trim())
      .filter((statement) => statement.length > 0);

    for (const statement of statements) {
      await this.pool.query(statement);
    }
  }

  private async readMigrationFiles(): Promise<MigrationFile[]> {
    const files = await fs.readdir(this.migrationsDir);
    const upFiles = files.filter((file) => file.endsWith('.up.sql')).sort();

    return upFiles.map((file) => {
      const id = file.replace(/\.up\.sql$/, '');
      return {
        id,
        upPath: path.join(this.migrationsDir, file),
        downPath: path.join(this.migrationsDir, `${id}.down.sql`)
      };
    });
  }
}
