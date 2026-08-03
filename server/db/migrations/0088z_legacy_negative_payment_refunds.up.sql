-- Legacy HolliHop refunds were imported into app.payments as negative rows.
-- v4 keeps actual payments non-negative and records refunds in the signed
-- account-adjustment ledger, so move them losslessly before migration 0089
-- installs the immutable payment boundary.
alter table app.account_adjustments
  add column if not exists legacy_payment_external_id text,
  add column if not exists legacy_payment_currency text,
  add column if not exists legacy_payment_lesson_id uuid,
  add column if not exists legacy_payment_migrated_at timestamptz;

insert into app.account_adjustments (
  id,
  student_id,
  branch_id,
  kind,
  amount,
  description,
  method,
  occurred_at,
  created_by,
  created_at,
  deleted_at,
  invoice_number,
  status,
  legacy_payment_external_id,
  legacy_payment_currency,
  legacy_payment_lesson_id,
  legacy_payment_migrated_at
)
select
  payment.id,
  payment.student_id,
  payment.branch_id,
  'refund',
  payment.amount,
  payment.notes,
  payment.method,
  coalesce(payment.payment_date, payment.created_at),
  payment.created_by,
  payment.created_at,
  payment.deleted_at,
  payment.invoice_number,
  case when payment.deleted_at is null then 'paid' else 'void' end,
  payment.external_id,
  payment.currency,
  payment.lesson_id,
  now()
from app.payments payment
where payment.amount < 0
on conflict (id) do nothing;

do $$
begin
  if exists (
    select 1
    from app.payments payment
    left join app.account_adjustments adjustment on adjustment.id = payment.id
    where payment.amount < 0
      and (
        adjustment.id is null
        or adjustment.legacy_payment_migrated_at is null
        or adjustment.student_id <> payment.student_id
        or adjustment.amount <> payment.amount
      )
  ) then
    raise exception 'legacy negative payment could not be preserved as an account adjustment';
  end if;
end
$$;

delete from app.payments payment
using app.account_adjustments adjustment
where payment.amount < 0
  and adjustment.id = payment.id
  and adjustment.legacy_payment_migrated_at is not null;

do $$
begin
  if exists (select 1 from app.payments where amount < 0) then
    raise exception 'negative payments remain after legacy refund migration';
  end if;
end
$$;

