do $$
begin
  if exists (
    select 1
    from app.user_capability_overrides
    where capability_key in (
      'commerce.teacher_payroll.read',
      'commerce.teacher_payroll.write'
    )
  ) then
    raise exception 'Cannot remove teacher payroll capabilities while overrides reference them';
  end if;
end $$;

delete from app.role_package_capabilities
where capability_key in (
  'commerce.teacher_payroll.read',
  'commerce.teacher_payroll.write'
);

delete from app.capability_definitions
where capability_key in (
  'commerce.teacher_payroll.read',
  'commerce.teacher_payroll.write'
);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant update, delete, truncate on app.teacher_rates to magiccrm_app;
    grant update, delete, truncate on app.teacher_payouts to magiccrm_app;
  end if;
end $$;
