alter table app.messages
  add column if not exists voice_duration_ms integer;

-- A soft-deleted media message intentionally has neither content nor an
-- attachment. The original constraint made DELETE /messages/:id fail for
-- every file, image and voice message.
alter table app.messages
  drop constraint if exists message_payload_check;

alter table app.messages
  add constraint message_payload_check
  check (
    deleted_at is not null
    or content is not null
    or attachment_file_id is not null
    or message_type = 'system'
  ) not valid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_attachment_file_fk'
      and conrelid = 'app.messages'::regclass
  ) then
    alter table app.messages
      add constraint messages_attachment_file_fk
      foreign key (attachment_file_id)
      references app.file_objects(id)
      on delete set null
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_voice_duration_check'
      and conrelid = 'app.messages'::regclass
  ) then
    alter table app.messages
      add constraint messages_voice_duration_check
      check (
        voice_duration_ms is null
        or (
          message_type = 'voice'
          and voice_duration_ms between 1 and 3600000
        )
      ) not valid;
  end if;
end $$;
