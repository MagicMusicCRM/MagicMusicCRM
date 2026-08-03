insert into app.payments (
  id,
  student_id,
  amount,
  currency,
  payment_date,
  method,
  external_id,
  notes,
  created_by,
  created_at,
  deleted_at,
  branch_id,
  invoice_number,
  lesson_id
)
select
  adjustment.id,
  adjustment.student_id,
  adjustment.amount,
  coalesce(adjustment.legacy_payment_currency, 'RUB'),
  adjustment.occurred_at,
  adjustment.method,
  adjustment.legacy_payment_external_id,
  adjustment.description,
  adjustment.created_by,
  adjustment.created_at,
  adjustment.deleted_at,
  adjustment.branch_id,
  adjustment.invoice_number,
  adjustment.legacy_payment_lesson_id
from app.account_adjustments adjustment
where adjustment.legacy_payment_migrated_at is not null
on conflict (id) do nothing;

do $$
begin
  if exists (
    select 1
    from app.account_adjustments adjustment
    left join app.payments payment on payment.id = adjustment.id
    where adjustment.legacy_payment_migrated_at is not null
      and payment.id is null
  ) then
    raise exception 'legacy negative payment could not be restored';
  end if;
end
$$;

delete from app.account_adjustments
where legacy_payment_migrated_at is not null;

alter table app.account_adjustments
  drop column if exists legacy_payment_migrated_at,
  drop column if exists legacy_payment_lesson_id,
  drop column if exists legacy_payment_currency,
  drop column if exists legacy_payment_external_id;

