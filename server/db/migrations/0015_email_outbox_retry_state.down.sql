drop index if exists app.email_outbox_retry_idx;

alter table app.email_outbox
  drop column if exists last_error,
  drop column if exists attempt_count;
