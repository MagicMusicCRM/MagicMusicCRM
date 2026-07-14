-- Revert: restore the announcements channel and drop the group chat (cascades
-- its migrated messages, members and reactions).

update app.channels
set deleted_at = null, updated_at = now()
where slug = 'announcements' and deleted_at is not null;

delete from app.chats where slug = 'announcements';

drop index if exists app.chats_slug_unique;
alter table app.chats drop column if exists is_system;
alter table app.chats drop column if exists slug;
