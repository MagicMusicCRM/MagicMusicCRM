-- v4 T4.2.3: immutable recurring-series template and school-timezone
-- interpretation for atomic series creation.

alter table app.schedule_series
  add column if not exists client_type text,
  add column if not exists client_id uuid,
  add column if not exists timezone_name text,
  add column if not exists completion_type text,
  add column if not exists client_charge_type text,
  add column if not exists client_charge_value numeric(12,2),
  add column if not exists teacher_compensation_type text,
  add column if not exists teacher_compensation_value numeric(12,2),
  add column if not exists subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  add column if not exists trial boolean,
  add column if not exists occurrence_count integer,
  add column if not exists version bigint not null default 1;

alter table app.schedule_series
  drop constraint if exists schedule_series_target_check;

alter table app.schedule_series
  add constraint schedule_series_target_check
  check (
    student_id is not null
    or group_id is not null
    or (
      client_type in ('lead', 'student')
      and client_id is not null
    )
  ),
  add constraint schedule_series_client_ref_check
  check (
    (client_type is null and client_id is null)
    or (client_type in ('lead', 'student') and client_id is not null)
  ),
  add constraint schedule_series_template_shape_check
  check (
    (
      client_type is null
      and client_id is null
      and completion_type is null
      and client_charge_type is null
      and client_charge_value is null
      and teacher_compensation_type is null
      and teacher_compensation_value is null
      and subscription_id is null
      and trial is null
      and occurrence_count is null
      and timezone_name is null
    )
    or (
      client_type in ('lead', 'student')
      and client_id is not null
      and timezone_name is not null
      and completion_type ~ '^[A-Za-z0-9._:-]{1,80}$'
      and client_charge_type in ('subscription', 'personal_account', 'none')
      and client_charge_value >= 0
      and teacher_compensation_type in ('fixed', 'hourly', 'none')
      and teacher_compensation_value >= 0
      and trial is not null
      and occurrence_count > 0
      and valid_until is not null
      and (
        (client_charge_type = 'subscription' and subscription_id is not null)
        or (client_charge_type <> 'subscription' and subscription_id is null)
      )
    )
  ),
  add constraint schedule_series_version_positive
  check (version > 0);

drop trigger if exists schedule_series_validate_timezone
  on app.schedule_series;
create trigger schedule_series_validate_timezone
before insert or update of timezone_name on app.schedule_series
for each row
when (new.timezone_name is not null)
execute function app.assert_schedule_timezone();

create index if not exists schedule_series_client_ref_idx
  on app.schedule_series (client_type, client_id)
  where deleted_at is null and client_id is not null;
