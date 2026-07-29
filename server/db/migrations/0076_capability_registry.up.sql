create table if not exists app.capability_definitions (
  capability_key text not null,
  version integer not null,
  description text not null,
  domain text not null,
  risk_level text not null,
  override_mode text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (capability_key, version),
  constraint capability_key_shape check (
    capability_key ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$'
  ),
  constraint capability_version_positive check (version > 0),
  constraint capability_risk_level_check
    check (risk_level in ('low', 'medium', 'high', 'critical')),
  constraint capability_override_mode_check
    check (override_mode in ('allow_deny', 'deny_only', 'locked'))
);

create unique index if not exists capability_definitions_one_active_idx
  on app.capability_definitions (capability_key)
  where active;

create table if not exists app.role_packages (
  id uuid primary key default gen_random_uuid(),
  role app.user_role not null,
  package_version integer not null,
  active boolean not null default true,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (role, package_version),
  constraint role_package_version_positive check (package_version > 0)
);

create unique index if not exists role_packages_one_active_role_idx
  on app.role_packages (role)
  where active;

create table if not exists app.role_package_capabilities (
  package_id uuid not null references app.role_packages(id) on delete cascade,
  capability_key text not null,
  capability_version integer not null,
  effect text not null,
  created_at timestamptz not null default now(),
  primary key (package_id, capability_key),
  foreign key (capability_key, capability_version)
    references app.capability_definitions(capability_key, version),
  constraint role_package_capability_effect_check
    check (effect in ('allow', 'deny'))
);

create table if not exists app.user_capability_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  capability_key text not null,
  capability_version integer not null,
  effect text not null,
  reason_code text not null,
  actor_user_id uuid not null references app.users(id),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  foreign key (capability_key, capability_version)
    references app.capability_definitions(capability_key, version),
  constraint user_capability_override_effect_check
    check (effect in ('allow', 'deny')),
  constraint user_capability_override_reason_code_check
    check (reason_code ~ '^[A-Za-z0-9._:-]{1,120}$'),
  constraint user_capability_override_lifecycle_check
    check (
      (active and revoked_at is null)
      or (not active and revoked_at is not null)
    )
);

create unique index if not exists user_capability_overrides_one_active_idx
  on app.user_capability_overrides (user_id, capability_key)
  where active;

create table if not exists app.user_access_versions (
  user_id uuid primary key references app.users(id) on delete cascade,
  version bigint not null default 1,
  changed_at timestamptz not null default now(),
  constraint user_access_version_positive check (version > 0)
);

insert into app.capability_definitions (
  capability_key,
  version,
  description,
  domain,
  risk_level,
  override_mode
)
values
  ('access.user.role.assign', 1, 'Assign an application role', 'access', 'critical', 'locked'),
  ('access.user.override.manage', 1, 'Manage personal capability overrides', 'access', 'critical', 'locked'),
  ('crm.client.read.basic', 1, 'Read actor-scoped basic client data', 'crm', 'medium', 'allow_deny'),
  ('crm.client.read.contacts', 1, 'Read actor-scoped client contacts', 'crm', 'high', 'deny_only'),
  ('crm.client.write', 1, 'Mutate actor-scoped CRM client data', 'crm', 'high', 'deny_only'),
  ('crm.comment.read.shared', 1, 'Read comments explicitly shared with actor', 'crm', 'medium', 'allow_deny'),
  ('schedule.lesson.read.assigned', 1, 'Read actor-scoped assigned lessons', 'schedule', 'medium', 'allow_deny'),
  ('schedule.lesson.write', 1, 'Create or mutate lessons', 'schedule', 'high', 'deny_only'),
  ('schedule.attendance.write', 1, 'Mutate attendance facts', 'schedule', 'critical', 'locked'),
  ('schedule.lesson.complete', 1, 'Complete lesson lifecycle', 'schedule', 'critical', 'locked'),
  ('commerce.client_finance.read', 1, 'Read actor-scoped client finance', 'commerce', 'high', 'deny_only'),
  ('commerce.school_finance.read', 1, 'Read school-wide finance', 'commerce', 'critical', 'locked'),
  ('commerce.package.read', 1, 'Read subscription package catalog', 'commerce', 'medium', 'allow_deny'),
  ('commerce.package.manage', 1, 'Manage subscription package catalog', 'commerce', 'critical', 'locked'),
  ('commerce.subscription.issue', 1, 'Issue or replace client subscription', 'commerce', 'critical', 'deny_only'),
  ('workflow.task.read', 1, 'Read actor-scoped shared tasks', 'workflow', 'medium', 'allow_deny'),
  ('workflow.task.write', 1, 'Create or mutate shared tasks', 'workflow', 'high', 'deny_only'),
  ('report.status.read', 1, 'Read management status reports', 'report', 'high', 'allow_deny'),
  ('report.export.xlsx', 1, 'Export an allowed report to XLSX', 'report', 'high', 'allow_deny'),
  ('system.settings.manage', 1, 'Manage operational system settings', 'system', 'critical', 'locked')
