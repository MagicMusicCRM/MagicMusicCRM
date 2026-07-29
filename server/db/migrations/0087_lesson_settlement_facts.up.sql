-- v4 T5.1.1: immutable, idempotent financial facts produced from the
-- authoritative LessonSnapshot when a Lesson is successfully completed.

drop trigger if exists lesson_snapshots_immutable on app.lesson_snapshots;

alter table app.lesson_snapshots
  add column if not exists duration_minutes integer;

update app.lesson_snapshots snapshot
set duration_minutes = lesson.duration_minutes
from app.lessons lesson
where lesson.id = snapshot.lesson_id
  and snapshot.duration_minutes is null;

alter table app.lesson_snapshots
  alter column duration_minutes set not null,
  add constraint lesson_snapshots_duration_positive
    check (duration_minutes > 0);

create or replace function app.fill_lesson_snapshot_duration()
returns trigger
language plpgsql
as $$
begin
  if new.duration_minutes is null then
    select lesson.duration_minutes
    into new.duration_minutes
    from app.lessons lesson
    where lesson.id = new.lesson_id;
  end if;
  return new;
end;
$$;

create trigger lesson_snapshots_fill_duration
before insert on app.lesson_snapshots
for each row execute function app.fill_lesson_snapshot_duration();

create trigger lesson_snapshots_immutable
before update or delete on app.lesson_snapshots
for each row execute function app.reject_immutable_lesson_fact();

create table if not exists app.lesson_client_charge_facts (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null unique references app.lessons(id) on delete restrict,
  client_type text not null,
  client_id uuid not null,
  charge_type text not null,
  snapshot_value numeric(12,2) not null,
  subscription_id uuid references app.subscriptions(id) on delete restrict,
  amount_minor bigint not null,
  units numeric(8,2) not null,
  currency_code text not null default 'RUB',
  created_at timestamptz not null default now(),
  constraint lesson_client_charge_facts_client_type_check
    check (client_type in ('lead', 'student')),
  constraint lesson_client_charge_facts_charge_type_check
    check (charge_type in ('subscription', 'personal_account', 'none')),
  constraint lesson_client_charge_facts_nonnegative_check
    check (snapshot_value >= 0 and amount_minor >= 0 and units >= 0),
  constraint lesson_client_charge_facts_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint lesson_client_charge_facts_shape_check
    check (
      (
        charge_type = 'subscription'
        and subscription_id is not null
        and amount_minor = 0
        and units = snapshot_value
      )
      or (
        charge_type = 'personal_account'
        and subscription_id is null
        and amount_minor = round(snapshot_value * 100)::bigint
        and units = 0
      )
      or (
        charge_type = 'none'
        and subscription_id is null
        and snapshot_value = 0
        and amount_minor = 0
        and units = 0
      )
    )
);

create table if not exists app.lesson_teacher_compensation_facts (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null unique references app.lessons(id) on delete restrict,
  teacher_id uuid not null references app.teachers(id) on delete restrict,
  compensation_type text not null,
  snapshot_rate numeric(12,2) not null,
  rate_minor bigint not null,
  duration_minutes integer not null,
  amount_minor bigint not null,
  currency_code text not null default 'RUB',
  created_at timestamptz not null default now(),
  constraint lesson_teacher_compensation_facts_type_check
    check (compensation_type in ('fixed', 'hourly', 'none')),
  constraint lesson_teacher_compensation_facts_nonnegative_check
    check (
      snapshot_rate >= 0
      and rate_minor >= 0
      and duration_minutes > 0
      and amount_minor >= 0
    ),
  constraint lesson_teacher_compensation_facts_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint lesson_teacher_compensation_facts_shape_check
    check (
      (
        compensation_type = 'fixed'
        and rate_minor = round(snapshot_rate * 100)::bigint
        and amount_minor = rate_minor
      )
      or (
        compensation_type = 'hourly'
        and rate_minor = round(snapshot_rate * 100)::bigint
        and amount_minor = round(
          snapshot_rate * 100 * duration_minutes / 60
        )::bigint
      )
      or (
        compensation_type = 'none'
        and snapshot_rate = 0
        and rate_minor = 0
        and amount_minor = 0
      )
    )
);

create trigger lesson_client_charge_facts_immutable
before update or delete on app.lesson_client_charge_facts
for each row execute function app.reject_immutable_lesson_fact();

create trigger lesson_teacher_compensation_facts_immutable
before update or delete on app.lesson_teacher_compensation_facts
for each row execute function app.reject_immutable_lesson_fact();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.lesson_client_charge_facts to magiccrm_app;
    grant select, insert on app.lesson_teacher_compensation_facts
      to magiccrm_app;
  end if;
end $$;
