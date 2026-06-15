alter table app.users
  add column if not exists is_app_account boolean not null default true;

alter table app.users
  add column if not exists phone_verified_at timestamptz;

create index if not exists users_app_accounts_role_created_idx
  on app.users (role, created_at desc)
  where deleted_at is null and is_app_account = true;

create table if not exists app.user_crm_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  entity_type app.crm_entity_type not null,
  entity_id uuid not null,
  matched_phone text,
  link_source text not null default 'manual_phone',
  confirmed_at timestamptz,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint user_crm_links_entity_type_check check (entity_type in ('student', 'lead')),
  constraint user_crm_links_source_check check (link_source in ('auto_phone', 'manual_phone'))
);

create unique index if not exists user_crm_links_user_entity_active_idx
  on app.user_crm_links (user_id, entity_type, entity_id)
  where deleted_at is null;

create unique index if not exists user_crm_links_entity_active_idx
  on app.user_crm_links (entity_type, entity_id)
  where deleted_at is null;

update app.users u
set is_app_account = false,
    updated_at = now()
from app.profiles p
where p.user_id = u.id
  and u.deleted_at is null
  and p.deleted_at is null
  and u.password_hash is null
  and u.email_verified_at is null
  and not exists (
    select 1 from app.refresh_sessions rs where rs.user_id = u.id
  )
  and not exists (
    select 1 from app.user_identities ui where ui.user_id = u.id
  )
  and (
    lower(u.email) like '%@migration.invalid'
    or lower(u.email) like '%@local.magicmusiccrm.invalid'
    or p.custom_data ? 'hollihopId'
    or p.custom_data ? 'hollihopClientId'
  );

update app.users u
set phone_verified_at = coalesce(u.phone_verified_at, now()),
    updated_at = now()
from app.profiles p
where p.user_id = u.id
  and u.deleted_at is null
  and p.deleted_at is null
  and u.is_app_account = true
  and coalesce(nullif(btrim(p.phone), ''), nullif(btrim(u.phone), '')) is not null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.user_crm_links to magiccrm_app;
  end if;
end $$;
