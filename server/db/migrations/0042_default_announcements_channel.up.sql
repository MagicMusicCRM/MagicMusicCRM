-- Durable data contract for the default system channel "Объявления".
-- Adds a stable identity (slug + is_system) so the channel cannot be duplicated
-- by repeated seeds. Adopts a pre-existing "Объявления" channel if one exists,
-- then ensures role-based permissions: read for every role, write for
-- admin/manager/system_admin only.

alter table app.channels add column if not exists slug text;
alter table app.channels add column if not exists is_system boolean not null default false;

-- One system channel per slug (ignores soft-deleted rows).
create unique index if not exists channels_slug_unique
  on app.channels (slug)
  where slug is not null and deleted_at is null;

-- Adopt a pre-existing "Объявления" channel (created before this contract) so we
-- never create a duplicate: tag the earliest untagged one with the system slug.
update app.channels
set slug = 'announcements', is_system = true, updated_at = now()
where id = (
  select id from app.channels
  where title = 'Объявления' and slug is null and deleted_at is null
  order by created_at asc
  limit 1
)
and not exists (
  select 1 from app.channels where slug = 'announcements' and deleted_at is null
);

-- Seed a fresh channel only if none exists yet (neither adopted nor seeded).
insert into app.channels (title, description, slug, is_system)
select 'Объявления', 'Школьные объявления', 'announcements', true
where not exists (
  select 1 from app.channels where slug = 'announcements' and deleted_at is null
);

-- Role-based permissions. user_id is NULL for role rows, and NULLs are not
-- deduplicated by the (channel_id, user_id, role) unique constraint, so each row
-- is guarded with NOT EXISTS to stay idempotent.
with ch as (
  select id from app.channels
  where slug = 'announcements' and deleted_at is null
  limit 1
)
insert into app.channel_permissions (channel_id, role, can_read, can_write)
select ch.id, perms.role::app.user_role, perms.can_read, perms.can_write
from ch
cross join (values
  ('client',       true,  false),
  ('teacher',      true,  false),
  ('admin',        true,  true),
  ('manager',      true,  true),
  ('system_admin', true,  true)
) as perms(role, can_read, can_write)
where not exists (
  select 1 from app.channel_permissions cp
  where cp.channel_id = ch.id
    and cp.user_id is null
    and cp.role = perms.role::app.user_role
);
