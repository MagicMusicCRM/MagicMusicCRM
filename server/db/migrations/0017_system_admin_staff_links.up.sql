alter type app.user_role add value if not exists 'system_admin';

alter type app.crm_entity_type add value if not exists 'staff';

create table if not exists app.staff_members (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references app.profiles(id) on delete set null,
  role text not null default 'employee',
  position text,
  status text not null default 'working',
  custom_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint staff_members_role_check check (length(btrim(role)) > 0),
  constraint staff_members_status_check check (length(btrim(status)) > 0)
);

create unique index if not exists staff_members_profile_active_idx
  on app.staff_members (profile_id)
  where profile_id is not null and deleted_at is null;

create index if not exists staff_members_role_status_idx
  on app.staff_members (role, status, created_at desc)
  where deleted_at is null;

create table if not exists app.staff_branch_assignments (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references app.staff_members(id) on delete cascade,
  branch_id uuid not null references app.branches(id) on delete cascade,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (staff_member_id, branch_id)
);

create index if not exists staff_branch_assignments_branch_idx
  on app.staff_branch_assignments (branch_id, staff_member_id)
  where deleted_at is null;

alter table app.user_crm_links
  drop constraint if exists user_crm_links_entity_type_check;

alter table app.user_crm_links
  add constraint user_crm_links_entity_type_check
  check (entity_type::text in ('student', 'lead', 'teacher', 'staff'));

alter table app.user_crm_links
  drop constraint if exists user_crm_links_source_check;

alter table app.user_crm_links
  add constraint user_crm_links_source_check
  check (link_source in ('auto_phone', 'manual_phone', 'auto_email', 'manual_email', 'import'));

create index if not exists user_crm_links_user_type_active_idx
  on app.user_crm_links (user_id, entity_type, created_at desc)
  where deleted_at is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on type app.user_role to magiccrm_app;
    grant usage on type app.crm_entity_type to magiccrm_app;
    grant select, insert, update, delete on app.staff_members to magiccrm_app;
    grant select, insert, update, delete on app.staff_branch_assignments to magiccrm_app;
    grant select, insert, update, delete on app.user_crm_links to magiccrm_app;
  end if;
end $$;
