-- A channel permission targets exactly one subject. Publishing always implies
-- reading, and nullable columns must not allow duplicate user/role rules.

update app.channel_permissions
set role = null
where user_id is not null and role is not null;

update app.channel_permissions
set can_read = true
where can_write = true and can_read = false;

with merged as (
  select channel_id, user_id, min(id::text)::uuid as keep_id,
    bool_or(can_read) as can_read, bool_or(can_write) as can_write
  from app.channel_permissions
  where user_id is not null
  group by channel_id, user_id
), updated as (
  update app.channel_permissions cp
  set can_read = merged.can_read or merged.can_write,
      can_write = merged.can_write
  from merged
  where cp.id = merged.keep_id
)
delete from app.channel_permissions cp
using merged
where cp.channel_id = merged.channel_id
  and cp.user_id = merged.user_id
  and cp.id <> merged.keep_id;

with merged as (
  select channel_id, role, min(id::text)::uuid as keep_id,
    bool_or(can_read) as can_read, bool_or(can_write) as can_write
  from app.channel_permissions
  where role is not null
  group by channel_id, role
), updated as (
  update app.channel_permissions cp
  set can_read = merged.can_read or merged.can_write,
      can_write = merged.can_write
  from merged
  where cp.id = merged.keep_id
)
delete from app.channel_permissions cp
using merged
where cp.channel_id = merged.channel_id
  and cp.role = merged.role
  and cp.id <> merged.keep_id;

alter table app.channel_permissions
  drop constraint if exists channel_permission_target_check;

alter table app.channel_permissions
  add constraint channel_permission_exact_target_check
    check ((user_id is not null) <> (role is not null)),
  add constraint channel_permission_write_requires_read_check
    check (not can_write or can_read);

create unique index if not exists channel_permissions_channel_user_unique
  on app.channel_permissions (channel_id, user_id)
  where user_id is not null;

create unique index if not exists channel_permissions_channel_role_unique
  on app.channel_permissions (channel_id, role)
  where role is not null;
