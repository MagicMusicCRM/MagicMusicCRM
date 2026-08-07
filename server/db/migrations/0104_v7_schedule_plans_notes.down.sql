do $$
begin
  if exists (select 1 from app.schedule_plans)
    or exists (select 1 from app.schedule_plan_participants)
    or exists (select 1 from app.client_internal_notes)
    or exists (select 1 from app.schedule_series where plan_id is not null)
    or exists (
      select 1 from app.lesson_client_charge_facts
      where settlement_type_key is not null
    )
    or exists (
      select 1 from app.lesson_teacher_compensation_facts
      where compensation_rule_key is not null
    ) then
    raise exception using
      errcode = '23514',
      message = 'v7 schedule/note facts exist; rollback would destroy evidence';
  end if;
end $$;

drop table app.client_internal_notes;

alter table app.lesson_teacher_compensation_facts
  drop constraint if exists lesson_teacher_compensation_facts_shape_check,
  drop constraint if exists lesson_teacher_compensation_facts_v7_snapshot_shape_check,
  drop constraint if exists lesson_teacher_compensation_facts_type_check,
  drop column if exists configuration_revision_id,
  drop column if exists compensation_override_reason,
  drop column if exists compensation_actual_value,
  drop column if exists compensation_default_value,
  drop column if exists compensation_mode,
  drop column if exists compensation_rule_label,
  drop column if exists compensation_rule_key;
alter table app.lesson_teacher_compensation_facts
  add constraint lesson_teacher_compensation_facts_type_check
    check (compensation_type in ('fixed', 'hourly', 'none')),
  add constraint lesson_teacher_compensation_facts_shape_check
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
      compensation_type = 'none' and snapshot_rate = 0
      and rate_minor = 0 and amount_minor = 0
    )
  );

alter table app.lesson_client_charge_facts
  drop constraint if exists lesson_client_charge_facts_shape_check,
  drop constraint if exists lesson_client_charge_facts_v7_snapshot_shape_check,
  drop column if exists configuration_revision_id,
  drop column if exists fixed_penalty_minor,
  drop column if exists hour_share_basis_points,
  drop column if exists settlement_color_token,
  drop column if exists settlement_label,
  drop column if exists settlement_type_key;
alter table app.lesson_client_charge_facts
  add constraint lesson_client_charge_facts_shape_check
  check (
    (
      charge_type = 'subscription' and subscription_id is not null
      and amount_minor = 0 and units = snapshot_value
    )
    or (
      charge_type = 'personal_account' and subscription_id is null
      and amount_minor = round(snapshot_value * 100)::bigint and units = 0
    )
    or (
      charge_type = 'none' and subscription_id is null
      and snapshot_value = 0 and amount_minor = 0 and units = 0
    )
  );

drop index if exists app.schedule_series_plan_idx;
alter table app.schedule_series drop column if exists plan_id;

drop trigger if exists schedule_plan_participants_validate
  on app.schedule_plan_participants;
drop table app.schedule_plan_participants;
drop function app.validate_schedule_plan_participant();

drop trigger if exists schedule_plans_validate_relations on app.schedule_plans;
drop table app.schedule_plans;
drop function app.validate_schedule_plan_relations();
