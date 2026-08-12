import { PGlite } from "@electric-sql/pglite";
import { readFile } from "fs/promises";
import { resolve } from "path";

describe("0124 reference catalog lifecycle migration", () => {
  it("preserves snapshots, allows informational archival and rejects new archived references", async () => {
    const db = new PGlite();
    await db.exec(`
      create schema app;
      create table app.users (id uuid primary key);
      create table app.aggregate_versions (
        aggregate_type text not null,
        aggregate_id text not null,
        version bigint not null,
        updated_at timestamptz not null default now(),
        primary key (aggregate_type, aggregate_id)
      );
      create table app.branches (
        id uuid primary key,
        name text not null,
        lifecycle_state text not null default 'active',
        deleted_at timestamptz
      );
      create table app.students (
        id uuid primary key,
        branch_id uuid references app.branches(id),
        deleted_at timestamptz
      );
      create table app.teachers (
        id uuid primary key,
        status text not null default 'active',
        lifecycle_state text not null default 'active',
        deleted_at timestamptz
      );
      create table app.disciplines (
        id uuid primary key,
        name text not null,
        is_active boolean not null default true,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),
        deleted_at timestamptz
      );
      create unique index disciplines_name_idx
        on app.disciplines (lower(name)) where deleted_at is null;
      create table app.branch_disciplines (
        id uuid primary key,
        branch_id uuid not null references app.branches(id) on delete cascade,
        discipline_id uuid not null references app.disciplines(id) on delete cascade,
        sort_order integer not null default 0,
        created_at timestamptz not null default now(),
        deleted_at timestamptz,
        unique (branch_id, discipline_id)
      );
      create table app.student_disciplines (
        id uuid primary key default gen_random_uuid(),
        student_id uuid not null references app.students(id) on delete cascade,
        discipline_id uuid not null references app.disciplines(id) on delete cascade,
        is_primary boolean not null default false,
        created_at timestamptz not null default now(),
        deleted_at timestamptz,
        unique (student_id, discipline_id)
      );
      create table app.teacher_disciplines (
        id uuid primary key default gen_random_uuid(),
        teacher_id uuid not null references app.teachers(id) on delete cascade,
        discipline_id uuid not null references app.disciplines(id) on delete cascade,
        created_at timestamptz not null default now(),
        unique (teacher_id, discipline_id)
      );
      create table app.teacher_branches (
        id uuid primary key default gen_random_uuid(),
        teacher_id uuid not null references app.teachers(id) on delete cascade,
        branch_id uuid not null references app.branches(id) on delete cascade,
        active_from date not null default current_date,
        active_until date
      );
      create table app.subscription_packages (
        id uuid primary key,
        discipline_id uuid references app.disciplines(id),
        branch_id uuid references app.branches(id),
        is_active boolean not null default true,
        deleted_at timestamptz
      );
      create table app.subscription_package_versions (
        package_id uuid not null,
        version bigint not null,
        discipline_id uuid,
        branch_id uuid,
        primary key (package_id, version)
      );
      create table app.lead_loss_reasons (
        id uuid primary key,
        name text not null,
        kind text not null default 'lost',
        sort_order integer not null default 0,
        is_active boolean not null default true,
        color text,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),
        deleted_at timestamptz,
        constraint lead_loss_reasons_kind_check check (kind in ('lost', 'paused'))
      );
      create unique index lead_loss_reasons_name_kind_idx
        on app.lead_loss_reasons (lower(name), kind) where deleted_at is null;
      create table app.lead_status_history (
        id uuid primary key default gen_random_uuid(),
        lead_id uuid,
        reason_id uuid references app.lead_loss_reasons(id)
      );

      insert into app.users values ('10000000-0000-4000-8000-000000000001');
      insert into app.branches values (
        '20000000-0000-4000-8000-000000000001', 'Сокол', 'active', null
      );
      insert into app.students values (
        '30000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001', null
      );
      insert into app.teachers values (
        '40000000-0000-4000-8000-000000000001', 'active', 'active', null
      );
      insert into app.disciplines (
        id, name
      ) values (
        '50000000-0000-4000-8000-000000000001', 'Вокал'
      );
      insert into app.branch_disciplines (
        id, branch_id, discipline_id
      ) values (
        '60000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001',
        '50000000-0000-4000-8000-000000000001'
      );
      insert into app.student_disciplines (student_id, discipline_id) values (
        '30000000-0000-4000-8000-000000000001',
        '50000000-0000-4000-8000-000000000001'
      );
      insert into app.teacher_disciplines (teacher_id, discipline_id) values (
        '40000000-0000-4000-8000-000000000001',
        '50000000-0000-4000-8000-000000000001'
      );
      insert into app.teacher_branches (teacher_id, branch_id) values (
        '40000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001'
      );
      insert into app.subscription_packages values (
        '70000000-0000-4000-8000-000000000001',
        '50000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001', true, null
      );
      insert into app.subscription_package_versions values (
        '70000000-0000-4000-8000-000000000001', 1,
        '50000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001'
      );
      insert into app.lead_loss_reasons (id, name, kind) values (
        '80000000-0000-4000-8000-000000000001', 'Дорого', 'lost'
      );
      insert into app.lead_status_history (lead_id, reason_id) values (
        '90000000-0000-4000-8000-000000000001',
        '80000000-0000-4000-8000-000000000001'
      );
    `);

    const up = await readFile(
      resolve(process.cwd(), "db/migrations/0124_reference_catalog_lifecycle.up.sql"),
      "utf8",
    );
    await db.exec(up);

    const snapshot = await db.query<{
      reason_name_snapshot: string;
      reason_kind_snapshot: string;
    }>(
      `select reason_name_snapshot, reason_kind_snapshot
       from app.lead_status_history`,
    );
    expect(snapshot.rows[0]).toEqual({
      reason_name_snapshot: "Дорого",
      reason_kind_snapshot: "lost",
    });

    await expect(
      db.exec(`update app.lead_status_history
        set lead_id = '90000000-0000-4000-8000-000000000002'`),
    ).rejects.toThrow(/append-only/i);
    await db.exec(`
      select set_config('app.allow_lead_status_history_repoint', 'on', false);
      update app.lead_status_history
        set lead_id = '90000000-0000-4000-8000-000000000002';
      select set_config('app.allow_lead_status_history_repoint', 'off', false);
    `);

    await db.exec(`
      update app.branch_disciplines
        set lifecycle_state = 'archived', deleted_at = now(),
            archived_at = now(), archive_reason = 'Отвязка'
        where id = '60000000-0000-4000-8000-000000000001';
      update app.disciplines
        set lifecycle_state = 'archived', is_active = false,
            deleted_at = now(), archived_at = now(), archive_reason = 'Закрытие'
        where id = '50000000-0000-4000-8000-000000000001';
      insert into app.teachers values (
        '40000000-0000-4000-8000-000000000002', 'active', 'active', null
      );
    `);

    await expect(
      db.exec(`insert into app.teacher_disciplines (teacher_id, discipline_id) values (
        '40000000-0000-4000-8000-000000000002',
        '50000000-0000-4000-8000-000000000001'
      )`),
    ).rejects.toThrow(/active discipline/i);

    await db.exec(`
      update app.disciplines
        set lifecycle_state = 'active', is_active = true, deleted_at = null,
            archived_at = null, archive_reason = null;
      insert into app.subscription_packages values (
        '70000000-0000-4000-8000-000000000002',
        '50000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001', true, null
      );
      insert into app.teacher_disciplines (teacher_id, discipline_id) values (
        '40000000-0000-4000-8000-000000000002',
        '50000000-0000-4000-8000-000000000001'
      );
      insert into app.teacher_branches (teacher_id, branch_id) values (
        '40000000-0000-4000-8000-000000000002',
        '20000000-0000-4000-8000-000000000001'
      );
      insert into app.students values (
        '30000000-0000-4000-8000-000000000002',
        '20000000-0000-4000-8000-000000000001', null
      );
      insert into app.student_disciplines (student_id, discipline_id) values (
        '30000000-0000-4000-8000-000000000002',
        '50000000-0000-4000-8000-000000000001'
      );
      update app.branches
        set lifecycle_state = 'archived', deleted_at = now();
    `);
    await expect(
      db.exec(`update app.branch_disciplines
        set lifecycle_state = 'active', deleted_at = null,
            archived_at = null, archive_reason = null
        where id = '60000000-0000-4000-8000-000000000001'`),
    ).rejects.toThrow(/active branch/i);

    await db.exec(`update app.lead_loss_reasons
      set lifecycle_state = 'archived', is_active = false,
          deleted_at = now(), archived_at = now(), archive_reason = 'Больше не используем'
      where id = '80000000-0000-4000-8000-000000000001'`);
    await expect(
      db.exec(`insert into app.lead_status_history (reason_id) values (
        '80000000-0000-4000-8000-000000000001'
      )`),
    ).rejects.toThrow(/active loss reason/i);

    await db.exec(`insert into app.reference_catalog_history (
      entity_type, entity_id, operation, from_state, to_state, version,
      reason_text, request_id, snapshot
    ) values (
      'discipline', '50000000-0000-4000-8000-000000000001',
      'archive', 'active', 'archived', 2, 'Закрытие', 'request-0124', '{}'::jsonb
    )`);
    await expect(
      db.exec(`update app.reference_catalog_history set reason_text = 'rewrite'`),
    ).rejects.toThrow(/append-only/i);

    await db.exec(
      `select set_config('app.enforce_reference_physical_delete_guard', 'on', false)`,
    );
    await expect(
      db.exec(`delete from app.lead_loss_reasons where id =
        '80000000-0000-4000-8000-000000000001'`),
    ).rejects.toThrow(/archived instead of deleted/i);
    await db.exec(
      `select set_config('app.enforce_reference_physical_delete_guard', 'off', false)`,
    );

    const down = await readFile(
      resolve(process.cwd(), "db/migrations/0124_reference_catalog_lifecycle.down.sql"),
      "utf8",
    );
    await db.exec(down);
    const columns = await db.query<{ count: number | string }>(
      `select count(*) as count from information_schema.columns
       where table_schema = 'app'
         and table_name in ('disciplines', 'lead_loss_reasons', 'branch_disciplines')
         and column_name in ('lifecycle_state', 'version', 'archived_at')`,
    );
    expect(Number(columns.rows[0].count)).toBe(0);
    await db.close();
  }, 30_000);
});
