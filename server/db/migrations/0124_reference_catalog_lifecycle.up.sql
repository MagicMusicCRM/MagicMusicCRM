-- Reversible lifecycle for school disciplines, branch-discipline links and
-- lead loss reasons. Historical references remain attached to the same UUID;
-- active consumers must be remediated before an archive/unassign transition.

alter table app.disciplines
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists version bigint not null default 1,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references app.users(id) on delete set null,
  add column if not exists archive_reason text;

update app.disciplines
set lifecycle_state = case
      when deleted_at is null and is_active then 'active'
      else 'archived'
    end,
    is_active = deleted_at is null and is_active,
    deleted_at = case
      when deleted_at is null and is_active then null
      else coalesce(deleted_at, updated_at, created_at, now())
    end,
    archived_at = case
      when deleted_at is null and is_active then null
      else coalesce(archived_at, deleted_at, updated_at, created_at, now())
    end,
    archive_reason = case
      when deleted_at is null and is_active then null
      else coalesce(archive_reason, 'Перенесено из прежнего архива')
    end;

alter table app.disciplines
  drop constraint if exists disciplines_lifecycle_state_check,
  drop constraint if exists disciplines_version_positive,
  drop constraint if exists disciplines_name_not_blank,
  drop constraint if exists disciplines_lifecycle_consistency_check;
alter table app.disciplines
  add constraint disciplines_lifecycle_state_check
    check (lifecycle_state in ('active', 'archived')),
  add constraint disciplines_version_positive check (version > 0),
  add constraint disciplines_name_not_blank
    check (nullif(btrim(name), '') is not null and char_length(name) <= 120),
  add constraint disciplines_lifecycle_consistency_check check (
    (lifecycle_state = 'active' and is_active and deleted_at is null
      and archived_at is null and archive_reason is null)
    or
    (lifecycle_state = 'archived' and not is_active and deleted_at is not null
      and archived_at is not null and nullif(btrim(archive_reason), '') is not null)
  );

alter table app.lead_loss_reasons
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists version bigint not null default 1,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references app.users(id) on delete set null,
  add column if not exists archive_reason text;

update app.lead_loss_reasons
set lifecycle_state = case
      when deleted_at is null and is_active then 'active'
      else 'archived'
    end,
    is_active = deleted_at is null and is_active,
    deleted_at = case
      when deleted_at is null and is_active then null
      else coalesce(deleted_at, updated_at, created_at, now())
    end,
    archived_at = case
      when deleted_at is null and is_active then null
      else coalesce(archived_at, deleted_at, updated_at, created_at, now())
    end,
    archive_reason = case
      when deleted_at is null and is_active then null
      else coalesce(archive_reason, 'Перенесено из прежнего архива')
    end;

alter table app.lead_loss_reasons
  drop constraint if exists lead_loss_reasons_lifecycle_state_check,
  drop constraint if exists lead_loss_reasons_version_positive,
  drop constraint if exists lead_loss_reasons_name_not_blank,
  drop constraint if exists lead_loss_reasons_lifecycle_consistency_check;
alter table app.lead_loss_reasons
  add constraint lead_loss_reasons_lifecycle_state_check
    check (lifecycle_state in ('active', 'archived')),
  add constraint lead_loss_reasons_version_positive check (version > 0),
  add constraint lead_loss_reasons_name_not_blank
    check (nullif(btrim(name), '') is not null and char_length(name) <= 120),
  add constraint lead_loss_reasons_lifecycle_consistency_check check (
    (lifecycle_state = 'active' and is_active and deleted_at is null
      and archived_at is null and archive_reason is null)
    or
    (lifecycle_state = 'archived' and not is_active and deleted_at is not null
      and archived_at is not null and nullif(btrim(archive_reason), '') is not null)
  );

alter table app.branch_disciplines
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists version bigint not null default 1,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references app.users(id) on delete set null,
  add column if not exists archive_reason text;

update app.branch_disciplines
set lifecycle_state = case when deleted_at is null then 'active' else 'archived' end,
    archived_at = case
      when deleted_at is null then null
      else coalesce(archived_at, deleted_at, created_at, now())
    end,
    archive_reason = case
      when deleted_at is null then null
      else coalesce(archive_reason, 'Перенесено из прежней отвязки')
    end,
    updated_at = coalesce(updated_at, created_at, now());

