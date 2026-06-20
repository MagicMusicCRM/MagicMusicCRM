-- server/db/migrations/0029_families.up.sql
-- Households: families + polymorphic family_members + normalized contacts.

create table if not exists app.families (
  id uuid primary key default gen_random_uuid(),
  name text,
  branch_id uuid references app.branches(id),
  primary_payer_member_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references app.families(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  role text not null default 'child',
  is_primary_contact boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint family_members_entity_check check (entity_type in ('student', 'lead', 'profile')),
  constraint family_members_role_check check (role in ('parent', 'child', 'partner', 'sibling', 'guardian', 'payer')),
  constraint family_members_unique unique (family_id, entity_type, entity_id)
);
create index if not exists family_members_family_idx
  on app.family_members (family_id) where deleted_at is null;
create index if not exists family_members_entity_idx
  on app.family_members (entity_type, entity_id) where deleted_at is null;

-- Guarded FK for the payer pointer (added after family_members exists; idempotent).
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where c.conname = 'families_payer_member_fk'
      and n.nspname = 'app'
      and t.relname = 'families'
  ) then
    alter table app.families
      add constraint families_payer_member_fk
      foreign key (primary_payer_member_id) references app.family_members(id) on delete set null;
  end if;
end $$;

create table if not exists app.contacts (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  phone_normalized text,
  name text,
  role text,
  created_at timestamptz not null default now(),
  constraint contacts_entity_check check (entity_type in ('student', 'lead', 'profile'))
);
create index if not exists contacts_entity_idx on app.contacts (entity_type, entity_id);
create index if not exists contacts_phone_idx on app.contacts (phone_normalized) where phone_normalized is not null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.families to magiccrm_app;
    grant select, insert, update, delete on app.family_members to magiccrm_app;
    grant select, insert, update, delete on app.contacts to magiccrm_app;
  end if;
end $$;
