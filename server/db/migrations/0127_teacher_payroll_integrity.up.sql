insert into app.capability_definitions (
  capability_key, version, description, domain, risk_level, override_mode
)
values
  (
    'commerce.teacher_payroll.read', 1,
    'Read teacher rates, payroll movements and teacher statistics',
    'commerce', 'high', 'deny_only'
  ),
  (
    'commerce.teacher_payroll.write', 1,
    'Append teacher rates, payouts, bonuses and deductions',
    'commerce', 'critical', 'deny_only'
  )
on conflict (capability_key, version) do nothing;

insert into app.role_package_capabilities (
  package_id, capability_key, capability_version, effect
)
select package.id, definition.capability_key, 1,
  case
    when package.role in ('admin', 'manager', 'director', 'system_admin')
      then 'allow'
    else 'deny'
  end
from app.role_packages package
cross join (
  values
    ('commerce.teacher_payroll.read'),
    ('commerce.teacher_payroll.write')
) definition(capability_key)
where package.active
on conflict (package_id, capability_key) do nothing;

-- Runtime payroll facts are append-only. The migration owner keeps maintenance
-- rights so test/restore tooling and parent-row cascades remain possible.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    revoke update, delete, truncate on app.teacher_rates from magiccrm_app;
    revoke update, delete, truncate on app.teacher_payouts from magiccrm_app;
    grant select, insert on app.teacher_rates to magiccrm_app;
    grant select, insert on app.teacher_payouts to magiccrm_app;
  end if;
end $$;
