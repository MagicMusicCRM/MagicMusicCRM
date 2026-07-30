create table if not exists app.report_export_jobs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references app.users(id) on delete cascade,
  report_key text not null,
  format text not null,
  filter_spec jsonb not null default '{}'::jsonb,
  row_count integer not null,
  status text not null default 'queued',
  filename text,
  mime_type text,
  content bytea,
  error_code text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint report_export_jobs_report_key_check
    check (report_key in ('client_status', 'school_finance')),
  constraint report_export_jobs_format_check
    check (format in ('xlsx', 'csv')),
  constraint report_export_jobs_row_count_check
    check (row_count between 0 and 100000),
  constraint report_export_jobs_status_check
    check (status in ('queued', 'processing', 'ready', 'failed', 'expired')),
  constraint report_export_jobs_ready_shape
    check (
      status <> 'ready'
      or (
        filename is not null
        and mime_type is not null
        and content is not null
        and completed_at is not null
      )
    )
);

create index if not exists report_export_jobs_actor_created_idx
  on app.report_export_jobs (actor_user_id, created_at desc, id);

create index if not exists report_export_jobs_queue_idx
  on app.report_export_jobs (status, created_at, id)
  where status in ('queued', 'processing');

create index if not exists report_export_jobs_expiry_idx
  on app.report_export_jobs (expires_at, id)
  where status = 'ready';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.report_export_jobs to magiccrm_app;
  end if;
end $$;
