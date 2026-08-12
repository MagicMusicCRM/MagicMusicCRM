alter table app.messages
  drop constraint if exists messages_voice_duration_check;

alter table app.messages
  drop constraint if exists messages_attachment_file_fk;

alter table app.messages
  drop column if exists voice_duration_ms;

alter table app.messages
  drop constraint if exists message_payload_check;

alter table app.messages
  add constraint message_payload_check
  check (
    content is not null
    or attachment_file_id is not null
    or message_type = 'system'
  ) not valid;
