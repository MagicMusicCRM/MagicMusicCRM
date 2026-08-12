import { PGlite } from "@electric-sql/pglite";
import { readFile } from "fs/promises";
import { resolve } from "path";

describe("0121 group lifecycle migration", () => {
  it("preserves history and prevents archived or inconsistent scheduling writes", async () => {
    const db = new PGlite();
    await db.exec(`
      create schema app;
      create table app.users (id uuid primary key);
      create table app.profiles (
        id uuid primary key,
        first_name text,
        last_name text
      );
      create table app.branches (
        id uuid primary key,
        lifecycle_state text not null default 'active',
        deleted_at timestamptz,
        timezone_name text
      );
      create table app.rooms (
        id uuid primary key,
        branch_id uuid references app.branches(id),
        lifecycle_state text not null default 'active',
        deleted_at timestamptz
      );
      create table app.teachers (
        id uuid primary key,
        profile_id uuid references app.profiles(id),
        status text not null default 'active',
        deleted_at timestamptz
      );
      create table app.teacher_branches (
        teacher_id uuid not null references app.teachers(id),
        branch_id uuid not null references app.branches(id),
        active_from date not null,
        active_until date
      );
      create table app.groups (
        id uuid primary key default gen_random_uuid(),
        teacher_id uuid references app.teachers(id),
        branch_id uuid references app.branches(id),
        room_id uuid references app.rooms(id),
        name text not null,
        price_per_lesson numeric,
        teacher_rate numeric,
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
      create table app.group_students (
        id uuid primary key default gen_random_uuid(),
        group_id uuid not null references app.groups(id),
        student_id uuid not null,
        joined_at timestamptz not null default now(),
        left_at timestamptz
      );
      create table app.lessons (
        id uuid primary key default gen_random_uuid(),
        group_id uuid references app.groups(id),
        scheduled_at timestamptz not null default now(),
        lifecycle_state text not null default 'scheduled',
        deleted_at timestamptz
      );
      create table app.schedule_series (
        id uuid primary key default gen_random_uuid(),
        group_id uuid references app.groups(id),
        valid_until date,
        superseded_by uuid,
        deleted_at timestamptz
      );
      create table app.schedule_plans (
        id uuid primary key default gen_random_uuid(),
        group_id uuid references app.groups(id),
        status text not null default 'active'
      );

      insert into app.branches (id) values
        ('30000000-0000-4000-8000-000000000001');
      insert into app.rooms (id, branch_id) values
        ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001'),
        ('20000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001');
      insert into app.profiles (id) values
        ('50000000-0000-4000-8000-000000000001');
      insert into app.teachers (id, profile_id) values
        ('40000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001');
      insert into app.teacher_branches (teacher_id, branch_id, active_from) values
        ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', current_date - 1);
      insert into app.groups (id, teacher_id, branch_id, room_id, name) values
        ('10000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Активная');
      insert into app.groups (id, teacher_id, branch_id, room_id, name, deleted_at) values
        ('10000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Старый архив', now());
    `);
    const up = await readFile(
      resolve(process.cwd(), "db/migrations/0121_group_lifecycle.up.sql"),
      "utf8",
    );
    await db.exec(up);

    const groups = await db.query<{
      lifecycle_state: string;
      version: number | string;
    }>(`select lifecycle_state, version from app.groups order by id`);
    expect(groups.rows).toEqual([
      expect.objectContaining({ lifecycle_state: "active", version: 1 }),
      expect.objectContaining({ lifecycle_state: "archived", version: 1 }),
    ]);
    const aggregates = await db.query<{ count: number | string }>(
      `select count(*) as count from app.aggregate_versions
       where aggregate_type = 'organization:group'`,
    );
    expect(Number(aggregates.rows[0].count)).toBe(2);
    const history = await db.query<{ count: number | string }>(
      "select count(*) as count from app.group_lifecycle_history",
    );
    expect(Number(history.rows[0].count)).toBe(1);
    await expect(
      db.exec("update app.group_lifecycle_history set reason_text = 'Подмена'"),
    ).rejects.toThrow("append-only");
    await expect(
      db.exec(
        "set app.enforce_group_physical_delete_guard = 'on'; " +
          "delete from app.groups where id = '10000000-0000-4000-8000-000000000001'",
      ),
    ).rejects.toThrow("archived instead of deleted");
    await db.exec("reset app.enforce_group_physical_delete_guard");
    await db.exec(`
      insert into app.groups (id, name) values
        ('10000000-0000-4000-8000-000000000003', 'Неполный импорт');
    `);

    await db.exec(`
      update app.groups
      set lifecycle_state = 'archived', deleted_at = now(), archived_at = now(),
          archive_effective_date = current_date, archive_reason = 'Группа завершена'
      where id = '10000000-0000-4000-8000-000000000001';
    `);
    await expect(
      db.exec(`
        insert into app.lessons (group_id, scheduled_at)
        values ('10000000-0000-4000-8000-000000000001', now() + interval '1 day')
      `),
    ).rejects.toThrow("active scheduling reference requires an active group");
    await expect(
      db.exec(`
        insert into app.group_students (group_id, student_id)
        values ('10000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000001')
      `),
    ).rejects.toThrow("membership can only change for an active group");

    await db.exec(`
      update app.groups
      set lifecycle_state = 'active', deleted_at = null, archived_at = null,
          archive_effective_date = null, archive_reason = null
      where id = '10000000-0000-4000-8000-000000000001';
      insert into app.lessons (group_id, scheduled_at)
      values ('10000000-0000-4000-8000-000000000001', now() + interval '1 day');
    `);
    await expect(
      db.exec(`
        update app.groups set room_id = '20000000-0000-4000-8000-000000000002'
        where id = '10000000-0000-4000-8000-000000000001'
      `),
    ).rejects.toThrow("assignment cannot change");

    const down = await readFile(
      resolve(process.cwd(), "db/migrations/0121_group_lifecycle.down.sql"),
      "utf8",
    );
    await db.exec(down);
    const columns = await db.query<{ count: number | string }>(
      `select count(*) as count from information_schema.columns
       where table_schema = 'app' and table_name = 'groups'
         and column_name = 'lifecycle_state'`,
    );
    expect(Number(columns.rows[0].count)).toBe(0);
    await db.close();
  }, 30_000);
});
