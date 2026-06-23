-- server/db/migrations/0040_audit_events_append_only.down.sql
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant update, delete on app.audit_events to magiccrm_app;
  end if;
end $$;
