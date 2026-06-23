-- server/db/migrations/0041_app_statement_timeout.up.sql
-- Bound runaway queries and leaked idle-in-transaction sessions so a single bad
-- query cannot hold one of the 10 pooled connections indefinitely and exhaust
-- the pool (KVA-222). Conservative values: well above legitimate OLTP/report
-- queries (sub-second here) but finite. Applies to NEW sessions of the role;
-- a deploy/restart picks up fresh connections. A job needing longer can use
-- SET LOCAL statement_timeout within its own transaction.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    alter role magiccrm_app set statement_timeout = '30s';
    alter role magiccrm_app set idle_in_transaction_session_timeout = '60s';
  end if;
end $$;
