-- v7 T2.1.3: append-only payment reversal and one reporting boundary.

alter table app.commerce_reporting_exclusions
  drop constraint commerce_reporting_exclusions_audit_event_id_fkey,
  add constraint commerce_reporting_exclusions_audit_event_id_fkey
    foreign key (audit_event_id) references app.audit_events(id)
    on delete restrict deferrable initially deferred;

alter table app.client_payment_records
  drop constraint client_payment_records_installment_id_key;
create index client_payment_records_installment_history_idx
  on app.client_payment_records (installment_id, created_at, id)
  where installment_id is not null;

create or replace view app.commerce_ordinary_payments
with (security_invoker = true) as
select payment.*
from app.payments payment
where not exists (
  select 1
  from app.commerce_reporting_exclusions exclusion
  where (exclusion.source_kind = 'payment'
      and exclusion.source_id = payment.id)
     or (exclusion.counterpart_kind = 'payment'
      and exclusion.counterpart_id = payment.id)
);

create or replace view app.commerce_ordinary_account_adjustments
with (security_invoker = true) as
select adjustment.*
from app.account_adjustments adjustment
where not exists (
  select 1
  from app.commerce_reporting_exclusions exclusion
  where (exclusion.source_kind = 'account_adjustment'
      and exclusion.source_id = adjustment.id)
     or (exclusion.counterpart_kind = 'account_adjustment'
      and exclusion.counterpart_id = adjustment.id)
);

create or replace view app.commerce_ordinary_payment_records
with (security_invoker = true) as
select record.*
from app.client_payment_records record
where not exists (
  select 1
  from app.commerce_reporting_exclusions exclusion
  where (exclusion.source_kind = 'payment_record'
      and exclusion.source_id = record.id)
     or (exclusion.counterpart_kind = 'payment_record'
      and exclusion.counterpart_id = record.id)
     or (record.actual_payment_id is not null and (
       (exclusion.source_kind = 'payment'
        and exclusion.source_id = record.actual_payment_id)
       or (exclusion.counterpart_kind = 'payment'
        and exclusion.counterpart_id = record.actual_payment_id)
     ))
);

create or replace function app.protect_client_payment_record()
returns trigger
language plpgsql
as $$
begin
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

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.commerce_ordinary_payments to magiccrm_app;
    grant select on app.commerce_ordinary_account_adjustments to magiccrm_app;
    grant select on app.commerce_ordinary_payment_records to magiccrm_app;
  end if;
end $$;
