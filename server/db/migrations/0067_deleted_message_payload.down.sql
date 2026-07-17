-- Back to «every message must carry a payload, deleted or not». Any message
-- already soft-deleted would violate it, so purge those rows first — their
-- content and attachment are gone regardless; only the tombstone is dropped.

delete from app.messages where deleted_at is not null;

alter table app.messages
  drop constraint if exists message_payload_check;

alter table app.messages
  add constraint message_payload_check check (
    content is not null
    or attachment_file_id is not null
    or message_type = 'system'
  );
