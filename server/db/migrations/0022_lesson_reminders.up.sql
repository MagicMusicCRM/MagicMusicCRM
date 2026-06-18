-- Idempotency marker for lesson reminders. One row per (lesson, kind) means a
-- given reminder was already enqueued and must never be sent again.
create table if not exists app.lesson_reminders (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete cascade,
  kind text not null check (kind in ('day', 'hour')),
  created_at timestamptz not null default now(),
  unique (lesson_id, kind)
);

create index if not exists lesson_reminders_lesson_idx
  on app.lesson_reminders (lesson_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.lesson_reminders to magiccrm_app;
  end if;
end $$;
