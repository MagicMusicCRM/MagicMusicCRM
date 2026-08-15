-- Versioned corrections for assigned and paid client payment records.

create table app.payment_record_corrections (
  id uuid primary key default gen_random_uuid(),
  source_payment_record_id uuid not null unique
    references app.client_payment_records(id) on delete restrict,
  replacement_payment_record_id uuid not null unique
    references app.client_payment_records(id) on delete restrict,
  reversal_adjustment_id uuid unique
    references app.account_adjustments(id) on delete restrict,
  reason text not null,
  actor_user_id uuid not null references app.users(id) on delete restrict,
  audit_event_id uuid references app.audit_events(id)
    on delete restrict deferrable initially deferred,
  occurred_at timestamptz not null default now(),
  constraint payment_record_corrections_distinct_records
    check (source_payment_record_id <> replacement_payment_record_id),
  constraint payment_record_corrections_reason_check
    check (nullif(btrim(reason), '') is not null)
);

create trigger payment_record_corrections_immutable
before update or delete on app.payment_record_corrections
for each row execute function app.reject_immutable_commerce_fact();

create index payment_record_corrections_actor_idx
  on app.payment_record_corrections (actor_user_id, occurred_at desc, id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.payment_record_corrections to magiccrm_app;
    revoke update, delete on app.payment_record_corrections from magiccrm_app;
  end if;
end $$;
