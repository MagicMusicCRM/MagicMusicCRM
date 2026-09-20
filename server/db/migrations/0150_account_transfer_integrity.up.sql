-- Existing transfer history is retained; new commands bind both immutable legs.
alter table app.account_adjustments add column transfer_peer_id uuid
  references app.account_adjustments(id) on delete restrict deferrable initially deferred;

create function app.validate_account_transfer_pair() returns trigger language plpgsql as $$
begin
  if new.transfer_peer_id is null then return new; end if;
  if not exists (
    select 1 from app.account_adjustments peer
    where peer.id = new.transfer_peer_id and peer.transfer_peer_id = new.id
      and peer.student_id = new.counterparty_student_id
      and peer.counterparty_student_id = new.student_id and peer.student_id <> new.student_id
      and peer.amount_minor = -new.amount_minor and peer.currency_code = new.currency_code
      and peer.occurred_at = new.occurred_at and peer.created_by is not distinct from new.created_by
      and peer.status = 'paid' and new.status = 'paid'
      and peer.deleted_at is null and new.deleted_at is null
      and ((new.kind = 'transfer_out' and new.amount_minor < 0 and peer.kind = 'transfer_in')
        or (new.kind = 'transfer_in' and new.amount_minor > 0 and peer.kind = 'transfer_out'))
  ) then raise exception using errcode='23514', message='Invalid account transfer pair'; end if;
  return new;
end;
$$;
create constraint trigger account_transfer_pair_valid after insert or update on app.account_adjustments
  deferrable initially deferred for each row execute function app.validate_account_transfer_pair();
create trigger account_transfer_immutable before update or delete on app.account_adjustments
  for each row when (old.transfer_peer_id is not null) execute function app.reject_immutable_commerce_fact();

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
  left join app.commerce_ordinary_payments source_payment
    on source_payment.id = adjustment.source_payment_id
  where adjustment.deleted_at is null
    and adjustment.status = 'paid'
    and ((adjustment.kind in ('transfer_in', 'transfer_out') and adjustment.source_payment_id is null)
      or (source_payment.id is not null and source_payment.issued_subscription_id is null))

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
