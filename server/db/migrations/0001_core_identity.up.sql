create extension if not exists pgcrypto;

create schema if not exists app;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type app.user_role as enum ('client', 'teacher', 'manager', 'admin');
  end if;
end $$;

create table if not exists app.users (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  password_hash text,
  full_name text,
  phone text,
  role app.user_role not null default 'client',
  email_verified_at timestamptz,
  profile_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists users_email_lower_unique
  on app.users (lower(email))
  where deleted_at is null;

create table if not exists app.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references app.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_events_actor_created_idx
  on app.audit_events (actor_user_id, created_at desc);

create table if not exists app.email_verification_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists email_verification_tokens_user_idx
  on app.email_verification_tokens (user_id, created_at desc);

create table if not exists app.otp_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references app.users(id) on delete cascade,
  email_hash text not null,
  purpose text not null,
  code_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists otp_challenges_email_purpose_created_idx
  on app.otp_challenges (email_hash, purpose, created_at desc);

create table if not exists app.password_reset_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists password_reset_tokens_user_created_idx
  on app.password_reset_tokens (user_id, created_at desc);

create table if not exists app.oauth_states (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  state_hash text not null unique,
  redirect_uri text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists oauth_states_provider_created_idx
  on app.oauth_states (provider, created_at desc);

create table if not exists app.user_identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  provider text not null,
  provider_user_id text not null,
  email text,
  email_verified boolean not null default false,
  raw_profile jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (provider, provider_user_id)
);

create index if not exists user_identities_user_idx
  on app.user_identities (user_id);

create table if not exists app.refresh_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  token_hash text not null unique,
  family_id uuid not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  replaced_by_id uuid references app.refresh_sessions(id),
  last_used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists refresh_sessions_user_idx
  on app.refresh_sessions (user_id, created_at desc);

create index if not exists refresh_sessions_family_idx
  on app.refresh_sessions (family_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on schema app to magiccrm_app;
    grant usage on type app.user_role to magiccrm_app;
    grant select, insert, update, delete on all tables in schema app to magiccrm_app;
    alter default privileges in schema app
      grant select, insert, update, delete on tables to magiccrm_app;
  end if;
end $$;
