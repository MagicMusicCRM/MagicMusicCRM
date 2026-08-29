do $$
begin
  if exists (
    select 1
    from app.schedule_series series
    where series.plan_id is not null and series.subscription_id is not null
  ) then
    raise exception
      '0142 rollback is unsafe: Plan series subscription snapshots exist; keep migration 0142 and roll back only the application image';
  end if;
end $$;

drop trigger if exists schedule_series_validate_plan_subscription
  on app.schedule_series;
drop function if exists app.validate_schedule_plan_series_subscription();

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
