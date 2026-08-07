-- v7 S4R: immutable staff-visible history of pre-start settlement decisions.

create table if not exists app.lesson_settlement_plan_revisions (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete restrict,
  version bigint not null check (version > 0),
  decision jsonb not null,
  settlement_revision_id uuid not null
    references app.crm_configuration_revisions(id) on delete restrict,
  compensation_revision_id uuid not null
    references app.crm_configuration_revisions(id) on delete restrict,
  reason_text text,
  actor_user_id uuid not null references app.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (lesson_id, version),
  constraint lesson_settlement_plan_revisions_decision_check check (
    jsonb_typeof(decision) = 'object'
    and jsonb_typeof(decision->'settlementTypeKey') = 'string'
    and jsonb_typeof(decision->'teacherCompensationRuleKey') = 'string'
  ),
  constraint lesson_settlement_plan_revisions_reason_check check (
    reason_text is null or nullif(btrim(reason_text), '') is not null
  )
);

insert into app.lesson_settlement_plan_revisions (
  lesson_id, version, decision, settlement_revision_id,
  compensation_revision_id, reason_text, actor_user_id, created_at
)
select plan.lesson_id, plan.version, plan.decision,
  plan.settlement_revision_id, plan.compensation_revision_id,
  plan.reason_text, plan.selected_by, plan.selected_at
from app.lesson_settlement_plans plan
join app.users actor on actor.id = plan.selected_by
on conflict (lesson_id, version) do nothing;

create trigger lesson_settlement_plan_revisions_immutable
before update or delete on app.lesson_settlement_plan_revisions
for each row execute function app.reject_immutable_lesson_fact();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.lesson_settlement_plan_revisions to magiccrm_app;
  end if;
end $$;
