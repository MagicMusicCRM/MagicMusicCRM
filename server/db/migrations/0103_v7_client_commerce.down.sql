do $$
begin
  if exists (select 1 from app.client_payment_status_events)
    or exists (select 1 from app.client_payment_records)
    or exists (select 1 from app.commerce_reporting_exclusions)
    or exists (
      select 1 from app.subscriptions
      where funding_mode is not null
        and (funding_mode <> 'legacy' or payer_student_id <> student_id)
    )
    or exists (
      select 1 from app.user_capability_overrides
      where capability_key in (
        'commerce.client_finance.write', 'config.commerce.manage'
      )
    ) then
    raise exception using
      errcode = '23514',
      message = 'v7 commerce facts exist; rollback would destroy evidence';
  end if;
end $$;

alter table app.payments drop column if exists payment_record_id;

drop trigger if exists commerce_reporting_exclusions_immutable
  on app.commerce_reporting_exclusions;
drop table app.commerce_reporting_exclusions;

drop trigger if exists client_payment_status_events_immutable
  on app.client_payment_status_events;
drop table app.client_payment_status_events;

drop trigger if exists client_payment_records_protect
  on app.client_payment_records;
drop table app.client_payment_records;
drop function app.protect_client_payment_record();

delete from app.role_package_capabilities
where capability_key in (
  'commerce.client_finance.write', 'config.commerce.manage'
);
delete from app.capability_definitions
where capability_key in (
  'commerce.client_finance.write', 'config.commerce.manage'
);

drop index if exists app.subscriptions_v7_payer_status_idx;
drop trigger if exists subscriptions_protect_v7_funding on app.subscriptions;
drop function app.protect_v7_subscription_funding();
alter table app.subscriptions
  drop constraint if exists subscriptions_v7_funding_shape_check,
  drop column if exists purchase_reason,
  drop column if exists funding_mode,
  drop column if exists payer_student_id;
