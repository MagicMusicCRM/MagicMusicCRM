create table if not exists app.chats (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('administration', 'direct', 'group')),
  title text,
  created_by uuid references app.users(id) on delete set null,
  avatar_file_id uuid,
  last_message_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.chat_members (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references app.chats(id) on delete cascade,
  user_id uuid not null references app.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  muted_until timestamptz,
  last_read_message_id uuid,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  unique (chat_id, user_id)
);

create table if not exists app.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references app.chats(id) on delete cascade,
  sender_id uuid references app.users(id) on delete set null,
  content text,
  message_type text not null default 'text' check (message_type in ('text', 'file', 'voice', 'system')),
  attachment_file_id uuid,
  reply_to_id uuid references app.messages(id) on delete set null,
  forwarded_from_id uuid references app.messages(id) on delete set null,
  pinned_by uuid references app.users(id) on delete set null,
  pinned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  delete_mode text,
  constraint message_payload_check check (
    content is not null
    or attachment_file_id is not null
    or message_type = 'system'
  )
);

alter table app.chat_members
  add constraint chat_members_last_read_message_fk
  foreign key (last_read_message_id) references app.messages(id) on delete set null;

create table if not exists app.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references app.messages(id) on delete cascade,
  user_id uuid not null references app.users(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

create table if not exists app.channels (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  avatar_file_id uuid,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.channel_permissions (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references app.channels(id) on delete cascade,
  user_id uuid references app.users(id) on delete cascade,
  role app.user_role,
  can_read boolean not null default true,
  can_write boolean not null default false,
  created_at timestamptz not null default now(),
  constraint channel_permission_target_check check (user_id is not null or role is not null),
  unique (channel_id, user_id, role)
);

create table if not exists app.channel_posts (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references app.channels(id) on delete cascade,
  author_id uuid references app.users(id) on delete set null,
  content text not null,
  attachment_file_id uuid,
  published_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists chats_created_idx on app.chats (created_at desc) where deleted_at is null;
create index if not exists chat_members_user_chat_idx on app.chat_members (user_id, chat_id) where left_at is null;
create index if not exists chat_members_chat_user_idx on app.chat_members (chat_id, user_id) where left_at is null;
create index if not exists messages_chat_created_idx on app.messages (chat_id, created_at desc) where deleted_at is null;
create index if not exists messages_sender_created_idx on app.messages (sender_id, created_at desc) where deleted_at is null;
create index if not exists channel_posts_channel_published_idx on app.channel_posts (channel_id, published_at desc) where deleted_at is null;
create index if not exists channel_permissions_user_idx on app.channel_permissions (user_id, channel_id) where user_id is not null;
create index if not exists channel_permissions_role_idx on app.channel_permissions (role, channel_id) where role is not null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on schema app to magiccrm_app;
    grant usage on type app.user_role to magiccrm_app;
    grant select, insert, update, delete on all tables in schema app to magiccrm_app;
    grant usage on all sequences in schema app to magiccrm_app;
    alter default privileges in schema app
      grant select, insert, update, delete on tables to magiccrm_app;
    alter default privileges in schema app
      grant usage on sequences to magiccrm_app;
  end if;
end $$;
