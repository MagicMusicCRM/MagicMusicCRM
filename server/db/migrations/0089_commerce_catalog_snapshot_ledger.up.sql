-- v4 T5.1.2: additive commerce catalog, immutable issued snapshot and
-- append-only payment/ledger facts. Monetary values are stored in minor units.

alter table app.subscription_packages
  add column if not exists base_price_minor bigint,
  add column if not exists currency_code text not null default 'RUB',
  add column if not exists version bigint not null default 1;

update app.subscription_packages
set base_price_minor = round(price * 100)::bigint
where base_price_minor is null;

create or replace function app.sync_subscription_package_minor_units()
returns trigger
language plpgsql
as $$
declare
  price_changed boolean;
  minor_changed boolean;
begin
  if tg_op = 'INSERT' then
    if new.price is null and new.base_price_minor is null then
      raise exception using
        errcode = '23514',
        message = 'subscription package price is required';
    elsif new.base_price_minor is null then
      new.base_price_minor := round(new.price * 100)::bigint;
    elsif new.price is null then
      new.price := new.base_price_minor::numeric / 100;
    elsif new.base_price_minor <> round(new.price * 100)::bigint then
      raise exception using
        errcode = '23514',
        message = 'subscription package price/minor-unit mismatch';
    end if;
    return new;
  end if;

  price_changed := new.price is distinct from old.price;
  minor_changed := new.base_price_minor is distinct from old.base_price_minor;
  if price_changed and minor_changed then
    if new.base_price_minor <> round(new.price * 100)::bigint then
      raise exception using
        errcode = '23514',
        message = 'subscription package price/minor-unit mismatch';
    end if;
  elsif price_changed then
    new.base_price_minor := round(new.price * 100)::bigint;
  elsif minor_changed then
    new.price := new.base_price_minor::numeric / 100;
  end if;
  return new;
end;
$$;

drop trigger if exists subscription_packages_sync_minor_units
  on app.subscription_packages;
create trigger subscription_packages_sync_minor_units
before insert or update of price, base_price_minor
on app.subscription_packages
for each row execute function app.sync_subscription_package_minor_units();

alter table app.subscription_packages
  alter column base_price_minor set not null,
  add constraint subscription_packages_base_price_minor_nonnegative
    check (base_price_minor >= 0),
  add constraint subscription_packages_currency_code_check
    check (currency_code ~ '^[A-Z]{3}$'),
  add constraint subscription_packages_version_positive
    check (version > 0);

create index if not exists subscription_packages_v4_active_idx
  on app.subscription_packages (is_active, sort_order, name, id)
  where deleted_at is null;

alter table app.subscriptions
  add column if not exists commercial_snapshot jsonb,
  add column if not exists snapshot_version integer,
  add column if not exists package_version bigint,
  add column if not exists base_price_minor bigint,
  add column if not exists currency_code text,
  add column if not exists discount_type text,
  add column if not exists discount_percent_basis_points integer,
  add column if not exists discount_fixed_minor bigint,
  add column if not exists discount_reason text,
  add column if not exists final_price_minor bigint,
  add column if not exists version bigint not null default 1;

alter table app.subscriptions
  add constraint subscriptions_version_positive
    check (version > 0),
  add constraint subscriptions_commercial_snapshot_shape
    check (
      (
        commercial_snapshot is null
        and snapshot_version is null
        and package_version is null
        and base_price_minor is null
        and currency_code is null
        and discount_type is null
        and discount_percent_basis_points is null
        and discount_fixed_minor is null
        and discount_reason is null
        and final_price_minor is null
      )
      or
      (
        jsonb_typeof(commercial_snapshot) = 'object'
        and snapshot_version >= 1
        and package_id is not null
        and package_version >= 1
        and base_price_minor >= 0
        and currency_code ~ '^[A-Z]{3}$'
        and final_price_minor >= 0
        and (
          (
            discount_type is null
            and discount_percent_basis_points is null
            and discount_fixed_minor is null
            and discount_reason is null
            and final_price_minor = base_price_minor
          )
          or
          (
            discount_type = 'percent'
            and discount_percent_basis_points between 1 and 10000
            and discount_fixed_minor is null
            and nullif(btrim(discount_reason), '') is not null
            and final_price_minor = greatest(
              0,
              base_price_minor
                - round(
                    base_price_minor::numeric
                      * discount_percent_basis_points
                      / 10000
                  )::bigint
            )
          )
          or
          (
            discount_type = 'fixed'
            and discount_percent_basis_points is null
            and discount_fixed_minor between 1 and base_price_minor
            and nullif(btrim(discount_reason), '') is not null
            and final_price_minor = base_price_minor - discount_fixed_minor
          )
        )
      )
    );

