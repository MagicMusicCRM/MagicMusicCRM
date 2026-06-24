-- chats: administration owner + assignment
alter table app.chats add column if not exists owner_user_id uuid references app.users(id) on delete set null;
alter table app.chats add column if not exists assigned_to_user_id uuid references app.users(id) on delete set null;
alter table app.chats add column if not exists assigned_at timestamptz;

create index if not exists chats_owner_user_idx on app.chats (owner_user_id) where deleted_at is null;

-- per-staff inbox state (personal archive)
create table if not exists app.chat_inbox_state (
  chat_id uuid not null references app.chats(id) on delete cascade,
  staff_user_id uuid not null references app.users(id) on delete cascade,
  archived_at timestamptz,
  primary key (chat_id, staff_user_id)
);

-- backfill existing administration chats' owner (single non-staff member); after the
-- Phase 2 wipe there are none, but keep idempotent.
update app.chats c
set owner_user_id = (
  select cm.user_id from app.chat_members cm
  where cm.chat_id = c.id and cm.left_at is null
  order by cm.joined_at asc limit 1
)
where c.type = 'administration' and c.owner_user_id is null and c.deleted_at is null;
