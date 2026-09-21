do $$
begin
  if exists (
    select 1 from app.subscription_installment_due_facts
  ) or exists (
    select 1 from app.subscription_installments
    where due_policy = 'consumption'
  ) then
    raise exception
      'refusing to remove consumption-based installment due facts';
  end if;
end $$;

drop trigger if exists subscription_installment_due_facts_immutable
  on app.subscription_installment_due_facts;
drop table if exists app.subscription_installment_due_facts;
alter table app.subscription_installments
  drop constraint if exists subscription_installments_due_policy_check,
  drop column if exists due_policy;
