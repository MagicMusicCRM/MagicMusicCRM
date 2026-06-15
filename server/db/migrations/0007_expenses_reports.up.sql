create table if not exists app.expenses (
  id uuid primary key default gen_random_uuid(),
  amount numeric(12,2) not null,
  category text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists expenses_created_idx
  on app.expenses (created_at desc)
  where deleted_at is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.expenses to magiccrm_app;
  end if;
end $$;