create or replace function app.protect_issued_subscription_snapshot()
returns trigger
language plpgsql
as $$
begin
  if old.commercial_snapshot is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  if tg_op = 'DELETE'
    or new.student_id is distinct from old.student_id
    or new.package_id is distinct from old.package_id
    or new.lessons_total is distinct from old.lessons_total
    or new.starts_at is distinct from old.starts_at
    or new.expires_at is distinct from old.expires_at
    or new.commercial_snapshot is distinct from old.commercial_snapshot
    or new.snapshot_version is distinct from old.snapshot_version
    or new.package_version is distinct from old.package_version
    or new.base_price_minor is distinct from old.base_price_minor
    or new.currency_code is distinct from old.currency_code
    or new.discount_type is distinct from old.discount_type
    or new.discount_percent_basis_points
      is distinct from old.discount_percent_basis_points
    or new.discount_fixed_minor is distinct from old.discount_fixed_minor
    or new.discount_reason is distinct from old.discount_reason
    or new.final_price_minor is distinct from old.final_price_minor then
    raise exception using
      errcode = '23514',
      message = 'issued subscription commercial snapshot is immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists subscriptions_protect_commercial_snapshot
  on app.subscriptions;
create trigger subscriptions_protect_commercial_snapshot
before update or delete on app.subscriptions
for each row execute function app.protect_issued_subscription_snapshot();

create index if not exists subscriptions_v4_client_status_idx
  on app.subscriptions (student_id, status, created_at desc, id)
  where commercial_snapshot is not null;
create index if not exists subscriptions_v4_package_idx
  on app.subscriptions (package_id, created_at desc, id)
  where commercial_snapshot is not null;

create table if not exists app.subscription_installments (
  id uuid primary key default gen_random_uuid(),
  issued_subscription_id uuid not null
    references app.subscriptions(id) on delete restrict,
  installment_number integer not null,
  due_at timestamptz not null,
  amount_minor bigint not null,
  currency_code text not null,
  status text not null default 'pending',
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_installments_number_positive
    check (installment_number > 0),
  constraint subscription_installments_amount_positive
    check (amount_minor > 0),
  constraint subscription_installments_currency_code_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint subscription_installments_status_check
    check (status in ('pending', 'paid', 'void')),
  constraint subscription_installments_version_positive
    check (version > 0),
  unique (issued_subscription_id, installment_number)
);

create index if not exists subscription_installments_due_idx
  on app.subscription_installments (status, due_at, id)
  where status = 'pending';

alter table app.payments
  add column if not exists amount_minor bigint,
  add column if not exists issued_subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  add column if not exists idempotency_ref text,
  add column if not exists request_fingerprint text;

update app.payments
set amount_minor = round(amount * 100)::bigint
where amount_minor is null;

create or replace function app.fill_payment_minor_units()
returns trigger
language plpgsql
as $$
begin
  if new.amount is null and new.amount_minor is null then
    raise exception using
      errcode = '23514',
      message = 'payment amount is required';
  elsif new.amount_minor is null then
    new.amount_minor := round(new.amount * 100)::bigint;
  elsif new.amount is null then
    new.amount := new.amount_minor::numeric / 100;
  elsif new.amount_minor <> round(new.amount * 100)::bigint then
    raise exception using
      errcode = '23514',
      message = 'payment amount/minor-unit mismatch';
  end if;
  return new;
end;
$$;

drop trigger if exists payments_fill_minor_units on app.payments;
create trigger payments_fill_minor_units
before insert on app.payments
for each row execute function app.fill_payment_minor_units();

create or replace function app.reject_immutable_commerce_fact()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = format('%I is an immutable commerce fact', tg_table_name);
end;
$$;

drop trigger if exists payments_immutable on app.payments;
create trigger payments_immutable
before update or delete on app.payments
for each row execute function app.reject_immutable_commerce_fact();