alter table app.branch_disciplines
  drop constraint if exists branch_disciplines_lifecycle_state_check,
  drop constraint if exists branch_disciplines_version_positive,
  drop constraint if exists branch_disciplines_lifecycle_consistency_check;
alter table app.branch_disciplines
  add constraint branch_disciplines_lifecycle_state_check
    check (lifecycle_state in ('active', 'archived')),
  add constraint branch_disciplines_version_positive check (version > 0),
  add constraint branch_disciplines_lifecycle_consistency_check check (
    (lifecycle_state = 'active' and deleted_at is null and archived_at is null
      and archive_reason is null)
    or
    (lifecycle_state = 'archived' and deleted_at is not null
      and archived_at is not null and nullif(btrim(archive_reason), '') is not null)
  );

-- A name remains reserved while archived, so create cannot fork the identity
-- that historical references and restore are expected to retain.
do $$
begin
  if exists (
    select 1 from app.disciplines
    group by lower(btrim(name)) having count(*) > 1
  ) then
    raise exception 'duplicate discipline names must be remediated before 0124';
  end if;
  if exists (
    select 1 from app.lead_loss_reasons
    group by lower(btrim(name)), kind having count(*) > 1
  ) then
    raise exception 'duplicate loss reason names must be remediated before 0124';
  end if;
end $$;

drop index if exists app.disciplines_name_idx;
create unique index disciplines_name_idx
  on app.disciplines (lower(btrim(name)));
drop index if exists app.lead_loss_reasons_name_kind_idx;
create unique index lead_loss_reasons_name_kind_idx
  on app.lead_loss_reasons (lower(btrim(name)), kind);

create table if not exists app.reference_catalog_history (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  operation text not null,
  from_state text not null,
  to_state text not null,
  version bigint not null,
  reason_text text not null,
  actor_user_id uuid references app.users(id) on delete set null,
  request_id text not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now(),
  constraint reference_catalog_history_entity_type_check
    check (entity_type in ('discipline', 'loss_reason', 'branch_discipline')),
  constraint reference_catalog_history_operation_check
    check (operation in ('rename', 'archive', 'restore', 'unassign', 'migration')),
  constraint reference_catalog_history_state_check
    check (from_state in ('active', 'archived') and to_state in ('active', 'archived')),
  constraint reference_catalog_history_version_positive check (version > 0),
  constraint reference_catalog_history_reason_check
    check (nullif(btrim(reason_text), '') is not null and char_length(reason_text) <= 500),
  constraint reference_catalog_history_request_check
    check (nullif(btrim(request_id), '') is not null and char_length(request_id) <= 160),
  constraint reference_catalog_history_snapshot_check
    check (jsonb_typeof(snapshot) = 'object'),
  unique (entity_type, entity_id, version)
);
create index if not exists reference_catalog_history_entity_idx
  on app.reference_catalog_history (entity_type, entity_id, created_at desc, id desc);

insert into app.reference_catalog_history (
  entity_type, entity_id, operation, from_state, to_state, version,
  reason_text, request_id, snapshot, created_at
)
select 'discipline', id, 'migration', 'active', 'archived', version,
       archive_reason, 'migration:0124:discipline:' || id::text,
       jsonb_build_object('name', name, 'lifecycleState', lifecycle_state),
       archived_at
from app.disciplines where lifecycle_state = 'archived'
on conflict (entity_type, entity_id, version) do nothing;

insert into app.reference_catalog_history (
  entity_type, entity_id, operation, from_state, to_state, version,
  reason_text, request_id, snapshot, created_at
)
select 'loss_reason', id, 'migration', 'active', 'archived', version,
       archive_reason, 'migration:0124:loss-reason:' || id::text,
       jsonb_build_object('name', name, 'kind', kind, 'lifecycleState', lifecycle_state),
       archived_at
from app.lead_loss_reasons where lifecycle_state = 'archived'
on conflict (entity_type, entity_id, version) do nothing;

