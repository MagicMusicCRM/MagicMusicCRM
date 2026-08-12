alter table app.branches
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists version bigint not null default 1,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references app.users(id) on delete set null,
  add column if not exists archive_reason text,
  add column if not exists archive_effective_date date;

update app.branches
set lifecycle_state = case when deleted_at is null then 'active' else 'archived' end,
    archived_at = case when deleted_at is null then null else coalesce(archived_at, deleted_at) end,
    archive_effective_date = case
      when deleted_at is null then null
      else coalesce(archive_effective_date, deleted_at::date)
    end,
    archive_reason = case
      when deleted_at is null then null
      else coalesce(archive_reason, 'Перенесено из прежнего архива')
    end;

alter table app.branches
  drop constraint if exists branches_lifecycle_state_check,
  drop constraint if exists branches_version_positive,
  drop constraint if exists branches_lifecycle_consistency_check;

alter table app.branches
  add constraint branches_lifecycle_state_check
    check (lifecycle_state in ('active', 'archived')),
  add constraint branches_version_positive check (version > 0),
  add constraint branches_lifecycle_consistency_check check (
    (lifecycle_state = 'active' and deleted_at is null and archived_at is null
      and archive_effective_date is null)
    or
    (lifecycle_state = 'archived' and deleted_at is not null and archived_at is not null
      and archive_effective_date is not null)
  );

create index if not exists branches_lifecycle_idx
  on app.branches (lifecycle_state, name, id);

create table if not exists app.branch_lifecycle_history (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references app.branches(id) on delete restrict,
  operation text not null,
  from_state text not null,
  to_state text not null,
  version bigint not null,
  reason_text text not null,
  effective_date date not null,
  actor_user_id uuid references app.users(id) on delete set null,
  request_id text not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now(),
  constraint branch_lifecycle_history_operation_check
    check (operation in ('archive', 'restore', 'migration')),
  constraint branch_lifecycle_history_state_check
    check (from_state in ('active', 'archived') and to_state in ('active', 'archived')),
  constraint branch_lifecycle_history_version_positive check (version > 0),
  constraint branch_lifecycle_history_reason_check
    check (nullif(btrim(reason_text), '') is not null and char_length(reason_text) <= 500),
  constraint branch_lifecycle_history_request_check
    check (nullif(btrim(request_id), '') is not null and char_length(request_id) <= 160),
  constraint branch_lifecycle_history_snapshot_check
    check (jsonb_typeof(snapshot) = 'object'),
  unique (branch_id, version)
);

create index if not exists branch_lifecycle_history_branch_idx
  on app.branch_lifecycle_history (branch_id, created_at desc, id desc);

insert into app.branch_lifecycle_history (
  branch_id,
  operation,
  from_state,
  to_state,
  version,
  reason_text,
  effective_date,
  request_id,
  snapshot,
  created_at
)
select
  branch.id,
  'migration',
  'active',
  'archived',
  branch.version,
  coalesce(branch.archive_reason, 'Перенесено из прежнего архива'),
  branch.archive_effective_date,
  'migration:0119:' || branch.id::text,
  jsonb_build_object(
    'name', branch.name,
    'address', branch.address,
    'lifecycleState', branch.lifecycle_state
  ),
  coalesce(branch.archived_at, branch.updated_at, branch.created_at)
from app.branches branch
where branch.lifecycle_state = 'archived'
on conflict (branch_id, version) do nothing;

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'organization:branch', branch.id::text, branch.version
from app.branches branch
on conflict (aggregate_type, aggregate_id) do update
set version = greatest(app.aggregate_versions.version, excluded.version),
    updated_at = now();

create or replace function app.reject_branch_lifecycle_history_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'branch_lifecycle_history is append-only';
end;
$$;

drop trigger if exists branch_lifecycle_history_append_only
  on app.branch_lifecycle_history;
create trigger branch_lifecycle_history_append_only
before update or delete on app.branch_lifecycle_history
for each row execute function app.reject_branch_lifecycle_history_mutation();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.branch_lifecycle_history to magiccrm_app;
  end if;
end $$;
