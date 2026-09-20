-- A rollback must not hide committed transfer balances or remove their history.
do $$ begin
  if exists(select 1 from app.account_adjustments where transfer_peer_id is not null) then
    raise exception 'Cannot roll back account transfer integrity after a transfer was committed';
  end if;
end $$;
drop trigger account_transfer_pair_valid on app.account_adjustments;
drop trigger account_transfer_immutable on app.account_adjustments;
drop function app.validate_account_transfer_pair();
alter table app.account_adjustments drop column transfer_peer_id;
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
    coalesce(lesson_charge.payer_student_id, lesson_charge.client_id),
    lesson_charge.currency_code,
    0::numeric,
    0::numeric,
    0::numeric,
    0::numeric,
    lesson_charge.amount_minor::numeric,
    0::numeric,
    0::numeric
  from app.lesson_client_charge_facts_effective lesson_charge
  where lesson_charge.payer_student_id is not null or lesson_charge.client_type = 'student'

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
