-- Reverse the default announcements seed. The channel row itself is intentionally
-- NOT deleted — it may have existed before this migration (adopted by title);
-- dropping the slug/is_system columns un-tags it. Only the role permissions this
-- migration seeded (role-based, user_id is null) are removed.
delete from app.channel_permissions
where user_id is null
  and channel_id in (
    select id from app.channels where slug = 'announcements'
  );

drop index if exists app.channels_slug_unique;
alter table app.channels drop column if exists is_system;
alter table app.channels drop column if exists slug;
