alter table app.users
  add column if not exists password_changed_at timestamptz,
  add column if not exists email_changed_at timestamptz;

alter table app.teachers
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists offboarded_at timestamptz,
  add column if not exists offboarded_by uuid references app.users(id) on delete set null,
  add column if not exists offboard_reason text,
  add column if not exists lifecycle_previous_status text,
  add column if not exists lifecycle_account_was_active boolean,
  add column if not exists lifecycle_snapshot jsonb not null default '{}'::jsonb;

alter table app.staff_members
  add column if not exists lifecycle_state text not null default 'active',
  add column if not exists version bigint not null default 1,
  add column if not exists offboarded_at timestamptz,
  add column if not exists offboarded_by uuid references app.users(id) on delete set null,
  add column if not exists offboard_reason text,
  add column if not exists lifecycle_previous_status text,
  add column if not exists lifecycle_account_was_active boolean,
  add column if not exists lifecycle_snapshot jsonb not null default '{}'::jsonb;

alter table app.teachers
  drop constraint if exists teachers_lifecycle_state_check;
alter table app.teachers
  add constraint teachers_lifecycle_state_check
  check (lifecycle_state in ('active', 'archived'));

alter table app.staff_members
  drop constraint if exists staff_members_lifecycle_state_check,
  drop constraint if exists staff_members_version_positive;
alter table app.staff_members
  add constraint staff_members_lifecycle_state_check
    check (lifecycle_state in ('active', 'archived')),
  add constraint staff_members_version_positive check (version > 0);

create index if not exists teachers_lifecycle_idx
  on app.teachers (lifecycle_state, status, id);
create index if not exists staff_members_lifecycle_idx
  on app.staff_members (lifecycle_state, status, id);

create table if not exists app.person_lifecycle_history (
  id uuid primary key default gen_random_uuid(),
  person_type text not null,
  person_id uuid not null,
  operation text not null,
  from_state text not null,
  to_state text not null,
  version bigint not null,
  reason_text text not null,
  actor_user_id uuid references app.users(id) on delete set null,
  request_id text not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now(),
  constraint person_lifecycle_history_type_check
    check (person_type in ('teacher', 'staff')),
  constraint person_lifecycle_history_operation_check
    check (operation in ('offboard', 'restore')),
  constraint person_lifecycle_history_state_check
    check (from_state in ('active', 'archived') and to_state in ('active', 'archived')),
  constraint person_lifecycle_history_version_positive check (version > 0),
  constraint person_lifecycle_history_reason_check
    check (char_length(btrim(reason_text)) between 5 and 500),
  constraint person_lifecycle_history_request_check
    check (char_length(btrim(request_id)) between 1 and 200),
  constraint person_lifecycle_history_snapshot_check
    check (jsonb_typeof(snapshot) = 'object')
);

create index if not exists person_lifecycle_history_person_idx
  on app.person_lifecycle_history
  (person_type, person_id, created_at desc, id desc);

create or replace function app.reject_person_lifecycle_history_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'person_lifecycle_history is append-only';
end;
$$;

drop trigger if exists person_lifecycle_history_append_only
  on app.person_lifecycle_history;
create trigger person_lifecycle_history_append_only
before update or delete on app.person_lifecycle_history
for each row execute function app.reject_person_lifecycle_history_mutation();

create or replace function app.guard_active_teacher_assignment()
returns trigger
language plpgsql
as $$
declare
  teacher_active boolean;
begin
  if new.active_until is not null and new.active_until < current_date then
    return new;
  end if;
  select true into teacher_active
  from app.teachers teacher
  where teacher.id = new.teacher_id
    and teacher.deleted_at is null
    and teacher.lifecycle_state = 'active'
  for share;
  if not coalesce(teacher_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'teacher_branch_active_teacher_required',
      message = 'active branch assignment requires an active teacher';
  end if;
  return new;
end;
$$;

drop trigger if exists teacher_branches_guard_active_teacher on app.teacher_branches;
create trigger teacher_branches_guard_active_teacher
before insert or update on app.teacher_branches
for each row execute function app.guard_active_teacher_assignment();

create or replace function app.guard_active_staff_assignment()
returns trigger
language plpgsql
as $$
declare
  staff_active boolean;
begin
  if new.deleted_at is not null then return new; end if;
  select true into staff_active
  from app.staff_members staff
  where staff.id = new.staff_member_id
    and staff.deleted_at is null
    and staff.lifecycle_state = 'active'
  for share;
  if not coalesce(staff_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'staff_branch_active_staff_required',
      message = 'active branch assignment requires an active staff member';
  end if;
  return new;
end;
$$;

drop trigger if exists staff_branches_guard_active_staff
  on app.staff_branch_assignments;
create trigger staff_branches_guard_active_staff
before insert or update on app.staff_branch_assignments
for each row execute function app.guard_active_staff_assignment();

create or replace function app.guard_active_teacher_schedule_reference()
returns trigger
language plpgsql
as $$
declare
  should_check boolean := false;
  teacher_active boolean;
begin
  if new.teacher_id is null then return new; end if;
  if TG_TABLE_NAME = 'lessons' then
    should_check := new.deleted_at is null
      and new.scheduled_at >= now()
      and new.lifecycle_state in ('scheduled', 'settlement_pending');
  elsif TG_TABLE_NAME = 'schedule_series' then
    should_check := new.deleted_at is null
      and new.superseded_by is null
      and (new.valid_until is null or new.valid_until >= current_date);
  end if;
  if not should_check then return new; end if;

  select true into teacher_active
  from app.teachers teacher
  where teacher.id = new.teacher_id
    and teacher.deleted_at is null
    and teacher.lifecycle_state = 'active'
    and lower(teacher.status) in ('active', 'working', 'активен', 'работает')
  for share;
  if not coalesce(teacher_active, false) then
    raise exception using
      errcode = '23514',
      constraint = 'active_teacher_schedule_reference_required',
      message = 'active scheduling reference requires an active teacher';
  end if;
  return new;
end;
$$;

drop trigger if exists lessons_guard_active_teacher on app.lessons;
create trigger lessons_guard_active_teacher
before insert or update on app.lessons
for each row execute function app.guard_active_teacher_schedule_reference();

drop trigger if exists schedule_series_guard_active_teacher on app.schedule_series;
create trigger schedule_series_guard_active_teacher
before insert or update on app.schedule_series
for each row execute function app.guard_active_teacher_schedule_reference();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.person_lifecycle_history to magiccrm_app;
  end if;
end $$;
