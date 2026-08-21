-- Restoring the previous function must not remove append-only aggregate facts
-- already created by the upgrade.

create or replace function app.repair_v7_legacy_subscription_finance()
returns bigint
language plpgsql
as $$
declare
  repair_count bigint;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('v7-legacy-subscription-finance-repair', 0)
  );

  insert into app.legacy_subscription_finance_repairs (
    subscription_id, payment_id, payment_record_id,
    previous_payment_issued_subscription_id,
    previous_record_issued_subscription_id, obligation_fact_id
  )
  select
    subscription.id, payment.id, record.id,
    payment.issued_subscription_id, record.issued_subscription_id,
    case when exists (
      select 1 from app.subscription_obligation_facts obligation
      where obligation.issued_subscription_id = subscription.id
        and obligation.direction = 'debit'
    ) then null else gen_random_uuid() end
  from app.subscriptions subscription
  join app.payments payment on payment.id = subscription.payment_id
  join app.client_payment_records record
    on record.actual_payment_id = payment.id
  where subscription.commercial_snapshot is not null
    and subscription.funding_mode = 'legacy'
    and payment.deleted_at is null
    and payment.student_id = subscription.student_id
    and payment.amount_minor = subscription.final_price_minor
    and record.student_id = subscription.student_id
    and record.amount_minor = subscription.final_price_minor
    and record.status = 'paid'
    and (payment.payment_record_id is null
      or payment.payment_record_id = record.id)
    and (payment.issued_subscription_id is null
      or payment.issued_subscription_id = subscription.id)
    and (record.issued_subscription_id is null
      or record.issued_subscription_id = subscription.id)
    and (
      payment.issued_subscription_id is null
      or record.issued_subscription_id is null
      or not exists (
        select 1 from app.subscription_obligation_facts obligation
        where obligation.issued_subscription_id = subscription.id
          and obligation.direction = 'debit'
      )
    )
    and (select count(*) from app.subscriptions candidate
      where candidate.payment_id = payment.id) = 1
    and not exists (
      select 1 from app.legacy_subscription_finance_repairs repair
      where repair.subscription_id = subscription.id
    );
  get diagnostics repair_count = row_count;

  update app.client_payment_records record
  set issued_subscription_id = repair.subscription_id
  from app.legacy_subscription_finance_repairs repair
  where record.id = repair.payment_record_id
    and repair.previous_record_issued_subscription_id is null
    and record.issued_subscription_id is null;

  update app.payments payment
  set payment_record_id = coalesce(
        payment.payment_record_id, repair.payment_record_id
      ),
      issued_subscription_id = repair.subscription_id
  from app.legacy_subscription_finance_repairs repair
  where payment.id = repair.payment_id
    and repair.previous_payment_issued_subscription_id is null
    and payment.issued_subscription_id is null;

  insert into app.subscription_obligation_facts (
    id, student_id, issued_subscription_id, fact_type, direction,
    amount_minor, currency_code, source_type, source_ref, occurred_at
  )
  select
    repair.obligation_fact_id,
    subscription.student_id,
    subscription.id,
    'issue',
    'debit',
    subscription.final_price_minor,
    subscription.currency_code,
    'subscription.issue',
    subscription.id::text,
    subscription.created_at
  from app.legacy_subscription_finance_repairs repair
  join app.subscriptions subscription on subscription.id = repair.subscription_id
  where repair.obligation_fact_id is not null
    and not exists (
      select 1 from app.subscription_obligation_facts obligation
      where obligation.issued_subscription_id = subscription.id
        and obligation.direction = 'debit'
    );

  return repair_count;
end;
$$;
