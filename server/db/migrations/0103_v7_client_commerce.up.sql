-- v7 T1.1.2: payer-aware subscriptions, three-state client payments,
-- immutable status history and reporting exclusions.

alter table app.subscriptions
  add column if not exists payer_student_id uuid
    references app.students(id) on delete restrict,
  add column if not exists funding_mode text,
  add column if not exists purchase_reason text;

alter table app.subscriptions
  add constraint subscriptions_v7_funding_shape_check
  check (
    (payer_student_id is null and funding_mode is null and purchase_reason is null)
    or (
      payer_student_id is not null
      and funding_mode in ('personal_account', 'installment', 'legacy')
      and (
        payer_student_id = student_id
        or nullif(btrim(purchase_reason), '') is not null
      )
    )
  );

create or replace function app.protect_v7_subscription_funding()
returns trigger
language plpgsql
as $$
begin
  if old.funding_mode is null then
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

drop trigger if exists subscriptions_protect_v7_funding on app.subscriptions;
create trigger subscriptions_protect_v7_funding
before update or delete on app.subscriptions
for each row execute function app.protect_v7_subscription_funding();

create index if not exists subscriptions_v7_payer_status_idx
  on app.subscriptions (payer_student_id, status, created_at desc, id)
  where payer_student_id is not null;

create table app.client_payment_records (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete restrict,
  issued_subscription_id uuid
    references app.subscriptions(id) on delete restrict,
  installment_id uuid unique
    references app.subscription_installments(id) on delete restrict,
  amount_minor bigint not null,
  currency_code text not null,
  status text not null,
  due_at timestamptz,
  method text,
  external_identifier text,
  verification_note text,
  actual_payment_id uuid unique references app.payments(id) on delete restrict,
  version bigint not null default 1,
  created_by uuid references app.users(id) on delete restrict,
  verified_by uuid references app.users(id) on delete restrict,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_payment_records_amount_positive check (amount_minor > 0),
  constraint client_payment_records_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint client_payment_records_status_check
    check (status in ('unpaid', 'posted_pending', 'paid')),
  constraint client_payment_records_version_positive check (version > 0),
  constraint client_payment_records_paid_shape_check
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
    )
);

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
      or (old.status = 'unpaid' and new.status = 'paid')
    ) then
    raise exception using
      errcode = '23514',
      message = 'invalid client payment status transition';
  end if;
  return new;
end;
$$;

create trigger client_payment_records_protect
before update or delete on app.client_payment_records
for each row execute function app.protect_client_payment_record();

create index client_payment_records_student_idx
  on app.client_payment_records (student_id, created_at desc, id);
create index client_payment_records_due_idx
  on app.client_payment_records (status, due_at, id)
  where status in ('unpaid', 'posted_pending');
create index client_payment_records_subscription_idx
  on app.client_payment_records (issued_subscription_id, created_at desc, id)
  where issued_subscription_id is not null;

create table app.client_payment_status_events (
  id uuid primary key default gen_random_uuid(),
  payment_record_id uuid not null
    references app.client_payment_records(id) on delete restrict,
  before_status text,
  after_status text not null,
  reason text not null,
  actor_user_id uuid references app.users(id) on delete restrict,
  aggregate_version bigint not null,
  actual_payment_id uuid references app.payments(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  constraint client_payment_status_events_before_check
    check (before_status is null or before_status in ('unpaid', 'posted_pending', 'paid')),
  constraint client_payment_status_events_after_check
    check (after_status in ('unpaid', 'posted_pending', 'paid')),
  constraint client_payment_status_events_reason_check
    check (nullif(btrim(reason), '') is not null),
  constraint client_payment_status_events_version_positive
    check (aggregate_version > 0),
  constraint client_payment_status_events_initial_shape
    check (
      (before_status is null and aggregate_version = 1)
      or before_status is not null
    ),
  unique (payment_record_id, aggregate_version)
);

create trigger client_payment_status_events_immutable
before update or delete on app.client_payment_status_events
for each row execute function app.reject_immutable_commerce_fact();

create index client_payment_status_events_record_idx
  on app.client_payment_status_events
    (payment_record_id, aggregate_version, occurred_at, id);

create table app.commerce_reporting_exclusions (
  id uuid primary key default gen_random_uuid(),
  source_kind text not null,
  source_id uuid not null,
  counterpart_kind text,
  counterpart_id uuid,
  reason text not null,
  actor_user_id uuid not null references app.users(id) on delete restrict,
  audit_event_id uuid references app.audit_events(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  constraint commerce_reporting_exclusions_source_kind_check
    check (source_kind in ('payment', 'payment_record', 'account_adjustment')),
  constraint commerce_reporting_exclusions_counterpart_kind_check
    check (
      counterpart_kind is null
      or counterpart_kind in ('payment', 'payment_record', 'account_adjustment')
    ),
  constraint commerce_reporting_exclusions_counterpart_shape_check
    check (
      (counterpart_kind is null and counterpart_id is null)
      or (counterpart_kind is not null and counterpart_id is not null)
    ),
  constraint commerce_reporting_exclusions_reason_check
    check (nullif(btrim(reason), '') is not null),
  unique (source_kind, source_id),
  unique (counterpart_kind, counterpart_id)
);

create trigger commerce_reporting_exclusions_immutable
before update or delete on app.commerce_reporting_exclusions
for each row execute function app.reject_immutable_commerce_fact();

create index commerce_reporting_exclusions_actor_idx
  on app.commerce_reporting_exclusions (actor_user_id, occurred_at desc, id);

alter table app.payments
  add column if not exists payment_record_id uuid unique
    references app.client_payment_records(id) on delete restrict;

insert into app.capability_definitions (
  capability_key, version, description, domain, risk_level, override_mode
)
values
  ('commerce.client_finance.write', 1,
   'Mutate actor-scoped client finance', 'commerce', 'critical', 'deny_only'),
  ('config.commerce.manage', 1,
   'Publish lesson settlement and teacher compensation catalogs',
   'config', 'critical', 'locked')
on conflict (capability_key, version) do nothing;

with matrix(capability_key, allowed_roles) as (
  values
    ('commerce.client_finance.write',
      array['admin','manager','director','system_admin']::app.user_role[]),
    ('config.commerce.manage',
      array['director','system_admin']::app.user_role[])
)
insert into app.role_package_capabilities (
  package_id, capability_key, capability_version, effect
)
select
  package.id,
  matrix.capability_key,
  1,
  case when package.role = any(matrix.allowed_roles) then 'allow' else 'deny' end
from app.role_packages package
cross join matrix
where package.active
on conflict (package_id, capability_key) do update
set capability_version = excluded.capability_version,
    effect = excluded.effect;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.client_payment_records to magiccrm_app;
    grant update (
      status, method, external_identifier, verification_note,
      actual_payment_id, version, verified_by, verified_at, updated_at
    ) on app.client_payment_records to magiccrm_app;
    revoke delete on app.client_payment_records from magiccrm_app;
    grant select, insert on app.client_payment_status_events to magiccrm_app;
    grant select, insert on app.commerce_reporting_exclusions to magiccrm_app;
    revoke update, delete on app.client_payment_status_events from magiccrm_app;
    revoke update, delete on app.commerce_reporting_exclusions from magiccrm_app;
  end if;
end $$;
