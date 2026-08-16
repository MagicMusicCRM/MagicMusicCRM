do $$
begin
  if exists (select 1 from app.legacy_subscription_finance_repairs) then
    raise exception
      'cannot remove legacy subscription finance repair with repair facts present';
  end if;
end $$;

drop function if exists app.repair_v7_legacy_subscription_finance();
drop trigger if exists legacy_subscription_finance_repairs_immutable
  on app.legacy_subscription_finance_repairs;
drop table if exists app.legacy_subscription_finance_repairs;

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
