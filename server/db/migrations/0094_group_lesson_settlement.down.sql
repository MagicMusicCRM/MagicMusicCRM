do $$
begin
  if exists (select 1 from app.lesson_snapshot_participants)
    or exists (select 1 from app.lesson_snapshots where group_id is not null)
    or exists (
      select 1 from app.lesson_client_charge_facts
      group by lesson_id having count(*) > 1
    )
    or exists (
      select 1 from app.lesson_reservations
      where state = 'reserved'
      group by lesson_id having count(*) > 1
    )
    or exists (
      select 1 from app.schedule_series
      where occurrence_count = 0 and client_type is not null
    ) then
    raise exception 'Cannot roll back 0094 while group settlement data exists';
  end if;
end $$;

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
      and occurrence_count > 0 and valid_until is not null
      and (
        (client_charge_type = 'subscription' and subscription_id is not null)
        or (client_charge_type <> 'subscription' and subscription_id is null)
      )
    )
  );

alter table app.lesson_completion_work
  drop column if exists client_financial_fact_ids;
alter table app.lesson_transitions
  drop column if exists client_financial_fact_ids;

create unique index if not exists lesson_reservations_one_active_idx
  on app.lesson_reservations (lesson_id)
  where state = 'reserved';

drop index if exists app.lesson_client_charge_facts_subject_unique_idx;
alter table app.lesson_client_charge_facts
  add constraint lesson_client_charge_facts_lesson_id_key unique (lesson_id);

drop trigger if exists lesson_snapshot_participants_immutable
  on app.lesson_snapshot_participants;
drop table if exists app.lesson_snapshot_participants;

drop trigger if exists lesson_snapshots_immutable on app.lesson_snapshots;
drop function if exists app.guard_lesson_snapshot_immutable();

alter table app.lesson_snapshots
  drop constraint if exists lesson_snapshots_subject_check,
  drop constraint if exists lesson_snapshots_subscription_check,
  drop column if exists group_id;

alter table app.lesson_snapshots
  alter column client_type set not null,
  alter column client_id set not null,
  add constraint lesson_snapshots_client_type_check
    check (client_type in ('lead', 'student')),
  add constraint lesson_snapshots_subscription_check
    check (
      validation_state = 'legacy_incomplete'
      or (
        (client_charge_type = 'subscription' and subscription_id is not null)
        or (client_charge_type <> 'subscription' and subscription_id is null)
      )
    );

create trigger lesson_snapshots_immutable
before update or delete on app.lesson_snapshots
for each row execute function app.reject_immutable_lesson_fact();
