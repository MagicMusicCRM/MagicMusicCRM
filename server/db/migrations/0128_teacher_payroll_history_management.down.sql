do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    revoke update, delete, truncate on app.teacher_rates from magiccrm_app;
    revoke update, delete, truncate on app.teacher_payouts from magiccrm_app;
    grant select, insert on app.teacher_rates to magiccrm_app;
    grant select, insert on app.teacher_payouts to magiccrm_app;
  end if;
end $$;

drop index if exists app.teacher_rates_teacher_idx;
create index teacher_rates_teacher_idx
  on app.teacher_rates (teacher_id, effective_from desc, created_at desc);

alter table app.teacher_rates
  drop column if exists deleted_by,
  drop column if exists deleted_at,
  drop column if exists updated_by,
  drop column if exists updated_at;

alter table app.teacher_payouts
  drop column if exists deleted_by,
  drop column if exists updated_by,
  drop column if exists updated_at;
