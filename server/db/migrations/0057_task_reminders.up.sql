-- Idempotency marker for task due-date reminders (mirrors 0022 lesson
-- reminders). One row per (task, kind) means a given reminder was already
-- enqueued and must never be sent again.
create table if not exists app.task_reminders (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references app.tasks(id) on delete cascade,
  kind text not null check (kind in ('day', 'hour')),
  sent_at timestamptz not null default now(),
  unique (task_id, kind)
);

create index if not exists task_reminders_task_idx
  on app.task_reminders (task_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.task_reminders to magiccrm_app;
  end if;
end $$;
