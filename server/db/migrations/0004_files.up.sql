do $$
begin
  if not exists (select 1 from pg_type where typname = 'file_purpose') then
    create type app.file_purpose as enum (
      'profile_avatar',
      'chat_attachment',
      'chat_voice',
      'legal_document',
      'crm_document'
    );
  end if;
end $$;

create table if not exists app.file_objects (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references app.users(id) on delete set null,
  owner_type text,
  owner_id uuid,
  purpose app.file_purpose not null,
  original_name text not null,
  mime_type text not null,
  size_bytes bigint not null,
  storage_key text not null unique,
  sha256 text not null,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.file_download_tokens (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  file_id uuid not null references app.file_objects(id) on delete cascade,
  actor_user_id uuid references app.users(id) on delete set null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists file_objects_owner_idx on app.file_objects (owner_user_id, created_at desc) where deleted_at is null;
create index if not exists file_objects_entity_idx on app.file_objects (owner_type, owner_id, created_at desc) where deleted_at is null;
create index if not exists file_download_tokens_file_idx on app.file_download_tokens (file_id, expires_at desc);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on schema app to magiccrm_app;
    grant usage on type app.file_purpose to magiccrm_app;
    grant select, insert, update, delete on all tables in schema app to magiccrm_app;
    grant usage on all sequences in schema app to magiccrm_app;
    alter default privileges in schema app
      grant select, insert, update, delete on tables to magiccrm_app;
    alter default privileges in schema app
      grant usage on sequences to magiccrm_app;
  end if;
end $$;