on conflict (capability_key, version) do nothing;

insert into app.role_packages (id, role, package_version, active)
values
  ('21000000-0000-0000-0000-000000000001', 'client', 1, true),
  ('21000000-0000-0000-0000-000000000002', 'teacher', 1, true),
  ('21000000-0000-0000-0000-000000000003', 'admin', 1, true),
  ('21000000-0000-0000-0000-000000000004', 'manager', 1, true),
  ('21000000-0000-0000-0000-000000000005', 'director', 1, true),
  ('21000000-0000-0000-0000-000000000006', 'system_admin', 1, true)
on conflict (role, package_version) do nothing;

with approved as (
  select *
  from (
    values
      ('access.user.role.assign', array['director','system_admin']::app.user_role[]),
      ('access.user.override.manage', array['director','system_admin']::app.user_role[]),
      ('crm.client.read.basic', array['client','teacher','admin','manager','director','system_admin']::app.user_role[]),
      ('crm.client.read.contacts', array['client','admin','manager','director','system_admin']::app.user_role[]),
      ('crm.client.write', array['admin','manager','director','system_admin']::app.user_role[]),
      ('crm.comment.read.shared', array['teacher','admin','manager','director','system_admin']::app.user_role[]),
      ('schedule.lesson.read.assigned', array['client','teacher','admin','manager','director','system_admin']::app.user_role[]),
      ('schedule.lesson.write', array['admin','manager','director','system_admin']::app.user_role[]),
      ('schedule.attendance.write', array['admin','manager','director','system_admin']::app.user_role[]),
      ('schedule.lesson.complete', array['admin','manager','director','system_admin']::app.user_role[]),
      ('commerce.client_finance.read', array['client','admin','manager','director','system_admin']::app.user_role[]),
      ('commerce.school_finance.read', array['director','system_admin']::app.user_role[]),
      ('commerce.package.read', array['admin','manager','director','system_admin']::app.user_role[]),
      ('commerce.package.manage', array['director','system_admin']::app.user_role[]),
      ('commerce.subscription.issue', array['admin','manager','director','system_admin']::app.user_role[]),
      ('workflow.task.read', array['teacher','admin','manager','director','system_admin']::app.user_role[]),
      ('workflow.task.write', array['admin','manager','director','system_admin']::app.user_role[]),
      ('report.status.read', array['manager','director','system_admin']::app.user_role[]),
      ('report.export.xlsx', array['manager','director','system_admin']::app.user_role[]),
      ('system.settings.manage', array['manager','director','system_admin']::app.user_role[])
  ) matrix(capability_key, allowed_roles)
)
insert into app.role_package_capabilities (
  package_id,
  capability_key,
  capability_version,
  effect
)
select
  package.id,
  approved.capability_key,
  1,
  case
    when package.role = any(approved.allowed_roles) then 'allow'
    else 'deny'
  end
from app.role_packages package
cross join approved
where package.package_version = 1
on conflict (package_id, capability_key) do nothing;

insert into app.user_access_versions (user_id, version)
select id, 1
from app.users
on conflict (user_id) do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.capability_definitions to magiccrm_app;
    grant select on app.role_packages to magiccrm_app;
    grant select on app.role_package_capabilities to magiccrm_app;
    grant select, insert, update on app.user_capability_overrides to magiccrm_app;
    grant select, insert, update on app.user_access_versions to magiccrm_app;
  end if;
end $$;
