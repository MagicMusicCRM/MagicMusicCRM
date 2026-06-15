create table if not exists app.system_settings (
  key text primary key,
  value jsonb,
  updated_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on schema app to magiccrm_app;
    grant select, insert, update, delete on all tables in schema app to magiccrm_app;
  end if;
end $$;
