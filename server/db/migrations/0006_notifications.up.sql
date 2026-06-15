do $$
begin
  if not exists (select 1 from pg_type where typname = 'notification_channel') then
    create type app.notification_channel as enum ('in_app', 'email', 'push');
  end if;

  if not exists (select 1 from pg_type where typname = 'notification_delivery_status') then
    create type app.notification_delivery_status as enum ('queued', 'sent', 'failed', 'skipped');
  end if;
end $$;

create table if not exists app.notifications (
  id uuid primary key default gen_random_uuid(),
  type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists app.notification_recipients (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references app.notifications(id) on delete cascade,
  user_id uuid not null references app.users(id) on delete cascade,
  is_read boolean not null default false,
  read_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  unique (notification_id, user_id)
);

create index if not exists notification_recipients_user_read_created_idx
  on app.notification_recipients (user_id, is_read, created_at desc);

create table if not exists app.notification_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  platform text not null,
  token_hash text not null,
  encrypted_token text,
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token_hash)
);

create index if not exists notification_devices_user_enabled_idx
  on app.notification_devices (user_id)
  where enabled = true;

create table if not exists app.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references app.notifications(id) on delete cascade,
  user_id uuid not null references app.users(id) on delete cascade,
  channel app.notification_channel not null,
  provider text not null,
  status app.notification_delivery_status not null default 'queued',
  attempt_count integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notification_deliveries_notification_user_idx
  on app.notification_deliveries (notification_id, user_id, channel);

create table if not exists app.email_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references app.users(id) on delete cascade,
  to_email_hash text not null,
  template text not null,
  payload jsonb not null default '{}'::jsonb,
  status app.notification_delivery_status not null default 'queued',
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists email_outbox_status_next_attempt_idx
  on app.email_outbox (status, next_attempt_at);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on schema app to magiccrm_app;
    grant usage on type app.notification_channel to magiccrm_app;
    grant usage on type app.notification_delivery_status to magiccrm_app;
    grant select, insert, update, delete on all tables in schema app to magiccrm_app;
    grant usage on all sequences in schema app to magiccrm_app;
    alter default privileges in schema app
      grant select, insert, update, delete on tables to magiccrm_app;
    alter default privileges in schema app
      grant usage on sequences to magiccrm_app;
  end if;
end $$;
