do $$
begin
  if exists (
    select 1
    from app.account_adjustments
    where source_payment_id is not null
       or idempotency_ref is not null
  ) then
    raise exception 'cannot remove commerce reconciliation with payment adjustments present';
  end if;
end
$$;

drop trigger if exists account_adjustments_source_immutable
  on app.account_adjustments;
drop trigger if exists account_adjustments_fill_minor_units
  on app.account_adjustments;
drop function if exists app.fill_account_adjustment_minor_units();
drop index if exists app.account_adjustments_source_payment_idx;
drop index if exists app.account_adjustments_v4_idempotency_idx;

alter table app.account_adjustments
  drop constraint if exists account_adjustments_source_shape_check,
  drop constraint if exists account_adjustments_currency_code_check,
  drop constraint if exists account_adjustments_amount_minor_nonzero,
  drop column if exists request_fingerprint,
  drop column if exists idempotency_ref,
  drop column if exists source_payment_id,
  drop column if exists currency_code,
  drop column if exists amount_minor;
