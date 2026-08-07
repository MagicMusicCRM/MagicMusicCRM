do $$
begin
  if exists (select 1 from app.client_payment_records)
    or exists (select 1 from app.client_payment_status_events)
    or exists (select 1 from app.commerce_reporting_exclusions) then
    raise exception using
      errcode = '23514',
      message = 'v7 payment projections exist; rollback would destroy evidence';
  end if;
end $$;

drop function if exists app.reconcile_v7_commerce();
drop function if exists app.backfill_v7_commerce();

drop trigger if exists payments_immutable on app.payments;
drop function if exists app.protect_v7_payment_fact();
create trigger payments_immutable
before update or delete on app.payments
for each row execute function app.reject_immutable_commerce_fact();

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
      and verified_by is not null
      and verified_at is not null
    )
    or (
      status <> 'paid'
      and actual_payment_id is null
      and verified_by is null
      and verified_at is null
    )
  );
