import { PGlite } from "@electric-sql/pglite";
import { readFile } from "fs/promises";
import { resolve } from "path";

describe("0120 room lifecycle migration", () => {
  it("backfills tombstones, seeds aggregate versions and protects history", async () => {
    const db = new PGlite();
    await db.exec(`
      create schema app;
      create table app.users (id uuid primary key);
      create table app.branches (
        id uuid primary key,
        lifecycle_state text not null default 'active',
        deleted_at timestamptz
      );
      create table app.rooms (
        id uuid primary key default gen_random_uuid(),
        branch_id uuid references app.branches(id),
        name text not null,
        capacity integer,
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
      create table app.groups (
        id uuid primary key default gen_random_uuid(),
        room_id uuid references app.rooms(id),
        deleted_at timestamptz
      );
      create table app.lessons (
        id uuid primary key default gen_random_uuid(),
        room_id uuid references app.rooms(id),
        scheduled_at timestamptz not null default now(),
        lifecycle_state text not null default 'scheduled',
        deleted_at timestamptz
      );
      create table app.schedule_series (
        id uuid primary key default gen_random_uuid(),
        room_id uuid references app.rooms(id),
        valid_until date,
        superseded_by uuid,
        deleted_at timestamptz
      );
      insert into app.branches (id) values
        ('30000000-0000-4000-8000-000000000001');
      insert into app.branches (id, lifecycle_state, deleted_at) values
        ('30000000-0000-4000-8000-000000000002', 'archived', now());
      insert into app.rooms (id, name) values
        ('20000000-0000-4000-8000-000000000001', 'Активная');
      insert into app.rooms (id, name, deleted_at) values
        ('20000000-0000-4000-8000-000000000002', 'Старый архив', now());
    `);
    const up = await readFile(
      resolve(process.cwd(), "db/migrations/0120_room_lifecycle.up.sql"),
      "utf8",
    );
    await db.exec(up);

    const rooms = await db.query<{
      id: string;
      lifecycle_state: string;
      version: number | string;
    }>(`select id, lifecycle_state, version from app.rooms order by id`);
    expect(rooms.rows).toEqual([
      expect.objectContaining({ lifecycle_state: "active", version: 1 }),
      expect.objectContaining({ lifecycle_state: "archived", version: 1 }),
    ]);
    const aggregates = await db.query<{ count: number | string }>(
      `select count(*) as count from app.aggregate_versions
       where aggregate_type = 'organization:room'`,
    );
    expect(Number(aggregates.rows[0].count)).toBe(2);
    const history = await db.query<{ count: number | string }>(
      "select count(*) as count from app.room_lifecycle_history",
    );
    expect(Number(history.rows[0].count)).toBe(1);
    await expect(
      db.exec("update app.room_lifecycle_history set reason_text = 'Подмена'"),
    ).rejects.toThrow("append-only");

    await db.exec(`
      update app.rooms
      set branch_id = '30000000-0000-4000-8000-000000000001'
      where id = '20000000-0000-4000-8000-000000000001';
      update app.rooms
      set lifecycle_state = 'archived', deleted_at = now(), archived_at = now(),
          archive_effective_date = current_date, archive_reason = 'Ремонт'
      where id = '20000000-0000-4000-8000-000000000001';
    `);
    await expect(
      db.exec(`
        insert into app.groups (room_id)
        values ('20000000-0000-4000-8000-000000000001')
      `),
    ).rejects.toThrow("active scheduling reference requires an active room");
    await expect(
      db.exec(`
        insert into app.rooms (name, branch_id)
        values ('Нельзя восстановить здесь', '30000000-0000-4000-8000-000000000002')
      `),
    ).rejects.toThrow("active room requires an active parent branch");

    const down = await readFile(
      resolve(process.cwd(), "db/migrations/0120_room_lifecycle.down.sql"),
      "utf8",
    );
    await db.exec(down);
    const columns = await db.query<{ count: number | string }>(
      `select count(*) as count from information_schema.columns
       where table_schema = 'app' and table_name = 'rooms'
         and column_name = 'lifecycle_state'`,
    );
    expect(Number(columns.rows[0].count)).toBe(0);
    await db.close();
  }, 30_000);
});
