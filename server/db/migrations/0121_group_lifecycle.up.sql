alter table app.groups
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists version bigint not null default 1,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references app.users(id) on delete set null,
  add column if not exists archive_reason text,
  add column if not exists archive_effective_date date;

update app.groups
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

alter table app.groups
  drop constraint if exists groups_lifecycle_state_check,
  drop constraint if exists groups_version_positive,
  drop constraint if exists groups_lifecycle_consistency_check;

alter table app.groups
  add constraint groups_lifecycle_state_check
    check (lifecycle_state in ('active', 'archived')),
  add constraint groups_version_positive check (version > 0),
  add constraint groups_lifecycle_consistency_check check (
    (lifecycle_state = 'active' and deleted_at is null and archived_at is null
      and archive_effective_date is null)
    or
    (lifecycle_state = 'archived' and deleted_at is not null and archived_at is not null
      and archive_effective_date is not null)
  );

create index if not exists groups_lifecycle_idx
  on app.groups (branch_id, lifecycle_state, name, id);

create table if not exists app.group_lifecycle_history (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references app.groups(id) on delete restrict,
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
  constraint group_lifecycle_history_operation_check
    check (operation in ('archive', 'restore', 'migration')),
  constraint group_lifecycle_history_state_check
    check (from_state in ('active', 'archived') and to_state in ('active', 'archived')),
  constraint group_lifecycle_history_version_positive check (version > 0),
  constraint group_lifecycle_history_reason_check
    check (nullif(btrim(reason_text), '') is not null and char_length(reason_text) <= 500),
  constraint group_lifecycle_history_request_check
    check (nullif(btrim(request_id), '') is not null and char_length(request_id) <= 160),
  constraint group_lifecycle_history_snapshot_check
    check (jsonb_typeof(snapshot) = 'object'),
  unique (group_id, version)
);

create index if not exists group_lifecycle_history_group_idx
  on app.group_lifecycle_history (group_id, created_at desc, id desc);

insert into app.group_lifecycle_history (
  group_id, operation, from_state, to_state, version, reason_text,
  effective_date, request_id, snapshot, created_at
)
select
  target.id,
  'migration',
  'active',
  'archived',
  target.version,
  coalesce(target.archive_reason, 'Перенесено из прежнего архива'),
  target.archive_effective_date,
  'migration:0121:' || target.id::text,
  jsonb_build_object(
    'name', target.name,
    'teacherId', target.teacher_id,
    'branchId', target.branch_id,
    'roomId', target.room_id,
    'lifecycleState', target.lifecycle_state
  ),
  coalesce(target.archived_at, target.updated_at, target.created_at)
from app.groups target
where target.lifecycle_state = 'archived'
on conflict (group_id, version) do nothing;

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'organization:group', target.id::text, target.version
from app.groups target
on conflict (aggregate_type, aggregate_id) do update
set version = greatest(app.aggregate_versions.version, excluded.version),
    updated_at = now();

create or replace function app.reject_group_lifecycle_history_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'group_lifecycle_history is append-only';
end;
$$;

drop trigger if exists group_lifecycle_history_append_only
  on app.group_lifecycle_history;
create trigger group_lifecycle_history_append_only
before update or delete on app.group_lifecycle_history
for each row execute function app.reject_group_lifecycle_history_mutation();

create or replace function app.reject_group_physical_delete()
returns trigger
language plpgsql
as $$
begin
  if current_user <> 'magiccrm_app'
    and current_setting('app.enforce_group_physical_delete_guard', true)
      is distinct from 'on' then
    return old;
  end if;
  raise exception using
    errcode = '23514',
    constraint = 'groups_archive_instead_of_delete',
    message = 'groups must be archived instead of deleted';
end;
$$;

drop trigger if exists groups_reject_physical_delete on app.groups;
create trigger groups_reject_physical_delete
before delete on app.groups
for each row execute function app.reject_group_physical_delete();

create or replace function app.guard_group_active_references()
returns trigger
language plpgsql
as $$
declare
  parent_branch_active boolean;
  parent_room_active boolean;
  teacher_assignment_active boolean;
