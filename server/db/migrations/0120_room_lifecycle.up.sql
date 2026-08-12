alter table app.rooms
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists version bigint not null default 1,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references app.users(id) on delete set null,
  add column if not exists archive_reason text,
  add column if not exists archive_effective_date date;

update app.rooms
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

alter table app.rooms
  drop constraint if exists rooms_lifecycle_state_check,
  drop constraint if exists rooms_version_positive,
  drop constraint if exists rooms_lifecycle_consistency_check;

alter table app.rooms
  add constraint rooms_lifecycle_state_check
    check (lifecycle_state in ('active', 'archived')),
  add constraint rooms_version_positive check (version > 0),
  add constraint rooms_lifecycle_consistency_check check (
    (lifecycle_state = 'active' and deleted_at is null and archived_at is null
      and archive_effective_date is null)
    or
    (lifecycle_state = 'archived' and deleted_at is not null and archived_at is not null
      and archive_effective_date is not null)
  );

create index if not exists rooms_lifecycle_idx
  on app.rooms (branch_id, lifecycle_state, name, id);

create table if not exists app.room_lifecycle_history (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references app.rooms(id) on delete restrict,
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
  constraint room_lifecycle_history_operation_check
    check (operation in ('archive', 'restore', 'migration')),
  constraint room_lifecycle_history_state_check
    check (from_state in ('active', 'archived') and to_state in ('active', 'archived')),
  constraint room_lifecycle_history_version_positive check (version > 0),
  constraint room_lifecycle_history_reason_check
    check (nullif(btrim(reason_text), '') is not null and char_length(reason_text) <= 500),
  constraint room_lifecycle_history_request_check
    check (nullif(btrim(request_id), '') is not null and char_length(request_id) <= 160),
  constraint room_lifecycle_history_snapshot_check
    check (jsonb_typeof(snapshot) = 'object'),
  unique (room_id, version)
);

create index if not exists room_lifecycle_history_room_idx
  on app.room_lifecycle_history (room_id, created_at desc, id desc);

insert into app.room_lifecycle_history (
  room_id,
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
  room.id,
  'migration',
  'active',
  'archived',
  room.version,
  coalesce(room.archive_reason, 'Перенесено из прежнего архива'),
  room.archive_effective_date,
  'migration:0120:' || room.id::text,
  jsonb_build_object(
    'name', room.name,
    'branchId', room.branch_id,
    'capacity', room.capacity,
    'lifecycleState', room.lifecycle_state
  ),
  coalesce(room.archived_at, room.updated_at, room.created_at)
from app.rooms room
where room.lifecycle_state = 'archived'
on conflict (room_id, version) do nothing;

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'organization:room', room.id::text, room.version
from app.rooms room
on conflict (aggregate_type, aggregate_id) do update
set version = greatest(app.aggregate_versions.version, excluded.version),
    updated_at = now();

create or replace function app.reject_room_lifecycle_history_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'room_lifecycle_history is append-only';
end;
$$;

drop trigger if exists room_lifecycle_history_append_only
  on app.room_lifecycle_history;
create trigger room_lifecycle_history_append_only
before update or delete on app.room_lifecycle_history
for each row execute function app.reject_room_lifecycle_history_mutation();

create or replace function app.guard_room_parent_branch_active()
returns trigger
language plpgsql
as $$
declare
  parent_active boolean;
begin
  if new.branch_id is null or new.lifecycle_state <> 'active' then
    return new;
  end if;
  if TG_OP = 'UPDATE'
    and new.branch_id is not distinct from old.branch_id
    and new.lifecycle_state is not distinct from old.lifecycle_state
    and new.deleted_at is not distinct from old.deleted_at then
    return new;
  end if;

  select true into parent_active
  from app.branches branch
  where branch.id = new.branch_id
    and branch.lifecycle_state = 'active'
    and branch.deleted_at is null
  for share;
  if not coalesce(parent_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'rooms_active_parent_branch_required',
      message = 'active room requires an active parent branch';
  end if;
  return new;
end;
$$;

drop trigger if exists rooms_guard_active_parent_branch on app.rooms;
create trigger rooms_guard_active_parent_branch
before insert or update on app.rooms
for each row execute function app.guard_room_parent_branch_active();

create or replace function app.guard_active_room_reference()
returns trigger
language plpgsql
as $$
declare
  should_check boolean := false;
  room_active boolean;
begin
  if new.room_id is null then
    return new;
  end if;

  if TG_TABLE_NAME = 'groups' then
    should_check := new.deleted_at is null;
  elsif TG_TABLE_NAME = 'lessons' then
    should_check := new.deleted_at is null
      and new.scheduled_at >= now()
      and new.lifecycle_state in ('scheduled', 'settlement_pending');
  elsif TG_TABLE_NAME = 'schedule_series' then
    should_check := new.deleted_at is null
      and new.superseded_by is null
      and (new.valid_until is null or new.valid_until >= current_date);
  end if;

  if not should_check then
    return new;
  end if;
  select true into room_active
  from app.rooms room
  where room.id = new.room_id
    and room.lifecycle_state = 'active'
    and room.deleted_at is null
  for share;
  if not coalesce(room_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'active_room_reference_required',
      message = 'active scheduling reference requires an active room';
  end if;
  return new;
end;
$$;

drop trigger if exists groups_guard_active_room on app.groups;
create trigger groups_guard_active_room
before insert or update on app.groups
for each row execute function app.guard_active_room_reference();

drop trigger if exists lessons_guard_active_room on app.lessons;
create trigger lessons_guard_active_room
before insert or update on app.lessons
for each row execute function app.guard_active_room_reference();

drop trigger if exists schedule_series_guard_active_room on app.schedule_series;
create trigger schedule_series_guard_active_room
before insert or update on app.schedule_series
for each row execute function app.guard_active_room_reference();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.room_lifecycle_history to magiccrm_app;
  end if;
end $$;
