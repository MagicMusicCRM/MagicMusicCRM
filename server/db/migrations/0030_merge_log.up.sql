-- server/db/migrations/0030_merge_log.up.sql
-- Audit + undo log for record merges (dedup). Records exactly which rows moved.

create table if not exists app.merge_log (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  loser_id uuid not null,
  winner_id uuid not null,
  repointed jsonb not null default '{}'::jsonb,
  merged_by uuid references app.users(id),
  merged_at timestamptz not null default now(),
  undone_at timestamptz,
  undone_by uuid references app.users(id),
  constraint merge_log_entity_check check (entity_type in ('lead', 'student'))
);
create index if not exists merge_log_entity_idx on app.merge_log (entity_type, loser_id);
create index if not exists merge_log_open_idx on app.merge_log (merged_at desc) where undone_at is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.merge_log to magiccrm_app;
  end if;
end $$;
