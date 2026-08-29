create or replace view app.commerce_student_account_projection
with (security_invoker = true) as
with monetary_facts as (
  select
    payment.student_id,
    upper(coalesce(nullif(btrim(payment.currency), ''), 'RUB')) as currency_code,
    payment.amount_minor::numeric as actual_payment_minor,
    0::numeric as adjustment_minor,
    0::numeric as obligation_debit_minor,
    0::numeric as obligation_credit_minor,
    0::numeric as write_off_minor,
    0::numeric as pending_minor,
    0::numeric as debt_minor
  from app.commerce_ordinary_payments payment
  where payment.deleted_at is null
    and payment.amount_minor is not null
    and payment.issued_subscription_id is null

  union all

  select
    lesson_charge.client_id,
    lesson_charge.currency_code,
    0::numeric,
    0::numeric,
    0::numeric,
    0::numeric,
    lesson_charge.amount_minor::numeric,
    0::numeric,
    0::numeric
  from app.lesson_client_charge_facts_effective lesson_charge
  where lesson_charge.client_type = 'student'

  union all

  select
    adjustment.student_id,
    adjustment.currency_code,
    0::numeric,
    adjustment.amount_minor::numeric,
    0::numeric,
    0::numeric,
    0::numeric,
    0::numeric,
    0::numeric
  from app.commerce_ordinary_account_adjustments adjustment
  join app.commerce_ordinary_payments source_payment
    on source_payment.id = adjustment.source_payment_id
  where adjustment.deleted_at is null
    and adjustment.status = 'paid'
    and source_payment.issued_subscription_id is null

  union all

  select
    record.student_id,
    record.currency_code,
    0::numeric,
    0::numeric,
    0::numeric,
    0::numeric,
    0::numeric,
    case when record.status = 'posted_pending'
      then record.amount_minor::numeric else 0::numeric end,
    case when record.status = 'unpaid'
      then record.amount_minor::numeric else 0::numeric end
  from app.commerce_ordinary_payment_records record
  where record.issued_subscription_id is null
)
select
  student_id,
  currency_code,
  sum(actual_payment_minor)::bigint as actual_payments_minor,
  sum(adjustment_minor)::bigint as adjustments_minor,
  sum(obligation_debit_minor)::bigint as obligation_debits_minor,
  sum(obligation_credit_minor)::bigint as obligation_credits_minor,
  sum(write_off_minor)::bigint as write_offs_minor,
  sum(pending_minor)::bigint as pending_minor,
  sum(debt_minor)::bigint as debt_minor,
  (
    sum(actual_payment_minor)
    + sum(adjustment_minor)
    + sum(obligation_credit_minor)
    - sum(obligation_debit_minor)
    - sum(write_off_minor)
  )::bigint as balance_minor,
  greatest(
    -(
      sum(actual_payment_minor)
      + sum(adjustment_minor)
      + sum(obligation_credit_minor)
      - sum(obligation_debit_minor)
      - sum(write_off_minor)
    ),
    0
  )::bigint as remaining_obligation_minor
from monetary_facts
group by student_id, currency_code;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.commerce_student_account_projection to magiccrm_app;
  end if;
end $$;
