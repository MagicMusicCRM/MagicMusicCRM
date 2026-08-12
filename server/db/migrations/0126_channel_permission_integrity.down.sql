drop index if exists app.channel_permissions_channel_role_unique;
drop index if exists app.channel_permissions_channel_user_unique;

alter table app.channel_permissions
  drop constraint if exists channel_permission_write_requires_read_check,
  drop constraint if exists channel_permission_exact_target_check;

alter table app.channel_permissions
  add constraint channel_permission_target_check
    check (user_id is not null or role is not null);