insert into app.reference_catalog_history (
  entity_type, entity_id, operation, from_state, to_state, version,
  reason_text, request_id, snapshot, created_at
)
select 'branch_discipline', id, 'migration', 'active', 'archived', version,
       archive_reason, 'migration:0124:branch-discipline:' || id::text,
       jsonb_build_object(
         'branchId', branch_id, 'disciplineId', discipline_id,
         'lifecycleState', lifecycle_state
       ), archived_at
from app.branch_disciplines where lifecycle_state = 'archived'
on conflict (entity_type, entity_id, version) do nothing;

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'reference:discipline', id::text, version from app.disciplines
on conflict (aggregate_type, aggregate_id) do update
set version = greatest(app.aggregate_versions.version, excluded.version), updated_at = now();
insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'reference:loss_reason', id::text, version from app.lead_loss_reasons
on conflict (aggregate_type, aggregate_id) do update
set version = greatest(app.aggregate_versions.version, excluded.version), updated_at = now();
insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'reference:branch_discipline', id::text, version from app.branch_disciplines
on conflict (aggregate_type, aggregate_id) do update
set version = greatest(app.aggregate_versions.version, excluded.version), updated_at = now();

-- Renaming a reason must not rewrite the label/kind of an already committed
-- lead transition or historical analytics row.
alter table app.lead_status_history
  add column if not exists reason_name_snapshot text,
  add column if not exists reason_kind_snapshot text;
update app.lead_status_history history
set reason_name_snapshot = coalesce(history.reason_name_snapshot, reason.name),
    reason_kind_snapshot = coalesce(history.reason_kind_snapshot, reason.kind)
from app.lead_loss_reasons reason
where history.reason_id = reason.id;
alter table app.lead_status_history
  drop constraint if exists lead_status_history_reason_snapshot_check;
alter table app.lead_status_history
  add constraint lead_status_history_reason_snapshot_check check (
    reason_id is null
    or (
      nullif(btrim(reason_name_snapshot), '') is not null
      and reason_kind_snapshot in ('lost', 'paused')
    )
  );

create or replace function app.reject_reference_catalog_history_mutation()
returns trigger language plpgsql as $$
begin
  raise exception using errcode = '23514',
    message = 'reference_catalog_history is append-only';
end;
$$;
drop trigger if exists reference_catalog_history_append_only
  on app.reference_catalog_history;
create trigger reference_catalog_history_append_only
before update or delete on app.reference_catalog_history
for each row execute function app.reject_reference_catalog_history_mutation();

create or replace function app.reject_lead_status_history_mutation()
returns trigger language plpgsql as $$
begin
  if TG_OP = 'UPDATE'
    and current_setting('app.allow_lead_status_history_repoint', true) = 'on'
    and (to_jsonb(new) - 'lead_id') = (to_jsonb(old) - 'lead_id') then
    return new;
  end if;
  raise exception using errcode = '23514',
    message = 'lead_status_history is append-only';
end;
$$;
drop trigger if exists lead_status_history_append_only on app.lead_status_history;
create trigger lead_status_history_append_only
before update or delete on app.lead_status_history
for each row execute function app.reject_lead_status_history_mutation();

create or replace function app.reject_reference_physical_delete()
returns trigger language plpgsql as $$
begin
  if current_user <> 'magiccrm_app'
    and current_setting('app.enforce_reference_physical_delete_guard', true)
      is distinct from 'on' then
    return old;
  end if;
  raise exception using errcode = '23514',
    constraint = 'reference_catalog_archive_instead_of_delete',
    message = 'reference catalog records must be archived instead of deleted';
end;
$$;
drop trigger if exists disciplines_reject_physical_delete on app.disciplines;
create trigger disciplines_reject_physical_delete
before delete on app.disciplines
for each row execute function app.reject_reference_physical_delete();
drop trigger if exists lead_loss_reasons_reject_physical_delete on app.lead_loss_reasons;
create trigger lead_loss_reasons_reject_physical_delete
before delete on app.lead_loss_reasons
for each row execute function app.reject_reference_physical_delete();
drop trigger if exists branch_disciplines_reject_physical_delete on app.branch_disciplines;
create trigger branch_disciplines_reject_physical_delete
before delete on app.branch_disciplines
for each row execute function app.reject_reference_physical_delete();

