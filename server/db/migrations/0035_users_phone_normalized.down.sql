-- server/db/migrations/0035_users_phone_normalized.down.sql
drop index if exists app.users_phone_normalized_idx;
alter table app.users drop column if exists phone_normalized;
