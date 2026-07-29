-- v4 T5.2.1: align the mutable subscription-package version with the
-- reusable platform aggregate-version registry and retain every catalog
-- version so an idempotent replay can return the exact committed result.

create table if not exists app.subscription_package_versions (
  package_id uuid not null
    references app.subscription_packages(id) on delete restrict,
  version bigint not null,
  name text not null,
  discipline_id uuid,
  branch_id uuid,
  unit_count numeric(6, 2) not null,
  price numeric(12, 2) not null,
  base_price_minor bigint not null,
  currency_code text not null,
  validity_days integer,
  is_active boolean not null,
  sort_order integer not null,
  package_created_at timestamptz not null,
  package_updated_at timestamptz not null,
  archived_at timestamptz,
  recorded_at timestamptz not null default now(),
  primary key (package_id, version),
  constraint subscription_package_versions_version_positive
    check (version > 0),
  constraint subscription_package_versions_unit_count_positive
    check (unit_count > 0),
  constraint subscription_package_versions_price_nonnegative
    check (price >= 0 and base_price_minor >= 0),
  constraint subscription_package_versions_currency_code_check
    check (currency_code ~ '^[A-Z]{3}$')
);

create or replace function app.reject_subscription_package_version_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'subscription package version history is immutable';
end;
$$;

drop trigger if exists subscription_package_versions_immutable
  on app.subscription_package_versions;
create trigger subscription_package_versions_immutable
before update or delete on app.subscription_package_versions
for each row
execute function app.reject_subscription_package_version_mutation();

insert into app.subscription_package_versions (
  package_id,
  version,
  name,
  discipline_id,
  branch_id,
  unit_count,
  price,
  base_price_minor,
  currency_code,
  validity_days,
  is_active,
  sort_order,
  package_created_at,
  package_updated_at,
  archived_at,
  recorded_at
)
select
  package.id,
  package.version,
  package.name,
  package.discipline_id,
  package.branch_id,
  package.lessons_total,
  package.price,
  package.base_price_minor,
  package.currency_code,
  package.validity_days,
  package.is_active and package.deleted_at is null,
  package.sort_order,
  package.created_at,
  package.updated_at,
  package.deleted_at,
  package.updated_at
from app.subscription_packages package
on conflict (package_id, version) do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.subscription_package_versions
      to magiccrm_app;
    revoke update, delete on app.subscription_package_versions
      from magiccrm_app;
  end if;
end $$;

insert into app.aggregate_versions (
  aggregate_type,
  aggregate_id,
  version
)
select
  'commerce:subscription-package',
  package.id::text,
  package.version
from app.subscription_packages package
on conflict (aggregate_type, aggregate_id)
do update set
  version = greatest(app.aggregate_versions.version, excluded.version),
  updated_at = now();