begin
  if new.lifecycle_state <> 'active' or new.deleted_at is not null then
    return new;
  end if;
  if TG_OP = 'UPDATE'
    and new.teacher_id is not distinct from old.teacher_id
    and new.branch_id is not distinct from old.branch_id
    and new.room_id is not distinct from old.room_id
    and new.lifecycle_state is not distinct from old.lifecycle_state
    and new.deleted_at is not distinct from old.deleted_at then
    return new;
  end if;

  select true into parent_branch_active
  from app.branches branch
  where branch.id = new.branch_id
    and branch.lifecycle_state = 'active'
    and branch.deleted_at is null
  for share;
  if not coalesce(parent_branch_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'groups_active_parent_branch_required',
      message = 'active group requires an active parent branch';
  end if;

  select true into parent_room_active
  from app.rooms room
  where room.id = new.room_id
    and room.branch_id = new.branch_id
    and room.lifecycle_state = 'active'
    and room.deleted_at is null
  for share;
  if not coalesce(parent_room_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'groups_active_room_required',
      message = 'active group requires an active room in its branch';
  end if;

  select true into teacher_assignment_active
  from app.teachers teacher
  join app.teacher_branches assignment
    on assignment.teacher_id = teacher.id
   and assignment.branch_id = new.branch_id
   and assignment.active_from <= current_date
   and (assignment.active_until is null or assignment.active_until >= current_date)
  where teacher.id = new.teacher_id
    and teacher.deleted_at is null
    and lower(teacher.status) in ('active', 'working', 'активен', 'работает')
  for share of teacher, assignment;
  if not coalesce(teacher_assignment_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'groups_active_teacher_assignment_required',
      message = 'active group requires an active teacher assigned to its branch';
  end if;
  return new;
end;
$$;

drop trigger if exists groups_guard_active_references on app.groups;
create trigger groups_guard_active_references
before update of teacher_id, branch_id, room_id, lifecycle_state, deleted_at on app.groups
for each row execute function app.guard_group_active_references();

create or replace function app.guard_active_group_schedule_reference()
returns trigger
language plpgsql
as $$
declare
  should_check boolean := false;
  group_active boolean;
begin
  if new.group_id is null then
    return new;
  end if;
  if TG_TABLE_NAME = 'lessons' then
    should_check := new.deleted_at is null
      and new.scheduled_at >= now()
      and new.lifecycle_state in ('scheduled', 'settlement_pending');
  elsif TG_TABLE_NAME = 'schedule_series' then
    should_check := new.deleted_at is null
      and new.superseded_by is null
      and (new.valid_until is null or new.valid_until >= current_date);
  elsif TG_TABLE_NAME = 'schedule_plans' then
    should_check := new.status = 'active';
  end if;
  if not should_check then
    return new;
  end if;

  select true into group_active
  from app.groups target
  where target.id = new.group_id
    and target.lifecycle_state = 'active'
    and target.deleted_at is null
  for share;
  if not coalesce(group_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'active_group_schedule_reference_required',
      message = 'active scheduling reference requires an active group';
  end if;
  return new;
end;
$$;

drop trigger if exists lessons_guard_active_group on app.lessons;
create trigger lessons_guard_active_group
before insert or update on app.lessons
for each row execute function app.guard_active_group_schedule_reference();

drop trigger if exists schedule_series_guard_active_group on app.schedule_series;
create trigger schedule_series_guard_active_group
before insert or update on app.schedule_series
for each row execute function app.guard_active_group_schedule_reference();

drop trigger if exists schedule_plans_guard_active_group on app.schedule_plans;
create trigger schedule_plans_guard_active_group
before insert or update on app.schedule_plans
for each row execute function app.guard_active_group_schedule_reference();

create or replace function app.guard_group_membership_parent_active()
returns trigger
language plpgsql
as $$
declare
  target_group_id uuid;
  group_active boolean;
begin
  target_group_id := case when TG_OP = 'DELETE' then old.group_id else new.group_id end;
  select true into group_active
  from app.groups target
  where target.id = target_group_id
    and target.lifecycle_state = 'active'
    and target.deleted_at is null
  for share;
  if not coalesce(group_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'group_membership_active_parent_required',
      message = 'group membership can only change for an active group';
  end if;
  if TG_OP = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists group_students_guard_active_group on app.group_students;
create trigger group_students_guard_active_group
before insert or update or delete on app.group_students
for each row execute function app.guard_group_membership_parent_active();

create or replace function app.guard_group_assignment_change()
returns trigger
language plpgsql
as $$
begin
  if new.lifecycle_state <> 'active'
    or new.deleted_at is not null
    or (
      new.teacher_id is not distinct from old.teacher_id
      and new.branch_id is not distinct from old.branch_id
      and new.room_id is not distinct from old.room_id
    ) then
    return new;
  end if;
  if exists (
    select 1 from app.lessons item
    where item.group_id = old.id and item.deleted_at is null
      and item.scheduled_at >= now()
      and item.lifecycle_state in ('scheduled', 'settlement_pending')
  ) or exists (
    select 1 from app.schedule_series item
    where item.group_id = old.id and item.deleted_at is null
      and item.superseded_by is null
      and (item.valid_until is null or item.valid_until >= current_date)
  ) or exists (
    select 1 from app.schedule_plans item
    where item.group_id = old.id and item.status = 'active'
  ) then
    raise exception using
      errcode = '23514',
      constraint = 'group_assignment_change_requires_remediation',
      message = 'group assignment cannot change while active schedule references exist';
  end if;
  return new;
end;
$$;

drop trigger if exists groups_guard_assignment_change on app.groups;
create trigger groups_guard_assignment_change
before update on app.groups
for each row execute function app.guard_group_assignment_change();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.group_lifecycle_history to magiccrm_app;
  end if;
end $$;
