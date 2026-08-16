-- Restore the relationship between snapshot-backed legacy subscriptions,
-- their immutable payment facts and the original subscription obligation.

create table app.legacy_subscription_finance_repairs (
  subscription_id uuid primary key
    references app.subscriptions(id) on delete restrict,
  payment_id uuid not null unique
    references app.payments(id) on delete restrict,
  payment_record_id uuid not null unique
    references app.client_payment_records(id) on delete restrict,
  previous_payment_issued_subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  previous_record_issued_subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  obligation_fact_id uuid unique
    references app.subscription_obligation_facts(id)
    on delete restrict deferrable initially deferred,
  repaired_at timestamptz not null default now()
);

create trigger legacy_subscription_finance_repairs_immutable
before update or delete on app.legacy_subscription_finance_repairs
for each row execute function app.reject_immutable_commerce_fact();

create or replace function app.protect_client_payment_record()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
    and old.issued_subscription_id is null
    and new.issued_subscription_id is not null
    and (to_jsonb(new) - 'issued_subscription_id')
      = (to_jsonb(old) - 'issued_subscription_id')
    and exists (
      select 1
      from app.subscriptions subscription
      where subscription.id = new.issued_subscription_id
        and subscription.student_id = old.student_id
        and subscription.payment_id = old.actual_payment_id
        and subscription.final_price_minor = old.amount_minor
    ) then
    return new;
  end if;
  if tg_op = 'DELETE'
    or new.student_id is distinct from old.student_id
    or new.issued_subscription_id is distinct from old.issued_subscription_id
    or new.installment_id is distinct from old.installment_id
    or new.amount_minor is distinct from old.amount_minor
    or new.currency_code is distinct from old.currency_code
    or new.due_at is distinct from old.due_at
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '23514',
      message = 'client payment identity is immutable';
  end if;
  if exists (
    select 1
    from app.commerce_reporting_exclusions exclusion
    where (exclusion.source_kind = 'payment_record'
        and exclusion.source_id = old.id)
       or (old.actual_payment_id is not null
        and exclusion.source_kind = 'payment'
        and exclusion.source_id = old.actual_payment_id)
  ) then
    raise exception using
      errcode = '23514',
      message = 'voided client payment is immutable';
  end if;
  if old.status = 'paid' then
    raise exception using
      errcode = '23514',
      message = 'paid client payment is immutable';
  end if;
  if new.status = old.status
    or new.version <> old.version + 1
    or not (
      (old.status = 'posted_pending' and new.status in ('unpaid', 'paid'))
      or (old.status = 'unpaid' and new.status in ('posted_pending', 'paid'))
    ) then
    raise exception using
      errcode = '23514',
      message = 'invalid client payment status transition';
  end if;
  return new;
end;
$$;

create or replace function app.protect_v7_payment_fact()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
    and old.payment_record_id is null
    and new.payment_record_id is not null
    and (to_jsonb(new) - 'payment_record_id')
      = (to_jsonb(old) - 'payment_record_id')
    and exists (
      select 1 from app.client_payment_records record
      where record.id = new.payment_record_id
        and record.actual_payment_id = old.id
        and record.student_id = old.student_id
        and record.amount_minor = old.amount_minor
    ) then
    return new;
  end if;
  if tg_op = 'UPDATE'
    and old.issued_subscription_id is null
    and new.issued_subscription_id is not null
    and (
      old.payment_record_id is not distinct from new.payment_record_id
      or (old.payment_record_id is null and new.payment_record_id is not null)
    )
    and (to_jsonb(new) - 'payment_record_id' - 'issued_subscription_id')
      = (to_jsonb(old) - 'payment_record_id' - 'issued_subscription_id')
    and exists (
      select 1
      from app.client_payment_records record
      where record.id = new.payment_record_id
        and record.actual_payment_id = old.id
        and record.issued_subscription_id = new.issued_subscription_id
        and record.student_id = old.student_id
        and record.amount_minor = old.amount_minor
    )
    and exists (
      select 1
      from app.subscriptions subscription
      where subscription.id = new.issued_subscription_id
        and subscription.student_id = old.student_id
        and subscription.payment_id = old.id
        and subscription.final_price_minor = old.amount_minor
    ) then
    return new;
  end if;
  raise exception using
    errcode = '23514',
    message = 'payments is an immutable commerce fact';
end;
$$;

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

  insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
  select
    'commerce:issued-subscription',
    subscription.id::text,
    subscription.version
  from app.legacy_subscription_finance_repairs repair
  join app.subscriptions subscription on subscription.id = repair.subscription_id
  on conflict (aggregate_type, aggregate_id) do nothing;

  return repair_count;
end;
$$;

select app.repair_v7_legacy_subscription_finance();

do $$
begin
  if exists (
    select 1
    from app.subscriptions subscription
    left join app.payments payment on payment.id = subscription.payment_id
    left join app.client_payment_records record
      on record.actual_payment_id = payment.id
    where subscription.commercial_snapshot is not null
      and subscription.funding_mode = 'legacy'
      and subscription.payment_id is not null
      and (
        payment.id is null
        or record.id is null
        or payment.issued_subscription_id is distinct from subscription.id
        or record.issued_subscription_id is distinct from subscription.id
        or not exists (
          select 1
          from app.subscription_obligation_facts obligation
          where obligation.issued_subscription_id = subscription.id
            and obligation.direction = 'debit'
        )
      )
  ) then
    raise exception
      'legacy subscription finance reconciliation failed after repair';
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.legacy_subscription_finance_repairs to magiccrm_app;
  end if;
end $$;
