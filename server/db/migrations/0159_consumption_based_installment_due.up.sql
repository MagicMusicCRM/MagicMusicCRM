alter table app.subscription_installments
  add column if not exists due_policy text not null default 'calendar';

alter table app.subscription_installments
  drop constraint if exists subscription_installments_due_policy_check,
  add constraint subscription_installments_due_policy_check
    check (due_policy in ('calendar', 'consumption'));

create table if not exists app.subscription_installment_due_facts (
  id uuid primary key default gen_random_uuid(),
  installment_id uuid not null unique
    references app.subscription_installments(id) on delete restrict,
  due_at timestamptz not null,
  trigger_charge_fact_id uuid
    references app.lesson_client_charge_facts(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists subscription_installment_due_facts_due_idx
  on app.subscription_installment_due_facts (due_at, installment_id);

drop trigger if exists subscription_installment_due_facts_immutable
  on app.subscription_installment_due_facts;
create trigger subscription_installment_due_facts_immutable
before update or delete on app.subscription_installment_due_facts
for each row execute function app.reject_immutable_commerce_fact();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.subscription_installment_due_facts
      to magiccrm_app;
    grant select (due_policy) on app.subscription_installments
      to magiccrm_app;
  end if;
end $$;