alter table app.payments
  alter column amount_minor set not null,
  add constraint payments_amount_minor_nonnegative
    check (amount_minor >= 0),
  add constraint payments_idempotency_shape
    check (
      (idempotency_ref is null and request_fingerprint is null)
      or (
        nullif(btrim(idempotency_ref), '') is not null
        and nullif(btrim(request_fingerprint), '') is not null
      )
    );

create unique index if not exists payments_v4_idempotency_idx
  on app.payments (student_id, idempotency_ref)
  where idempotency_ref is not null;
create index if not exists payments_v4_issued_idx
  on app.payments (issued_subscription_id, payment_date, id)
  where issued_subscription_id is not null;

create table if not exists app.subscription_obligation_facts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete restrict,
  issued_subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  fact_type text not null,
  direction text not null,
  amount_minor bigint not null,
  currency_code text not null,
  source_type text not null,
  source_ref text not null,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint subscription_obligation_facts_type_check
    check (
      fact_type in (
        'issue',
        'installment',
        'replacement_debt',
        'replacement_overpayment',
        'adjustment',
        'reversal'
      )
    ),
  constraint subscription_obligation_facts_direction_check
    check (direction in ('debit', 'credit')),
  constraint subscription_obligation_facts_amount_nonnegative
    check (amount_minor >= 0),
  constraint subscription_obligation_facts_currency_code_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint subscription_obligation_facts_source_check
    check (
      nullif(btrim(source_type), '') is not null
      and nullif(btrim(source_ref), '') is not null
    ),
  unique (source_type, source_ref)
);

create trigger subscription_obligation_facts_immutable
before update or delete on app.subscription_obligation_facts
for each row execute function app.reject_immutable_commerce_fact();

create index if not exists subscription_obligation_facts_client_idx
  on app.subscription_obligation_facts
    (student_id, occurred_at desc, id);
create index if not exists subscription_obligation_facts_issued_idx
  on app.subscription_obligation_facts
    (issued_subscription_id, occurred_at desc, id)
  where issued_subscription_id is not null;

create table if not exists app.subscription_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  issued_subscription_id uuid not null
    references app.subscriptions(id) on delete restrict,
  event_type text not null,
  before_issued_subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  after_issued_subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  actor_user_id uuid references app.users(id) on delete restrict,
  reason text not null,
  aggregate_version bigint not null,
  occurred_at timestamptz not null default now(),
  constraint subscription_lifecycle_events_type_check
    check (event_type in ('issue', 'replace', 'cancel')),
  constraint subscription_lifecycle_events_reason_check
    check (nullif(btrim(reason), '') is not null),
  constraint subscription_lifecycle_events_version_positive
    check (aggregate_version > 0),
  constraint subscription_lifecycle_events_shape_check
    check (
      (
        event_type = 'issue'
        and before_issued_subscription_id is null
        and after_issued_subscription_id = issued_subscription_id
      )
      or
      (
        event_type = 'replace'
        and before_issued_subscription_id is not null
        and after_issued_subscription_id is not null
        and before_issued_subscription_id
          <> after_issued_subscription_id
        and issued_subscription_id = after_issued_subscription_id
      )
      or
      (
        event_type = 'cancel'
        and before_issued_subscription_id = issued_subscription_id
        and after_issued_subscription_id is null
      )
    )
);

create trigger subscription_lifecycle_events_immutable
before update or delete on app.subscription_lifecycle_events
for each row execute function app.reject_immutable_commerce_fact();

create index if not exists subscription_lifecycle_events_issued_idx
  on app.subscription_lifecycle_events
    (issued_subscription_id, occurred_at desc, id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.subscription_installments to magiccrm_app;
    revoke update, delete on app.subscription_installments
      from magiccrm_app;
    grant update (status, version, updated_at)
      on app.subscription_installments to magiccrm_app;
    grant select, insert on app.subscription_obligation_facts to magiccrm_app;
    grant select, insert on app.subscription_lifecycle_events to magiccrm_app;
    revoke update, delete on app.payments from magiccrm_app;
    revoke update, delete on app.subscription_obligation_facts
      from magiccrm_app;
    revoke update, delete on app.subscription_lifecycle_events
      from magiccrm_app;
  end if;
end $$;
