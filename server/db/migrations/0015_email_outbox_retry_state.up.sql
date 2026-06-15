alter table app.email_outbox
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_error text;

create index if not exists email_outbox_retry_idx
  on app.email_outbox (status, next_attempt_at, attempt_count);
