-- server/db/migrations/0026_crm_dictionaries.up.sql
-- CRM dictionaries: loss reasons, lead sources, disciplines (+ per-branch order,
-- per-student primary), and terminal/requires-reason flags on lead statuses.

create table if not exists app.lead_loss_reasons (
  id uuid primary key default gen_random_uuid(),
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
create unique index if not exists lead_loss_reasons_name_kind_idx
  on app.lead_loss_reasons (lower(name), kind) where deleted_at is null;

alter table app.lead_statuses add column if not exists is_terminal boolean not null default false;
alter table app.lead_statuses add column if not exists requires_reason boolean not null default false;

create table if not exists app.lead_sources (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  display_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index if not exists lead_sources_canonical_idx
  on app.lead_sources (lower(canonical_name)) where deleted_at is null;

create table if not exists app.disciplines (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create unique index if not exists disciplines_name_idx
  on app.disciplines (lower(name)) where deleted_at is null;

create table if not exists app.branch_disciplines (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references app.branches(id) on delete cascade,
  discipline_id uuid not null references app.disciplines(id) on delete cascade,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint branch_disciplines_unique unique (branch_id, discipline_id)
);
create index if not exists branch_disciplines_branch_idx
  on app.branch_disciplines (branch_id, sort_order) where deleted_at is null;

create table if not exists app.student_disciplines (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  discipline_id uuid not null references app.disciplines(id) on delete cascade,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint student_disciplines_unique unique (student_id, discipline_id)
);
create unique index if not exists student_disciplines_one_primary_idx
  on app.student_disciplines (student_id) where is_primary and deleted_at is null;

-- Seed loss/pause reasons (idempotent: only when table empty).
insert into app.lead_loss_reasons (name, kind, sort_order)
select name, kind, sort_order
from (values
  ('Дорого', 'lost', 1),
  ('Неудобное расписание', 'lost', 2),
  ('Нет нужного преподавателя', 'lost', 3),
  ('Выбрали конкурента', 'lost', 4),
  ('Не отвечает', 'lost', 5),
  ('Передумал', 'lost', 6),
  ('Дубль', 'lost', 7),
  ('Нецелевой лид', 'lost', 8),
  ('Филиал далеко', 'lost', 9),
  ('Пауза (семейные обстоятельства)', 'paused', 10),
  ('Другое', 'lost', 99)
) as v(name, kind, sort_order)
where not exists (select 1 from app.lead_loss_reasons);

-- Seed lead sources (idempotent: only when table empty).
insert into app.lead_sources (canonical_name, display_name, is_active)
select canonical_name, display_name, true
from (values
  ('site', 'Сайт'),
  ('ads', 'Реклама'),
  ('referral', 'Рекомендации'),
  ('social', 'Соцсети'),
  ('messenger', 'Мессенджер'),
  ('call', 'Звонок'),
  ('offline', 'Офлайн'),
  ('partners', 'Партнёры'),
  ('repeat', 'Повторное обращение'),
  ('app', 'Через приложение'),
  ('chat', 'Чат')
) as v(canonical_name, display_name)
where not exists (select 1 from app.lead_sources);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.lead_loss_reasons to magiccrm_app;
    grant select, insert, update, delete on app.lead_sources to magiccrm_app;
    grant select, insert, update, delete on app.disciplines to magiccrm_app;
    grant select, insert, update, delete on app.branch_disciplines to magiccrm_app;
    grant select, insert, update, delete on app.student_disciplines to magiccrm_app;
  end if;
end $$;
