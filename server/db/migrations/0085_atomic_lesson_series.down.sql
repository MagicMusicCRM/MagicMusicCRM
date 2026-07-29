do $$
begin
  if exists (
    select 1
    from app.schedule_series
    where client_type is not null
       or completion_type is not null
  ) then
    raise exception
      'Refusing destructive rollback: atomic lesson series exist';
  end if;
end $$;

drop index if exists app.schedule_series_client_ref_idx;
drop trigger if exists schedule_series_validate_timezone
  on app.schedule_series;

alter table app.schedule_series
  drop constraint if exists schedule_series_version_positive,
  drop constraint if exists schedule_series_template_shape_check,
  drop constraint if exists schedule_series_client_ref_check,
  drop constraint if exists schedule_series_target_check;

alter table app.schedule_series
  add constraint schedule_series_target_check
  check (student_id is not null or group_id is not null);

alter table app.schedule_series
  drop column if exists version,
  drop column if exists occurrence_count,
  drop column if exists trial,
  drop column if exists subscription_id,
  drop column if exists teacher_compensation_value,
  drop column if exists teacher_compensation_type,
  drop column if exists client_charge_value,
  drop column if exists client_charge_type,
  drop column if exists completion_type,
  drop column if exists timezone_name,
  drop column if exists client_id,
  drop column if exists client_type;
