-- server/db/migrations/0041_app_statement_timeout.down.sql
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    alter role magiccrm_app reset statement_timeout;
    alter role magiccrm_app reset idle_in_transaction_session_timeout;
  end if;
end $$;
