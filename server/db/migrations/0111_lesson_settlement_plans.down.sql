do $$
begin
  if exists (select 1 from app.lesson_settlement_plans)
    or exists (
      select 1 from app.schedule_series
      where planned_financial_decision is not null
    ) then
    raise exception
      'Refusing destructive rollback: planned lesson settlements exist';
  end if;
end $$;

alter table app.schedule_series
  drop constraint if exists schedule_series_settlement_plan_shape_check,
  drop column if exists compensation_revision_id,
  drop column if exists settlement_revision_id,
  drop column if exists planned_financial_decision;

drop table if exists app.lesson_settlement_plans;
