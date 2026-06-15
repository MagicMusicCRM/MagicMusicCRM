create table if not exists app.import_batches (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  mode text not null,
  status text not null default 'running',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  source_counts jsonb not null default '{}'::jsonb,
  planned_counts jsonb not null default '{}'::jsonb,
  stored_counts jsonb not null default '{}'::jsonb,
  skipped_counts jsonb not null default '{}'::jsonb,
  checksums jsonb not null default '{}'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  report jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint import_batches_mode_check check (mode in ('dry_run', 'apply')),
  constraint import_batches_status_check check (status in ('running', 'completed', 'failed'))
);

create index if not exists import_batches_source_started_idx
  on app.import_batches (source, started_at desc);

create table if not exists app.import_source_records (
  id uuid primary key default gen_random_uuid(),
  import_batch_id uuid references app.import_batches(id) on delete cascade,
  source text not null,
  external_id text not null,
  target_table text,
  target_id uuid,
  source_checksum text not null,
  raw jsonb not null,
  field_loss jsonb not null default '[]'::jsonb,
  imported_at timestamptz not null default now(),
  constraint import_source_records_external_id_check check (length(btrim(external_id)) > 0)
);

create unique index if not exists import_source_records_batch_source_external_idx
  on app.import_source_records (import_batch_id, source, external_id);

create index if not exists import_source_records_target_idx
  on app.import_source_records (target_table, target_id)
  where target_table is not null and target_id is not null;

create table if not exists app.duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  import_batch_id uuid references app.import_batches(id) on delete set null,
  entity_type_a app.crm_entity_type not null,
  entity_id_a uuid not null,
  entity_type_b app.crm_entity_type not null,
  entity_id_b uuid not null,
  match_type text not null,
  match_value text not null,
  confidence numeric(5,4) not null default 1,
  source text not null default 'computed',
  status text not null default 'pending',
  decided_at timestamptz,
  decided_by uuid references app.users(id) on delete set null,
  decision_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint duplicate_candidates_match_type_check check (match_type in ('phone', 'email', 'full_name', 'lead_student_phone', 'lead_student_email')),
  constraint duplicate_candidates_status_check check (status in ('pending', 'not_duplicate', 'attached', 'merged', 'ignored')),
  constraint duplicate_candidates_not_self_check check (
    entity_type_a <> entity_type_b or entity_id_a <> entity_id_b
  )
);

create unique index if not exists duplicate_candidates_active_identity_idx
  on app.duplicate_candidates (
    entity_type_a,
    entity_id_a,
    entity_type_b,
    entity_id_b,
    match_type,
    match_value
  )
  where deleted_at is null;

create index if not exists duplicate_candidates_status_idx
  on app.duplicate_candidates (status, created_at desc)
  where deleted_at is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.import_batches to magiccrm_app;
    grant select, insert, update, delete on app.import_source_records to magiccrm_app;
    grant select, insert, update, delete on app.duplicate_candidates to magiccrm_app;
  end if;
end $$;
