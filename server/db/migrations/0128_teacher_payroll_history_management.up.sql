-- Owner rule 2026-08-12: Director/system_admin may correct or remove payroll
-- history from operational projections. Physical history remains retained and
-- DELETE/TRUNCATE stay revoked; the versioned API performs audited UPDATE/void.
alter table app.teacher_rates
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists updated_by uuid references app.users(id) on delete set null,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references app.users(id) on delete set null;

alter table app.teacher_payouts
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists updated_by uuid references app.users(id) on delete set null,
  add column if not exists deleted_by uuid references app.users(id) on delete set null;

drop index if exists app.teacher_rates_teacher_idx;
create index teacher_rates_teacher_idx
  on app.teacher_rates (teacher_id, effective_from desc, created_at desc)
  where deleted_at is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    revoke delete, truncate on app.teacher_rates from magiccrm_app;
    revoke delete, truncate on app.teacher_payouts from magiccrm_app;
    grant select, insert, update on app.teacher_rates to magiccrm_app;
    grant select, insert, update on app.teacher_payouts to magiccrm_app;
  end if;
end $$;
