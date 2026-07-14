-- «Объявления» becomes a real group chat: every user is a member, only
-- manager/director may post (enforced in the service), and all group features
-- (reactions, replies, delete) apply. This migrates the legacy announcements
-- channel and its posts into a chat, then hides the channel.

-- 1. Chat identity columns (mirrors channels: slug + is_system).
alter table app.chats add column if not exists slug text;
alter table app.chats add column if not exists is_system boolean not null default false;

create unique index if not exists chats_slug_unique
  on app.chats (slug)
  where slug is not null and deleted_at is null;

-- 2. Create/adopt the announcements group chat.
insert into app.chats (type, title, slug, is_system)
select 'group', 'Объявления', 'announcements', true
where not exists (
  select 1 from app.chats where slug = 'announcements' and deleted_at is null
);

-- 3. Migrate legacy channel posts -> messages. Deterministic id (md5 of the
--    post id) makes the copy idempotent on re-run.
insert into app.messages (
  id, chat_id, sender_id, content, message_type, attachment_file_id,
  created_at, updated_at
)
select
  md5('announcements-post:' || p.id::text)::uuid,
  (select id from app.chats where slug = 'announcements' and deleted_at is null limit 1),
  p.author_id,
  p.content,
  case when p.attachment_file_id is not null then 'file' else 'text' end,
  p.attachment_file_id,
  p.published_at,
  p.updated_at
from app.channel_posts p
join app.channels ac
  on ac.id = p.channel_id and ac.slug = 'announcements' and ac.deleted_at is null
where p.deleted_at is null
on conflict (id) do nothing;

-- 4. Everyone is a member. Managers/directors get chat-admin; posting is still
--    gated by user role in the service. Idempotent.
insert into app.chat_members (chat_id, user_id, role)
select
  (select id from app.chats where slug = 'announcements' and deleted_at is null limit 1),
  u.id,
  case when u.role in ('manager', 'director') then 'admin' else 'member' end
from app.users u
where u.deleted_at is null
on conflict (chat_id, user_id) do nothing;

-- 5. Point the chat at its newest message, then hide the legacy channel.
update app.chats c
set last_message_id = (
      select m.id
      from app.messages m
      where m.chat_id = c.id and m.deleted_at is null
      order by m.created_at desc, m.id desc
      limit 1
    ),
    updated_at = now()
where c.slug = 'announcements' and c.deleted_at is null;

update app.channels
set deleted_at = now(), updated_at = now()
where slug = 'announcements' and deleted_at is null;
