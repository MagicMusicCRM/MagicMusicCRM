do $$
begin
  if exists (select 1 from app.commerce_reporting_exclusions) then
    raise exception 'cannot remove payment reversal views with exclusion facts present';
  end if;
end $$;

drop view if exists app.commerce_ordinary_payment_records;
drop view if exists app.commerce_ordinary_account_adjustments;
drop view if exists app.commerce_ordinary_payments;

drop index if exists app.client_payment_records_installment_history_idx;
alter table app.client_payment_records
  drop constraint if exists client_payment_records_installment_id_key,
  add constraint client_payment_records_installment_id_key
    unique (installment_id);

alter table app.commerce_reporting_exclusions
  drop constraint commerce_reporting_exclusions_audit_event_id_fkey,
  add constraint commerce_reporting_exclusions_audit_event_id_fkey
    foreign key (audit_event_id) references app.audit_events(id)
    on delete restrict;

-- Restore the T2.1.2 transition guard.
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
