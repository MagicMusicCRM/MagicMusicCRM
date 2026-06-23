-- server/db/migrations/0040_audit_events_append_only.up.sql
-- app.audit_events is an append-only audit log. The runtime application role
-- (magiccrm_app) was granted UPDATE/DELETE by the blanket grant in 0001, which
-- means a SQL-injection / RCE / bug could tamper with or erase the audit trail
-- (KVA-219). Keep INSERT/SELECT, drop UPDATE/DELETE.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    revoke update, delete on app.audit_events from magiccrm_app;
  end if;
end $$;
