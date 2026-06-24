drop table if exists app.chat_inbox_state;
drop index if exists app.chats_owner_user_idx;
alter table app.chats drop column if exists assigned_at;
alter table app.chats drop column if exists assigned_to_user_id;
alter table app.chats drop column if exists owner_user_id;
