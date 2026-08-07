-- v7 S4R: every new lesson carries an explicit, revision-pinned settlement plan.

create table if not exists app.lesson_settlement_plans (
  lesson_id uuid primary key references app.lessons(id) on delete restrict,
  decision jsonb not null,
  settlement_revision_id uuid not null
    references app.crm_configuration_revisions(id) on delete restrict,
  compensation_revision_id uuid not null
    references app.crm_configuration_revisions(id) on delete restrict,
  version bigint not null default 1 check (version > 0),
  state text not null default 'planned',
  failure_code text,
  reason_text text,
  selected_by uuid references app.users(id) on delete restrict,
  selected_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lesson_settlement_plans_decision_check check (
    jsonb_typeof(decision) = 'object'
    and jsonb_typeof(decision->'settlementTypeKey') = 'string'
    and jsonb_typeof(decision->'teacherCompensationRuleKey') = 'string'
  ),
  constraint lesson_settlement_plans_state_check check (
    state in ('planned', 'settled', 'review_required', 'cancelled')
  ),
  constraint lesson_settlement_plans_failure_check check (
    (state = 'review_required' and nullif(btrim(failure_code), '') is not null)
    or (state <> 'review_required' and failure_code is null)
  ),
  constraint lesson_settlement_plans_reason_check check (
    reason_text is null or nullif(btrim(reason_text), '') is not null
  )
);

create index if not exists lesson_settlement_plans_state_idx
  on app.lesson_settlement_plans (state, updated_at, lesson_id);

alter table app.schedule_series
  add column if not exists planned_financial_decision jsonb,
  add column if not exists settlement_revision_id uuid
    references app.crm_configuration_revisions(id) on delete restrict,
  add column if not exists compensation_revision_id uuid
    references app.crm_configuration_revisions(id) on delete restrict;

alter table app.schedule_series
  drop constraint if exists schedule_series_settlement_plan_shape_check,
  add constraint schedule_series_settlement_plan_shape_check check (
    (planned_financial_decision is null
      and settlement_revision_id is null
      and compensation_revision_id is null)
    or (
      jsonb_typeof(planned_financial_decision) = 'object'
      and jsonb_typeof(planned_financial_decision->'settlementTypeKey') = 'string'
      and jsonb_typeof(planned_financial_decision->'teacherCompensationRuleKey') = 'string'
      and settlement_revision_id is not null
      and compensation_revision_id is not null
    )
  );

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.lesson_settlement_plans to magiccrm_app;
  end if;
end $$;
