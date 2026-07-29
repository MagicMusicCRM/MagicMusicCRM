create table if not exists app.aggregate_versions (
  aggregate_type text not null,
  aggregate_id text not null,
  version bigint not null,
  updated_at timestamptz not null default now(),
  primary key (aggregate_type, aggregate_id),
  constraint aggregate_versions_version_positive check (version > 0)
);

create table if not exists app.idempotency_records (
  id uuid primary key default gen_random_uuid(),
  actor_key text not null,
  operation text not null,
  idempotency_key text not null,
  request_fingerprint text not null,
  status text not null default 'pending',
  result_ref jsonb,
  result_version bigint,
  audit_event_id uuid,
  outbox_event_id uuid,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz,
  constraint idempotency_records_scope_unique
    unique (actor_key, operation, idempotency_key),
  constraint idempotency_records_fingerprint_shape
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint idempotency_records_status_check
    check (status in ('pending', 'completed')),
  constraint idempotency_records_completion_check
    check (
      (status = 'pending' and completed_at is null)
      or (status = 'completed' and completed_at is not null)
    )
);

create index if not exists idempotency_records_expiry_idx
  on app.idempotency_records (expires_at)
  where expires_at is not null;

alter table app.audit_events
  add column if not exists request_id text,
  add column if not exists before_ref jsonb,
  add column if not exists after_ref jsonb,
  add column if not exists reason text;

create index if not exists audit_events_request_id_idx
  on app.audit_events (request_id)
  where request_id is not null;

create table if not exists app.platform_outbox_events (
  event_id uuid primary key default gen_random_uuid(),
  event_type text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  aggregate_version bigint not null,
  request_id text not null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by text,
  published_at timestamptz,
  attempts integer not null default 0,
  last_error text,
  dead_lettered_at timestamptz,
  constraint platform_outbox_version_positive
    check (aggregate_version > 0),
  constraint platform_outbox_attempts_nonnegative
    check (attempts >= 0),
  constraint platform_outbox_claim_pair
    check (
      (claimed_at is null and claimed_by is null)
      or (claimed_at is not null and claimed_by is not null)
    ),
  constraint platform_outbox_terminal_exclusive
    check (not (published_at is not null and dead_lettered_at is not null))
);

create index if not exists platform_outbox_due_idx
  on app.platform_outbox_events (available_at, occurred_at, event_id)
  where published_at is null and dead_lettered_at is null;

create index if not exists platform_outbox_claim_idx
  on app.platform_outbox_events (claimed_at)
  where published_at is null and dead_lettered_at is null;

alter table app.idempotency_records
  add constraint idempotency_records_audit_event_fk
    foreign key (audit_event_id) references app.audit_events(id),
  add constraint idempotency_records_outbox_event_fk
    foreign key (outbox_event_id)
    references app.platform_outbox_events(event_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.aggregate_versions to magiccrm_app;
    grant select, insert, update on app.idempotency_records to magiccrm_app;
    grant select, insert, update on app.platform_outbox_events to magiccrm_app;
  end if;
end $$;
