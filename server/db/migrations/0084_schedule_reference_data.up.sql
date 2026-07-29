-- v4 T4.1.2: timezone-aware branch hours, teacher availability and
-- effective-dated teacher-to-branch assignments.

alter table app.branches
  add column if not exists timezone_name text not null default 'Europe/Moscow',
  add column if not exists schedule_reference_version bigint not null default 1;

alter table app.teachers
  add column if not exists schedule_reference_version bigint not null default 1;

alter table app.teacher_branches
  add column if not exists active_from date not null default date '1970-01-01',
  add column if not exists active_until date,
  add column if not exists version bigint not null default 1,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'branches_schedule_reference_version_positive'
      and conrelid = 'app.branches'::regclass
  ) then
    alter table app.branches
      add constraint branches_schedule_reference_version_positive
      check (schedule_reference_version > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'teachers_schedule_reference_version_positive'
      and conrelid = 'app.teachers'::regclass
  ) then
    alter table app.teachers
      add constraint teachers_schedule_reference_version_positive
      check (schedule_reference_version > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'teacher_branches_active_range_check'
      and conrelid = 'app.teacher_branches'::regclass
  ) then
    alter table app.teacher_branches
      add constraint teacher_branches_active_range_check
      check (active_until is null or active_until >= active_from);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'teacher_branches_version_positive'
      and conrelid = 'app.teacher_branches'::regclass
  ) then
    alter table app.teacher_branches
      add constraint teacher_branches_version_positive
      check (version > 0);
  end if;
end $$;

create table if not exists app.branch_hours (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references app.branches(id) on delete cascade,
  weekday smallint not null,
  open_local time not null,
  close_local time not null,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branch_hours_weekday_check check (weekday between 1 and 7),
  constraint branch_hours_interval_check check (open_local < close_local),
  constraint branch_hours_version_positive check (version > 0),
  unique (branch_id, weekday)
);

create table if not exists app.branch_hour_exceptions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references app.branches(id) on delete cascade,
  local_date date not null,
  closed boolean not null default true,
  open_local time,
  close_local time,
  reason text,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branch_hour_exceptions_interval_check
    check (
      (closed and open_local is null and close_local is null)
      or (
        not closed
        and open_local is not null
        and close_local is not null
        and open_local < close_local
      )
    ),
  constraint branch_hour_exceptions_reason_check
    check (reason is null or char_length(reason) between 1 and 300),
  constraint branch_hour_exceptions_version_positive check (version > 0),
  unique (branch_id, local_date)
);

create table if not exists app.teacher_availability_rules (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.teachers(id) on delete cascade,
  kind text not null,
  available boolean not null,
  timezone_name text not null default 'Europe/Moscow',
  weekday smallint,
  local_start time,
  local_end time,
  valid_from date,
  valid_until date,
  starts_at timestamptz,
  ends_at timestamptz,
  reason text,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint teacher_availability_kind_check
    check (kind in ('recurring', 'interval')),
  constraint teacher_availability_shape_check
    check (
      (
        kind = 'recurring'
        and weekday between 1 and 7
        and local_start is not null
        and local_end is not null
        and local_start < local_end
        and valid_from is not null
        and (valid_until is null or valid_until >= valid_from)
        and starts_at is null
        and ends_at is null
      )
      or (
        kind = 'interval'
        and weekday is null
        and local_start is null
        and local_end is null
        and valid_from is null
        and valid_until is null
        and starts_at is not null
        and (
          (ends_at is not null and ends_at > starts_at)
          or (not available and ends_at is null)
        )
      )
    ),
  constraint teacher_availability_reason_check
    check (reason is null or char_length(reason) between 1 and 300),
  constraint teacher_availability_version_positive check (version > 0)
);

create index if not exists branch_hours_branch_weekday_idx
  on app.branch_hours (branch_id, weekday);

create index if not exists branch_hour_exceptions_branch_date_idx
  on app.branch_hour_exceptions (branch_id, local_date);

create index if not exists teacher_branches_active_idx
  on app.teacher_branches (teacher_id, branch_id, active_from, active_until);

create index if not exists teacher_availability_recurring_idx
  on app.teacher_availability_rules (
    teacher_id, weekday, valid_from, valid_until
  )
  where kind = 'recurring';

create index if not exists teacher_availability_interval_idx
  on app.teacher_availability_rules (teacher_id, starts_at, ends_at)
  where kind = 'interval';

create or replace function app.assert_schedule_timezone()
returns trigger
language plpgsql
as $$
declare
  candidate text;
begin
  candidate := new.timezone_name;
  if not exists (
    select 1 from pg_timezone_names where name = candidate
  ) then
    raise exception using
      errcode = '23514',
      message = 'unknown IANA timezone';
  end if;
  return new;
end;
$$;

drop trigger if exists branches_validate_schedule_timezone on app.branches;
create trigger branches_validate_schedule_timezone
before insert or update of timezone_name on app.branches
for each row execute function app.assert_schedule_timezone();

drop trigger if exists teacher_availability_validate_timezone
  on app.teacher_availability_rules;
create trigger teacher_availability_validate_timezone
before insert or update of timezone_name on app.teacher_availability_rules
for each row execute function app.assert_schedule_timezone();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'branches_timezone_name_nonempty'
      and conrelid = 'app.branches'::regclass
  ) then
    alter table app.branches
      add constraint branches_timezone_name_nonempty
      check (char_length(timezone_name) between 1 and 80);
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.branch_hours to magiccrm_app;
    grant select, insert, update, delete
      on app.branch_hour_exceptions to magiccrm_app;
    grant select, insert, update, delete
      on app.teacher_availability_rules to magiccrm_app;
  end if;
end $$;
