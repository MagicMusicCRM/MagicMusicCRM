-- server/db/migrations/0061_task_history.up.sql
-- Per-field change log for tasks, in the shape the AmoCRM-style feed needs:
-- one row per changed field, so «перенёс срок» and «сменил исполнителя» are
-- separate events even when they happened in the same PATCH.
--
-- Why a dedicated table and not app.audit_events + metadata: the feed is read
-- per task and filtered per field (the director's reschedule control screen is
-- literally `where field = 'due_at'`). On audit_events that is a jsonb probe
-- over every action in the system; here it is an index hit. Precedent:
-- app.lead_status_history exists for the same reason.

create table if not exists app.task_history (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references app.tasks(id) on delete cascade,
  -- 'created' | 'status' | 'due_at' | 'assigned_to' | 'title' | 'description' | 'entity'
  field text not null,
  -- Rendered as text on purpose: the feed shows values, it never re-resolves
  -- them, and a uuid/timestamptz/text union would need three nullable columns.
  -- The *_user_id columns below carry the ids the UI must link to.
  old_value text,
  new_value text,
  -- Denormalised link targets for assignment events, so the feed can render a
  -- profile chip without parsing old_value/new_value back into uuids.
  old_user_id uuid references app.users(id) on delete set null,
  new_user_id uuid references app.users(id) on delete set null,
  changed_by uuid references app.users(id) on delete set null,
  -- NOT `default now()` at the call site: the HolliHop import backfills history
  -- with the ORIGINAL dates/times (spec §2.2 «по датам и времени выполнения»),
  -- so callers pass changed_at explicitly. The default only covers live edits.
  changed_at timestamptz not null default now(),
  -- Provenance: distinguishes what this app recorded from what was backfilled,
  -- so a re-import can delete and rewrite its own rows without touching live ones.
  source text not null default 'app',
  constraint task_history_source_check check (source in ('app', 'hollihop'))
);

-- The task feed: «show me everything that happened to this task, newest first».
create index if not exists task_history_task_idx
  on app.task_history (task_id, changed_at desc);

-- The supervisor control feed (spec: «директор и управляющий видят, кто какие
-- задачи когда переносит»): filtered by field, ordered by time.
create index if not exists task_history_field_idx
  on app.task_history (field, changed_at desc);

-- Idempotent re-import: lets the importer replace its own backfilled rows.
create index if not exists task_history_source_idx
  on app.task_history (source, task_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.task_history to magiccrm_app;
  end if;
end $$;
