import { PGlite } from "@electric-sql/pglite";
import { readFile } from "fs/promises";
import { resolve } from "path";

describe("0119 branch lifecycle migration", () => {
  it("backfills tombstones, seeds aggregate versions and protects history", async () => {
    const db = new PGlite();
    await db.exec(`
      create schema app;
      create table app.users (id uuid primary key);
      create table app.branches (
        id uuid primary key default gen_random_uuid(),
        name text not null,
        address text,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),
        deleted_at timestamptz
      );
      create table app.aggregate_versions (
        aggregate_type text not null,
        aggregate_id text not null,
        version bigint not null,
        updated_at timestamptz not null default now(),
        primary key (aggregate_type, aggregate_id)
      );
      insert into app.branches (id, name) values
        ('10000000-0000-4000-8000-000000000001', 'Активный');
      insert into app.branches (id, name, deleted_at) values
        ('10000000-0000-4000-8000-000000000002', 'Старый архив', now());
    `);
    const up = await readFile(
      resolve(process.cwd(), "db/migrations/0119_branch_lifecycle.up.sql"),
      "utf8",
    );
    await db.exec(up);

    const branches = await db.query<{
      id: string;
      lifecycle_state: string;
      version: number | string;
    }>(
      `select id, lifecycle_state, version from app.branches order by id`,
    );
    expect(branches.rows).toEqual([
      expect.objectContaining({ lifecycle_state: "active", version: 1 }),
      expect.objectContaining({ lifecycle_state: "archived", version: 1 }),
    ]);
    const aggregates = await db.query<{ count: number | string }>(
      `select count(*) as count from app.aggregate_versions
       where aggregate_type = 'organization:branch'`,
    );
    expect(Number(aggregates.rows[0].count)).toBe(2);
    const history = await db.query<{ count: number | string }>(
      "select count(*) as count from app.branch_lifecycle_history",
    );
    expect(Number(history.rows[0].count)).toBe(1);
    await expect(
      db.exec(
        "update app.branch_lifecycle_history set reason_text = 'Подмена'",
      ),
    ).rejects.toThrow("append-only");

    const down = await readFile(
      resolve(process.cwd(), "db/migrations/0119_branch_lifecycle.down.sql"),
      "utf8",
    );
    await db.exec(down);
    const columns = await db.query<{ count: number | string }>(
      `select count(*) as count from information_schema.columns
       where table_schema = 'app' and table_name = 'branches'
         and column_name = 'lifecycle_state'`,
    );
    expect(Number(columns.rows[0].count)).toBe(0);
    await db.close();
  }, 30_000);
});