create or replace function app.guard_active_discipline_reference()
returns trigger language plpgsql as $$
declare
  target_discipline_id uuid;
  should_check boolean := true;
  discipline_active boolean;
  branch_active boolean;
begin
  if TG_TABLE_NAME = 'branch_disciplines' then
    if TG_OP = 'UPDATE' and (
      new.branch_id is distinct from old.branch_id
      or new.discipline_id is distinct from old.discipline_id
    ) then
      raise exception using errcode = '23514',
        constraint = 'branch_discipline_identity_immutable',
        message = 'branch discipline identity cannot be changed';
    end if;
    target_discipline_id := new.discipline_id;
    should_check := new.lifecycle_state = 'active' and new.deleted_at is null;
    if should_check then
      select true into branch_active
      from app.branches branch
      where branch.id = new.branch_id
        and branch.lifecycle_state = 'active' and branch.deleted_at is null
      for share;
      if not coalesce(branch_active, false) then
        raise exception using errcode = '23514',
          constraint = 'active_branch_reference_required',
          message = 'active branch discipline references require an active branch';
      end if;
    end if;
  elsif TG_TABLE_NAME = 'student_disciplines' then
    target_discipline_id := new.discipline_id;
    should_check := new.deleted_at is null;
  elsif TG_TABLE_NAME = 'teacher_disciplines' then
    target_discipline_id := new.discipline_id;
  elsif TG_TABLE_NAME = 'subscription_packages' then
    target_discipline_id := new.discipline_id;
    should_check := new.discipline_id is not null
      and new.deleted_at is null and new.is_active;
  end if;
  if not should_check or target_discipline_id is null then return new; end if;
  select true into discipline_active
  from app.disciplines discipline
  where discipline.id = target_discipline_id
    and discipline.lifecycle_state = 'active'
    and discipline.is_active and discipline.deleted_at is null
  for share;
  if not coalesce(discipline_active, false) then
    raise exception using errcode = '23514',
      constraint = 'active_discipline_reference_required',
      message = 'active references require an active discipline';
  end if;
  return new;
end;
$$;
drop trigger if exists branch_disciplines_guard_active_discipline on app.branch_disciplines;
create trigger branch_disciplines_guard_active_discipline
before insert or update on app.branch_disciplines
for each row execute function app.guard_active_discipline_reference();
drop trigger if exists student_disciplines_guard_active_discipline on app.student_disciplines;
create trigger student_disciplines_guard_active_discipline
before insert or update on app.student_disciplines
for each row execute function app.guard_active_discipline_reference();
drop trigger if exists teacher_disciplines_guard_active_discipline on app.teacher_disciplines;
create trigger teacher_disciplines_guard_active_discipline
before insert or update on app.teacher_disciplines
for each row execute function app.guard_active_discipline_reference();
drop trigger if exists subscription_packages_guard_active_discipline on app.subscription_packages;
create trigger subscription_packages_guard_active_discipline
before insert or update on app.subscription_packages
for each row execute function app.guard_active_discipline_reference();

create or replace function app.guard_active_loss_reason_reference()
returns trigger language plpgsql as $$
declare reason_active boolean;
begin
  if new.reason_id is null then return new; end if;
  select true into reason_active
  from app.lead_loss_reasons reason
  where reason.id = new.reason_id
    and reason.lifecycle_state = 'active'
    and reason.is_active and reason.deleted_at is null
  for share;
  if not coalesce(reason_active, false) then
    raise exception using errcode = '23514',
      constraint = 'active_loss_reason_reference_required',
      message = 'new lead transitions require an active loss reason';
  end if;
  return new;
end;
$$;
drop trigger if exists lead_status_history_guard_active_reason
  on app.lead_status_history;
create trigger lead_status_history_guard_active_reason
before insert or update of reason_id on app.lead_status_history
for each row execute function app.guard_active_loss_reason_reference();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.reference_catalog_history to magiccrm_app;
    revoke update, delete on app.reference_catalog_history from magiccrm_app;
  end if;
end $$;
