alter table app.messages
  drop constraint if exists messages_message_type_check;

alter table app.messages
  add constraint messages_message_type_check
  check (message_type in ('text', 'file', 'image', 'voice', 'system'));
