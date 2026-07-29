-- v4 T4.1.1: explicit Lesson lifecycle, immutable command snapshot,
-- append-only transitions and subscription reservations.

alter table app.lessons
  add column if not exists lifecycle_state text not null default 'scheduled',
  add column if not exists version bigint not null default 1,
  add column if not exists predecessor_id uuid references app.lessons(id)
    on delete restrict,
  add column if not exists successor_id uuid references app.lessons(id)
    on delete restrict;

update app.lessons
set lifecycle_state = case lower(btrim(status))
  when 'completed' then 'successfully_completed'
  when 'successfully_completed' then 'successfully_completed'
  when 'cancelled' then 'cancelled'
  when 'canceled' then 'cancelled'
  when 'rescheduled' then 'rescheduled'
  else 'scheduled'
end;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'lessons_lifecycle_state_check'
      and conrelid = 'app.lessons'::regclass
  ) then
    alter table app.lessons
      add constraint lessons_lifecycle_state_check
      check (
        lifecycle_state in (
          'scheduled',
          'successfully_completed',
          'cancelled',
          'rescheduled'
        )
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'lessons_version_positive'
      and conrelid = 'app.lessons'::regclass
  ) then
    alter table app.lessons
      add constraint lessons_version_positive check (version > 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'lessons_predecessor_not_self'
      and conrelid = 'app.lessons'::regclass
  ) then
    alter table app.lessons
      add constraint lessons_predecessor_not_self
      check (predecessor_id is null or predecessor_id <> id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'lessons_successor_not_self'
      and conrelid = 'app.lessons'::regclass
  ) then
    alter table app.lessons
      add constraint lessons_successor_not_self
      check (successor_id is null or successor_id <> id);
  end if;
end $$;

create unique index if not exists lessons_one_successor_per_predecessor_idx
  on app.lessons (predecessor_id)
  where predecessor_id is not null;

create unique index if not exists lessons_successor_reference_unique_idx
  on app.lessons (successor_id)
  where successor_id is not null;

create index if not exists lessons_lifecycle_due_idx
  on app.lessons (lifecycle_state, scheduled_at, id)
  where deleted_at is null and lifecycle_state = 'scheduled';

create table if not exists app.lesson_snapshots (
  lesson_id uuid primary key references app.lessons(id) on delete restrict,
  client_type text not null,
  client_id uuid not null,
  completion_type text not null,
  client_charge_type text not null,
  client_charge_value numeric(12,2) not null default 0,
  teacher_compensation_type text not null,
  teacher_compensation_value numeric(12,2) not null default 0,
  subscription_id uuid references app.subscriptions(id) on delete restrict,
  trial boolean not null default false,
  validation_state text not null default 'valid',
  origin text not null default 'runtime',
  created_at timestamptz not null default now(),
  constraint lesson_snapshots_client_type_check
    check (client_type in ('lead', 'student')),
  constraint lesson_snapshots_completion_type_check
    check (completion_type ~ '^[A-Za-z0-9._:-]{1,80}$'),
  constraint lesson_snapshots_charge_type_check
    check (client_charge_type in ('subscription', 'personal_account', 'none')),
  constraint lesson_snapshots_compensation_type_check
    check (teacher_compensation_type in ('fixed', 'hourly', 'none')),
  constraint lesson_snapshots_values_nonnegative
    check (client_charge_value >= 0 and teacher_compensation_value >= 0),
  constraint lesson_snapshots_validation_state_check
    check (validation_state in ('valid', 'legacy_incomplete')),
  constraint lesson_snapshots_origin_check
    check (origin in ('runtime', 'legacy_backfill')),
  constraint lesson_snapshots_subscription_check
    check (
      validation_state = 'legacy_incomplete'
      or (
        (client_charge_type = 'subscription' and subscription_id is not null)
        or (client_charge_type <> 'subscription' and subscription_id is null)
      )
    )
);

create table if not exists app.lesson_transitions (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete restrict,
  from_state text not null,
  to_state text not null,
  reason_code text not null,
  reason_text text,
  actor_user_id uuid references app.users(id) on delete set null,
  worker_id text,
  predecessor_id uuid references app.lessons(id) on delete restrict,
  successor_id uuid references app.lessons(id) on delete restrict,
  financial_decision jsonb not null default '{}'::jsonb,
  client_financial_fact_id uuid,
  teacher_financial_fact_id uuid,
  origin text not null default 'runtime',
  created_at timestamptz not null default now(),
  constraint lesson_transitions_state_check
    check (
      from_state = 'scheduled'
      and to_state in (
        'successfully_completed',
        'cancelled',
        'rescheduled'
      )
    ),
  constraint lesson_transitions_reason_code_check
    check (reason_code ~ '^[A-Za-z0-9._:-]{1,120}$'),
  constraint lesson_transitions_origin_check
    check (origin in ('runtime', 'legacy_backfill')),
  constraint lesson_transitions_reschedule_link_check
    check (
      (to_state = 'rescheduled' and successor_id is not null)
      or (to_state <> 'rescheduled')
      or origin = 'legacy_backfill'
    )
);

