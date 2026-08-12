import { PGlite } from "@electric-sql/pglite";
import { readFile } from "fs/promises";
import { resolve } from "path";

describe("0122/0123 person lifecycle migrations", () => {
  it("protects history and refuses active work for archived people", async () => {
    const db = new PGlite();
    await db.exec(`
      create schema app;
      create table app.users (id uuid primary key);
      create table app.teachers (
        id uuid primary key, status text not null, deleted_at timestamptz,
        updated_at timestamptz not null default now()
      );
      create table app.staff_members (
        id uuid primary key, status text not null, deleted_at timestamptz,
        updated_at timestamptz not null default now()
      );
      create table app.teacher_branches (
        teacher_id uuid not null, active_from date not null default current_date,
        active_until date, version bigint not null default 1,
        updated_at timestamptz not null default now()
      );
      create table app.staff_branch_assignments (
        staff_member_id uuid not null, deleted_at timestamptz
      );
      create table app.lessons (
        teacher_id uuid, scheduled_at timestamptz not null,
        lifecycle_state text not null, deleted_at timestamptz
      );
      create table app.schedule_series (
        teacher_id uuid, valid_until date, superseded_by uuid,
        deleted_at timestamptz
      );
      insert into app.users (id) values
        ('10000000-0000-4000-8000-000000000001');
      insert into app.teachers (id, status) values
        ('20000000-0000-4000-8000-000000000001', 'active');
      insert into app.staff_members (id, status) values
        ('30000000-0000-4000-8000-000000000001', 'working');
    `);
    const lifecycleUp = await readFile(
      resolve(process.cwd(), "db/migrations/0122_person_access_lifecycle.up.sql"),
      "utf8",
    );
    const versionUp = await readFile(
      resolve(process.cwd(), "db/migrations/0123_teacher_lifecycle_version.up.sql"),
      "utf8",
    );
    await db.exec(lifecycleUp);
    await db.exec(versionUp);

    await db.exec(`
      update app.teachers set lifecycle_state = 'archived', status = 'inactive'
      where id = '20000000-0000-4000-8000-000000000001';
    `);
    await expect(
      db.exec(`
        insert into app.lessons (teacher_id, scheduled_at, lifecycle_state)
        values ('20000000-0000-4000-8000-000000000001', now() + interval '1 day', 'scheduled');
      `),
    ).rejects.toThrow("active scheduling reference requires an active teacher");
    await expect(
      db.exec(`
        insert into app.teacher_branches (teacher_id)
        values ('20000000-0000-4000-8000-000000000001');
      `),
    ).rejects.toThrow("active branch assignment requires an active teacher");

    await db.exec(`
      insert into app.person_lifecycle_history (
        person_type, person_id, operation, from_state, to_state, version,
        reason_text, actor_user_id, request_id, snapshot
      ) values (
        'teacher', '20000000-0000-4000-8000-000000000001', 'offboard',
        'active', 'archived', 2, 'Сотрудник уволен',
        '10000000-0000-4000-8000-000000000001', 'request-0001', '{}'::jsonb
      );
    `);
    await expect(
      db.exec("update app.person_lifecycle_history set reason_text = 'Подмена'"),
    ).rejects.toThrow("append-only");

    const teacherVersion = await db.query<{ version: number | string }>(
      "select version from app.teachers limit 1",
    );
    expect(Number(teacherVersion.rows[0].version)).toBe(1);
    const versionDown = await readFile(
      resolve(
        process.cwd(),
        "db/migrations/0123_teacher_lifecycle_version.down.sql",
      ),
      "utf8",
    );
    const lifecycleDown = await readFile(
      resolve(
        process.cwd(),
        "db/migrations/0122_person_access_lifecycle.down.sql",
      ),
      "utf8",
    );
    await db.exec(versionDown);
    await db.exec(lifecycleDown);
    const lifecycleColumns = await db.query<{ count: number | string }>(
      `select count(*) as count from information_schema.columns
       where table_schema = 'app' and table_name = 'teachers'
         and column_name in ('version', 'lifecycle_state')`,
    );
    expect(Number(lifecycleColumns.rows[0].count)).toBe(0);
    await db.close();
  }, 30_000);
});
