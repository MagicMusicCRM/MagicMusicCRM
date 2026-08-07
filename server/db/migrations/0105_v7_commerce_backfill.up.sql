-- v7 T1.1.4: restartable lossless projection of legacy paid facts.

alter table app.client_payment_records
  drop constraint if exists client_payment_records_paid_shape_check;
alter table app.client_payment_records
  add constraint client_payment_records_paid_shape_check
  check (
    (
      status = 'paid'
      and nullif(btrim(method), '') is not null
      and nullif(btrim(external_identifier), '') is not null
      and actual_payment_id is not null
      and verified_at is not null
      and (
        verified_by is not null
        or verification_note = 'legacy_backfill'
      )
    )
    or (
      status <> 'paid'
      and actual_payment_id is null
      and verified_by is null
      and verified_at is null
    )
  );

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
  raise exception using
    errcode = '23514',
    message = 'payments is an immutable commerce fact';
end;
$$;

drop trigger if exists payments_immutable on app.payments;
create trigger payments_immutable
before update or delete on app.payments
for each row execute function app.protect_v7_payment_fact();

create or replace function app.backfill_v7_commerce()
returns table (
  subscriptions_backfilled bigint,
  payments_backfilled bigint,
  review_rows bigint
)
language plpgsql
as $$
declare
  subscription_count bigint;
  payment_count bigint;
  review_count bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('v7-commerce-backfill', 0));

  update app.subscriptions
  set payer_student_id = student_id,
      funding_mode = 'legacy',
      purchase_reason = null
  where funding_mode is null;
  get diagnostics subscription_count = row_count;

  insert into app.client_payment_records (
    id, student_id, issued_subscription_id, amount_minor, currency_code,
    status, method, external_identifier, verification_note,
    actual_payment_id, version, created_by, verified_by, verified_at,
    created_at, updated_at
  )
  select
    payment.id,
    payment.student_id,
    payment.issued_subscription_id,
    payment.amount_minor,
    upper(coalesce(nullif(btrim(payment.currency), ''), 'RUB')),
    'paid',
    coalesce(nullif(btrim(payment.method), ''), 'legacy_unknown'),
    coalesce(
      nullif(btrim(payment.external_id), ''),
      nullif(btrim(payment.invoice_number), ''),
      'legacy:' || payment.id::text
    ),
    'legacy_backfill',
    payment.id,
    1,
    payment.created_by,
    payment.created_by,
    coalesce(payment.payment_date, payment.created_at),
    payment.created_at,
    payment.created_at
  from app.payments payment
  where payment.deleted_at is null
    and payment.amount_minor > 0
  on conflict (id) do nothing;
  get diagnostics payment_count = row_count;

  insert into app.client_payment_status_events (
    id, payment_record_id, before_status, after_status, reason,
    actor_user_id, aggregate_version, actual_payment_id, occurred_at
  )
  select
    gen_random_uuid(), record.id, null, 'paid',
    'Импорт существующей оплаченной операции', record.created_by,
    1, record.actual_payment_id, record.verified_at
  from app.client_payment_records record
  where record.verification_note = 'legacy_backfill'
    and not exists (
      select 1 from app.client_payment_status_events event
      where event.payment_record_id = record.id
    );

  insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
  select 'commerce:client-payment', record.id::text, record.version
  from app.client_payment_records record
  on conflict (aggregate_type, aggregate_id) do update
  set version = greatest(app.aggregate_versions.version, excluded.version),
      updated_at = now();

  update app.payments payment
  set payment_record_id = record.id
  from app.client_payment_records record
  where record.actual_payment_id = payment.id
    and payment.payment_record_id is null;

  select count(*) into review_count
  from app.payments payment
  where payment.deleted_at is null and payment.amount_minor <= 0;

  return query select subscription_count, payment_count, review_count;
end;
$$;

create or replace function app.reconcile_v7_commerce()
returns table (issue_code text, entity_id text, detail text)
language sql
stable
as $$
  select 'subscription.funding_missing', subscription.id::text,
         'payer/funding legacy backfill missing'
  from app.subscriptions subscription
  where subscription.payer_student_id is null
     or subscription.funding_mode is null

  union all

  select 'payment.linkage_mismatch', payment.id::text,
         'payment and client record do not match bidirectionally'
  from app.payments payment
  left join app.client_payment_records record
    on record.actual_payment_id = payment.id
  where payment.deleted_at is null
    and payment.amount_minor > 0
    and (
      record.id is null
      or payment.payment_record_id is distinct from record.id
      or record.student_id <> payment.student_id
      or record.amount_minor <> payment.amount_minor
      or record.status <> 'paid'
    )

  union all

  select 'payment.event_version_mismatch', record.id::text,
         'latest status event or aggregate version differs from record'
  from app.client_payment_records record
  left join lateral (
    select event.after_status, event.aggregate_version
    from app.client_payment_status_events event
    where event.payment_record_id = record.id
    order by event.aggregate_version desc
    limit 1
  ) latest on true
  left join app.aggregate_versions aggregate
    on aggregate.aggregate_type = 'commerce:client-payment'
   and aggregate.aggregate_id = record.id::text
  where latest.aggregate_version is distinct from record.version
     or latest.after_status is distinct from record.status
     or aggregate.version is distinct from record.version

  union all

  select 'reporting_exclusion.counterpart_mismatch', exclusion.id::text,
         'reversal counterpart is absent or amount/source differs'
  from app.commerce_reporting_exclusions exclusion
  left join app.payments payment
    on exclusion.source_kind = 'payment' and payment.id = exclusion.source_id
  left join app.account_adjustments adjustment
    on exclusion.counterpart_kind = 'account_adjustment'
   and adjustment.id = exclusion.counterpart_id
  where exclusion.source_kind = 'payment'
    and exclusion.counterpart_kind = 'account_adjustment'
    and (
      payment.id is null or adjustment.id is null
      or adjustment.source_payment_id is distinct from payment.id
      or adjustment.amount_minor <> -payment.amount_minor
    )

  order by 1, 2;
$$;

select * from app.backfill_v7_commerce();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant execute on function app.reconcile_v7_commerce() to magiccrm_app;
  end if;
end $$;
