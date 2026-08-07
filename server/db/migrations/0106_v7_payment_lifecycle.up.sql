-- v7 T2.1.2: complete the three-state payment lifecycle.

-- Legacy subscriptions are still removable. Returning NEW from a DELETE
-- trigger is NULL and silently cancels deletion, so preserve OLD explicitly.
create or replace function app.protect_v7_subscription_funding()
returns trigger
language plpgsql
as $$
begin
  if old.funding_mode is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  if tg_op = 'DELETE'
    or new.payer_student_id is distinct from old.payer_student_id
    or new.funding_mode is distinct from old.funding_mode
    or new.purchase_reason is distinct from old.purchase_reason then
    raise exception using
      errcode = '23514',
      message = 'issued subscription funding snapshot is immutable';
  end if;
  return new;
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