create unique index if not exists lesson_transitions_one_terminal_idx
  on app.lesson_transitions (lesson_id);

create unique index if not exists lesson_transitions_client_fact_unique_idx
  on app.lesson_transitions (client_financial_fact_id)
  where client_financial_fact_id is not null;

create unique index if not exists lesson_transitions_teacher_fact_unique_idx
  on app.lesson_transitions (teacher_financial_fact_id)
  where teacher_financial_fact_id is not null;

create index if not exists lesson_transitions_created_idx
  on app.lesson_transitions (lesson_id, created_at, id);

create table if not exists app.lesson_reservations (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete restrict,
  subscription_id uuid not null references app.subscriptions(id)
    on delete restrict,
  units numeric(8,2) not null,
  state text not null default 'reserved',
  version bigint not null default 1,
  financial_fact_id uuid,
  terminal_at timestamptz,
  origin text not null default 'runtime',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lesson_reservations_units_positive check (units > 0),
  constraint lesson_reservations_state_check
    check (state in ('reserved', 'consumed', 'released', 'cancelled')),
  constraint lesson_reservations_version_positive check (version > 0),
  constraint lesson_reservations_terminal_time_check
    check (
      (state = 'reserved' and terminal_at is null)
      or (state <> 'reserved' and terminal_at is not null)
    ),
  constraint lesson_reservations_consumption_fact_check
    check (state <> 'consumed' or financial_fact_id is not null),
  constraint lesson_reservations_origin_check
    check (origin = 'runtime')
);

create unique index if not exists lesson_reservations_lesson_subscription_idx
  on app.lesson_reservations (lesson_id, subscription_id);

create unique index if not exists lesson_reservations_one_active_idx
  on app.lesson_reservations (lesson_id)
  where state = 'reserved';

create unique index if not exists lesson_reservations_financial_fact_unique_idx
  on app.lesson_reservations (financial_fact_id)
  where financial_fact_id is not null;

create or replace function app.reject_immutable_lesson_fact()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = TG_TABLE_NAME || ' is immutable';
end;
$$;

drop trigger if exists lesson_snapshots_immutable on app.lesson_snapshots;
create trigger lesson_snapshots_immutable
before update or delete on app.lesson_snapshots
for each row execute function app.reject_immutable_lesson_fact();

drop trigger if exists lesson_transitions_immutable on app.lesson_transitions;
create trigger lesson_transitions_immutable
before update or delete on app.lesson_transitions
for each row execute function app.reject_immutable_lesson_fact();

create or replace function app.sync_lesson_lifecycle()
returns trigger
language plpgsql
as $$
declare
  mapped_state text;
begin
  if TG_OP = 'INSERT' then
    new.lifecycle_state := case lower(btrim(new.status))
      when 'completed' then 'successfully_completed'
      when 'successfully_completed' then 'successfully_completed'
      when 'cancelled' then 'cancelled'
      when 'canceled' then 'cancelled'
      when 'rescheduled' then 'rescheduled'
      else 'scheduled'
    end;
    return new;
  end if;

  if new.lifecycle_state is distinct from old.lifecycle_state then
    mapped_state := new.lifecycle_state;
    new.status := case mapped_state
      when 'successfully_completed' then 'completed'
      else mapped_state
    end;
  elsif new.status is distinct from old.status then
    mapped_state := case lower(btrim(new.status))
      when 'completed' then 'successfully_completed'
      when 'successfully_completed' then 'successfully_completed'
      when 'cancelled' then 'cancelled'
      when 'canceled' then 'cancelled'
      when 'rescheduled' then 'rescheduled'
      else 'scheduled'
    end;
    new.lifecycle_state := mapped_state;
  else
    mapped_state := old.lifecycle_state;
  end if;

  if old.lifecycle_state in (
    'successfully_completed',
    'cancelled',
    'rescheduled'
  ) and new.lifecycle_state is distinct from old.lifecycle_state then
    raise exception using
      errcode = '23514',
      message = 'terminal lesson lifecycle cannot transition';
  end if;

  if old.lifecycle_state = 'scheduled'
    and new.lifecycle_state not in (
      'scheduled',
      'successfully_completed',
      'cancelled',
      'rescheduled'
    ) then
    raise exception using
      errcode = '23514',
      message = 'illegal lesson lifecycle transition';
  end if;

  new.version := greatest(
    coalesce(new.version, old.version),
    old.version + 1
  );
  return new;
