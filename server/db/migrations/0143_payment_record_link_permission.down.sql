do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    revoke update (payment_record_id) on app.payments from magiccrm_app;
  end if;
end $$;
