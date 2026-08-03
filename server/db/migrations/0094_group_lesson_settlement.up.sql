-- v4 refinement: immutable group participants, per-client settlement facts,
-- and multiple subscription reservations for one group Lesson.

drop trigger if exists lesson_snapshots_immutable on app.lesson_snapshots;

alter table app.lesson_snapshots
  add column if not exists group_id uuid
    references app.groups(id) on delete restrict,
  alter column client_type drop not null,
  alter column client_id drop not null,
  drop constraint if exists lesson_snapshots_client_type_check,
  drop constraint if exists lesson_snapshots_subscription_check;

alter table app.lesson_snapshots
  add constraint lesson_snapshots_subject_check
    check (
      (
        group_id is null
        and client_type in ('lead', 'student')
        and client_id is not null
      )
      or (
        group_id is not null
        and client_type is null
        and client_id is null
      )
    ),
  add constraint lesson_snapshots_subscription_check
    check (
      validation_state = 'legacy_incomplete'
      or (
        group_id is not null
        and client_charge_type = 'none'
        and client_charge_value = 0
        and subscription_id is null
      )
      or (
        group_id is null
        and (
          (client_charge_type = 'subscription' and subscription_id is not null)
          or (client_charge_type <> 'subscription' and subscription_id is null)
        )
      )
    );

create or replace function app.guard_lesson_snapshot_immutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
    and old.validation_state = 'legacy_incomplete'
    and new.validation_state = 'valid'
    and new.lesson_id = old.lesson_id
    and new.client_type is not distinct from old.client_type
    and new.client_id is not distinct from old.client_id
    and new.group_id is not distinct from old.group_id
    and new.origin = old.origin then
    return new;
  end if;
  raise exception using
    errcode = '23514',
    message = 'lesson_snapshots is immutable';
end;
$$;

create trigger lesson_snapshots_immutable
before update or delete on app.lesson_snapshots
for each row execute function app.guard_lesson_snapshot_immutable();

create table if not exists app.lesson_snapshot_participants (
  lesson_id uuid not null references app.lesson_snapshots(lesson_id)
    on delete restrict,
  student_id uuid not null references app.students(id) on delete restrict,
  charge_type text not null,
  charge_value numeric(12,2) not null,
  subscription_id uuid references app.subscriptions(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (lesson_id, student_id),
  constraint lesson_snapshot_participants_charge_type_check
    check (charge_type in ('subscription', 'personal_account', 'none')),
  constraint lesson_snapshot_participants_value_nonnegative
    check (charge_value >= 0),
  constraint lesson_snapshot_participants_subscription_check
    check (
      (charge_type = 'subscription' and subscription_id is not null and charge_value > 0)
      or (charge_type = 'personal_account' and subscription_id is null)
      or (charge_type = 'none' and subscription_id is null and charge_value = 0)
    )
);

create trigger lesson_snapshot_participants_immutable
before update or delete on app.lesson_snapshot_participants
for each row execute function app.reject_immutable_lesson_fact();

alter table app.lesson_client_charge_facts
  drop constraint if exists lesson_client_charge_facts_lesson_id_key;

create unique index if not exists lesson_client_charge_facts_subject_unique_idx
  on app.lesson_client_charge_facts (lesson_id, client_type, client_id);

drop index if exists app.lesson_reservations_one_active_idx;

alter table app.lesson_transitions
  add column if not exists client_financial_fact_ids uuid[] not null
    default '{}'::uuid[];

alter table app.lesson_completion_work
  add column if not exists client_financial_fact_ids uuid[] not null
    default '{}'::uuid[];

alter table app.schedule_series
  drop constraint if exists schedule_series_template_shape_check;
alter table app.schedule_series
  add constraint schedule_series_template_shape_check
  check (
    (
      client_type is null and client_id is null and completion_type is null
      and client_charge_type is null and client_charge_value is null
      and teacher_compensation_type is null
      and teacher_compensation_value is null and subscription_id is null
      and trial is null and occurrence_count is null and timezone_name is null
    )
    or (
      client_type in ('lead', 'student') and client_id is not null
      and timezone_name is not null
      and completion_type ~ '^[A-Za-z0-9._:-]{1,80}$'
      and client_charge_type in ('subscription', 'personal_account', 'none')
      and client_charge_value >= 0
      and teacher_compensation_type in ('fixed', 'hourly', 'none')
      and teacher_compensation_value >= 0 and trial is not null
      and occurrence_count >= 0 and valid_until is not null
      and (
        (client_charge_type = 'subscription' and subscription_id is not null)
        or (client_charge_type <> 'subscription' and subscription_id is null)
      )
    )
  );

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.lesson_snapshot_participants to magiccrm_app;
  end if;
end $$;
