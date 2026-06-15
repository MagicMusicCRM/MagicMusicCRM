do $$
begin
  if not exists (select 1 from pg_type where typname = 'legal_document_type') then
    create type app.legal_document_type as enum (
      'privacy_policy',
      'terms_of_use',
      'account_deletion'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'account_deletion_status') then
    create type app.account_deletion_status as enum (
      'pending',
      'processing',
      'completed',
      'rejected',
      'cancelled'
    );
  end if;
end $$;

create table if not exists app.legal_documents (
  id uuid primary key default gen_random_uuid(),
  document_type app.legal_document_type not null,
  version text not null,
  title text not null,
  url text,
  file_id uuid references app.file_objects(id) on delete set null,
  published_at timestamptz not null default now(),
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint legal_documents_external_url_check check (
    url is null
    or url ~ '^https://magicmusiccrm-legal\.vercel\.app/(privacy|terms|account-deletion)/?$'
    or url ~ '^https://magic-music\.org/'
  )
);

create unique index if not exists legal_documents_current_type_unique
  on app.legal_documents (document_type)
  where is_current = true;

create unique index if not exists legal_documents_type_version_unique
  on app.legal_documents (document_type, version);

create table if not exists app.legal_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  document_id uuid not null references app.legal_documents(id) on delete restrict,
  version text not null,
  accepted_at timestamptz not null default now(),
  ip_hash text,
  user_agent_hash text,
  unique (user_id, document_id)
);

create index if not exists legal_consents_user_accepted_idx
  on app.legal_consents (user_id, accepted_at desc);

create table if not exists app.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  status app.account_deletion_status not null default 'pending',
  reason text,
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references app.users(id) on delete set null,
  resolution_note text,
  updated_at timestamptz not null default now()
);

create unique index if not exists account_deletion_requests_active_user_unique
  on app.account_deletion_requests (user_id)
  where status in ('pending', 'processing');

create index if not exists account_deletion_requests_status_requested_idx
  on app.account_deletion_requests (status, requested_at desc);

insert into app.legal_documents (document_type, version, title, url, is_current)
values
  (
    'privacy_policy',
    '2026-06-11',
    'Политика конфиденциальности',
    'https://magicmusiccrm-legal.vercel.app/privacy/',
    true
  ),
  (
    'terms_of_use',
    '2026-06-11',
    'Пользовательское соглашение',
    'https://magicmusiccrm-legal.vercel.app/terms/',
    true
  ),
  (
    'account_deletion',
    '2026-06-11',
    'Удаление аккаунта',
    'https://magicmusiccrm-legal.vercel.app/account-deletion/',
    true
  )
on conflict (document_type, version) do update
set
  title = excluded.title,
  url = excluded.url,
  is_current = excluded.is_current,
  updated_at = now();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on schema app to magiccrm_app;
    grant usage on type app.legal_document_type to magiccrm_app;
    grant usage on type app.account_deletion_status to magiccrm_app;
    grant select, insert, update, delete on all tables in schema app to magiccrm_app;
    grant usage on all sequences in schema app to magiccrm_app;
    alter default privileges in schema app
      grant select, insert, update, delete on tables to magiccrm_app;
    alter default privileges in schema app
      grant usage on sequences to magiccrm_app;
  end if;
end $$;