end;
$$;

drop trigger if exists lessons_sync_lifecycle on app.lessons;
create trigger lessons_sync_lifecycle
before insert or update on app.lessons
for each row execute function app.sync_lesson_lifecycle();

create or replace function app.guard_lesson_reservation_lifecycle()
returns trigger
language plpgsql
as $$
begin
  if old.state <> 'reserved' and new.state is distinct from old.state then
    raise exception using
      errcode = '23514',
      message = 'terminal lesson reservation cannot transition';
  end if;
  if old.state = 'reserved'
    and new.state not in ('reserved', 'consumed', 'released', 'cancelled') then
    raise exception using
      errcode = '23514',
      message = 'illegal lesson reservation transition';
  end if;
  if new.state = 'reserved' then
    new.terminal_at := null;
  elsif new.terminal_at is null then
    new.terminal_at := now();
  end if;
  new.version := greatest(
    coalesce(new.version, old.version),
    old.version + 1
  );
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists lesson_reservations_guard_lifecycle
  on app.lesson_reservations;
create trigger lesson_reservations_guard_lifecycle
before update on app.lesson_reservations
for each row execute function app.guard_lesson_reservation_lifecycle();

insert into app.lesson_snapshots (
  lesson_id,
  client_type,
  client_id,
  completion_type,
  client_charge_type,
  client_charge_value,
  teacher_compensation_type,
  teacher_compensation_value,
  subscription_id,
  trial,
  validation_state,
  origin,
  created_at
)
select
  lesson.id,
  case when lesson.lead_id is not null then 'lead' else 'student' end,
  coalesce(lesson.lead_id, lesson.student_id),
  'legacy.' || regexp_replace(
    lower(coalesce(nullif(btrim(lesson.status), ''), 'scheduled')),
    '[^a-z0-9._:-]',
    '_',
    'g'
  ),
  'none',
  0,
  case when lesson.teacher_rate is null then 'none' else 'fixed' end,
  coalesce(lesson.teacher_rate, 0),
  null,
  lesson.is_trial,
  'legacy_incomplete',
  'legacy_backfill',
  lesson.created_at
from app.lessons lesson
where coalesce(lesson.lead_id, lesson.student_id) is not null
on conflict (lesson_id) do nothing;

insert into app.lesson_transitions (
  lesson_id,
  from_state,
  to_state,
  reason_code,
  actor_user_id,
  worker_id,
  origin,
  created_at
)
select
  lesson.id,
  'scheduled',
  lesson.lifecycle_state,
  'migration.legacy-status',
  lesson.created_by,
  'migration:0083',
  'legacy_backfill',
  lesson.updated_at
from app.lessons lesson
where lesson.lifecycle_state in (
  'successfully_completed',
  'cancelled',
  'rescheduled'
)
on conflict (lesson_id) do nothing;

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'schedule:lesson', lesson.id::text, lesson.version
from app.lessons lesson
on conflict (aggregate_type, aggregate_id)
do update set
  version = greatest(app.aggregate_versions.version, excluded.version),
  updated_at = now();

create or replace function app.sync_lesson_aggregate_version()
returns trigger
language plpgsql
as $$
begin
  if TG_OP = 'DELETE' then
    delete from app.aggregate_versions
    where aggregate_type = 'schedule:lesson'
      and aggregate_id = old.id::text;
    return old;
  end if;

  insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
  values ('schedule:lesson', new.id::text, new.version)
  on conflict (aggregate_type, aggregate_id)
  do update set
    version = greatest(app.aggregate_versions.version, excluded.version),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists lessons_sync_aggregate_version on app.lessons;
create trigger lessons_sync_aggregate_version
after insert or update or delete on app.lessons
for each row execute function app.sync_lesson_aggregate_version();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.lesson_snapshots to magiccrm_app;
    grant select, insert on app.lesson_transitions to magiccrm_app;
    grant select, insert, update on app.lesson_reservations to magiccrm_app;
  end if;
end $$;
