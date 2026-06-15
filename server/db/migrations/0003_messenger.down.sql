drop table if exists app.channel_posts;
drop table if exists app.channel_permissions;
drop table if exists app.channels;
drop table if exists app.message_reactions;
alter table if exists app.chat_members drop constraint if exists chat_members_last_read_message_fk;
drop table if exists app.messages;
drop table if exists app.chat_members;
drop table if exists app.chats;
