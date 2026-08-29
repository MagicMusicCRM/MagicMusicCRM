-- Schedule Plan series retain the individual subscription selected for that
-- exact row version. Legacy rows remain readable through the plan fallback.

alter table app.schedule_series
  drop constraint if exists schedule_series_template_shape_check;

alter table app.schedule_series
  add constraint schedule_series_template_shape_check
  check (
    (
      client_type is null and client_id is null and completion_type is null
      and client_charge_type is null and client_charge_value is null
      and teacher_compensation_type is null
      and teacher_compensation_value is null
      and (subscription_id is null or plan_id is not null)
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

create or replace function app.validate_schedule_plan_series_subscription()
returns trigger
language plpgsql
as $$
declare
  plan_kind text;
  plan_subscription_id uuid;
begin
  if tg_op = 'UPDATE'
     and old.subscription_id is not null
     and new.subscription_id is distinct from old.subscription_id then
    raise exception using
      errcode = '23514',
      constraint = 'schedule_series_subscription_snapshot_immutable',
      message = 'schedule series subscription snapshot is immutable';
  end if;
  if new.plan_id is null then
    return new;
  end if;
  select kind, subscription_id into plan_kind, plan_subscription_id
  from app.schedule_plans where id = new.plan_id;
  if plan_kind = 'individual' and new.subscription_id is not null
     and new.subscription_id is distinct from plan_subscription_id then
    raise exception using
      errcode = '23514',
      constraint = 'schedule_series_plan_subscription_snapshot_check',
      message = 'individual plan series must snapshot the plan subscription';
  end if;
  if plan_kind = 'group' and new.subscription_id is not null then
    raise exception using
      errcode = '23514',
      constraint = 'schedule_series_plan_subscription_snapshot_check',
      message = 'group plan series cannot snapshot one subscription';
  end if;
  return new;
end;
$$;

drop trigger if exists schedule_series_validate_plan_subscription
  on app.schedule_series;
create trigger schedule_series_validate_plan_subscription
before insert or update of plan_id, subscription_id on app.schedule_series
for each row execute function app.validate_schedule_plan_series_subscription();
