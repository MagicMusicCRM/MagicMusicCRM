-- v7 S4R: append-only post-settlement corrections with effective leaf views.

create table if not exists app.lesson_settlement_corrections (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete restrict,
  version bigint not null check (version > 0),
  supersedes_correction_id uuid references app.lesson_settlement_corrections(id)
    on delete restrict,
  decision jsonb not null,
  settlement_revision_id uuid not null
    references app.crm_configuration_revisions(id) on delete restrict,
  compensation_revision_id uuid not null
    references app.crm_configuration_revisions(id) on delete restrict,
  reason_text text not null check (nullif(btrim(reason_text), '') is not null),
  actor_user_id uuid not null references app.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (lesson_id, version),
  constraint lesson_settlement_corrections_decision_check check (
    jsonb_typeof(decision) = 'object'
    and jsonb_typeof(decision->'settlementTypeKey') = 'string'
    and jsonb_typeof(decision->'teacherCompensationRuleKey') = 'string'
  )
);

create unique index lesson_settlement_corrections_root_idx
  on app.lesson_settlement_corrections (lesson_id)
  where supersedes_correction_id is null;
create unique index lesson_settlement_corrections_supersedes_idx
  on app.lesson_settlement_corrections (supersedes_correction_id)
  where supersedes_correction_id is not null;

alter table app.lesson_client_charge_facts
  add column if not exists correction_id uuid
    references app.lesson_settlement_corrections(id) on delete restrict,
  add column if not exists supersedes_fact_id uuid
    references app.lesson_client_charge_facts(id) on delete restrict;

drop index if exists app.lesson_client_charge_facts_subject_unique_idx;
create unique index lesson_client_charge_facts_root_subject_idx
  on app.lesson_client_charge_facts (lesson_id, client_type, client_id)
  where supersedes_fact_id is null;
create unique index lesson_client_charge_facts_supersedes_idx
  on app.lesson_client_charge_facts (supersedes_fact_id)
  where supersedes_fact_id is not null;
create unique index lesson_client_charge_facts_correction_subject_idx
  on app.lesson_client_charge_facts (correction_id, client_type, client_id)
  where correction_id is not null;

alter table app.lesson_teacher_compensation_facts
  drop constraint if exists lesson_teacher_compensation_facts_lesson_id_key,
  add column if not exists correction_id uuid
    references app.lesson_settlement_corrections(id) on delete restrict,
  add column if not exists supersedes_fact_id uuid
    references app.lesson_teacher_compensation_facts(id) on delete restrict;

create unique index lesson_teacher_compensation_facts_root_idx
  on app.lesson_teacher_compensation_facts (lesson_id)
  where supersedes_fact_id is null;
create unique index lesson_teacher_compensation_facts_supersedes_idx
  on app.lesson_teacher_compensation_facts (supersedes_fact_id)
  where supersedes_fact_id is not null;
create unique index lesson_teacher_compensation_facts_correction_idx
  on app.lesson_teacher_compensation_facts (correction_id)
  where correction_id is not null;

create or replace view app.lesson_client_charge_facts_effective as
select fact.*
from app.lesson_client_charge_facts fact
where not exists (
  select 1 from app.lesson_client_charge_facts newer
  where newer.supersedes_fact_id = fact.id
);

create or replace view app.lesson_teacher_compensation_facts_effective as
select fact.*
from app.lesson_teacher_compensation_facts fact
where not exists (
  select 1 from app.lesson_teacher_compensation_facts newer
  where newer.supersedes_fact_id = fact.id
);

create trigger lesson_settlement_corrections_immutable
before update or delete on app.lesson_settlement_corrections
for each row execute function app.reject_immutable_lesson_fact();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.lesson_settlement_corrections to magiccrm_app;
    grant select on app.lesson_client_charge_facts_effective to magiccrm_app;
    grant select on app.lesson_teacher_compensation_facts_effective to magiccrm_app;
  end if;
end $$;
