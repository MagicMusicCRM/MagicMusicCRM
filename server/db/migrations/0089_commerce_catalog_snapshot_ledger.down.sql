do $$
begin
  if exists (
    select 1 from app.subscriptions where commercial_snapshot is not null
  )
    or exists (select 1 from app.subscription_installments)
    or exists (select 1 from app.subscription_obligation_facts)
    or exists (select 1 from app.subscription_lifecycle_events)
    or exists (
      select 1
      from app.payments
      where issued_subscription_id is not null
        or idempotency_ref is not null
    ) then
    raise exception using
      errcode = '23514',
      message = 'v4 commerce facts exist; rollback would destroy immutable evidence';
  end if;
end $$;

drop trigger if exists subscription_lifecycle_events_immutable
  on app.subscription_lifecycle_events;
drop table if exists app.subscription_lifecycle_events;

drop trigger if exists subscription_obligation_facts_immutable
  on app.subscription_obligation_facts;
drop table if exists app.subscription_obligation_facts;

drop table if exists app.subscription_installments;

drop index if exists app.payments_v4_issued_idx;
drop index if exists app.payments_v4_idempotency_idx;
drop trigger if exists payments_immutable on app.payments;
drop trigger if exists payments_fill_minor_units on app.payments;
alter table app.payments
  drop constraint if exists payments_idempotency_shape,
  drop constraint if exists payments_amount_minor_nonnegative,
  drop column if exists request_fingerprint,
  drop column if exists idempotency_ref,
  drop column if exists issued_subscription_id,
  drop column if exists amount_minor;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant update, delete on app.payments to magiccrm_app;
  end if;
end $$;
drop function if exists app.fill_payment_minor_units();
drop function if exists app.reject_immutable_commerce_fact();

drop index if exists app.subscriptions_v4_package_idx;
drop index if exists app.subscriptions_v4_client_status_idx;
drop trigger if exists subscriptions_protect_commercial_snapshot
  on app.subscriptions;
alter table app.subscriptions
  drop constraint if exists subscriptions_commercial_snapshot_shape,
  drop constraint if exists subscriptions_version_positive,
  drop column if exists version,
  drop column if exists final_price_minor,
  drop column if exists discount_reason,
  drop column if exists discount_fixed_minor,
  drop column if exists discount_percent_basis_points,
  drop column if exists discount_type,
  drop column if exists currency_code,
  drop column if exists base_price_minor,
  drop column if exists package_version,
  drop column if exists snapshot_version,
  drop column if exists commercial_snapshot;
drop function if exists app.protect_issued_subscription_snapshot();

drop index if exists app.subscription_packages_v4_active_idx;
drop trigger if exists subscription_packages_sync_minor_units
  on app.subscription_packages;
alter table app.subscription_packages
  drop constraint if exists subscription_packages_version_positive,
  drop constraint if exists subscription_packages_currency_code_check,
  drop constraint if exists subscription_packages_base_price_minor_nonnegative,
  drop column if exists version,
  drop column if exists currency_code,
  drop column if exists base_price_minor;
drop function if exists app.sync_subscription_package_minor_units();
