-- Deleting a message returned 500 for every user, every time.
--
-- `message_payload_check` (0003_messenger) demands that a message carry
-- something: content, an attachment, or be a system message. Soft-delete
-- (message.service.ts — deleteMessage) nulls BOTH content and
-- attachment_file_id, which leaves an ordinary 'text' message satisfying none
-- of the three arms. Postgres rejected the UPDATE, the exception was unhandled,
-- and the client got «Internal Server Error». Only 'system' messages could ever
-- be deleted.
--
-- The constraint's intent is «a LIVE message must have a payload» — a deleted
-- one legitimately has none, which is the entire point of erasing it. Add that
-- arm rather than weakening the rule for live messages.

alter table app.messages
  drop constraint if exists message_payload_check;

alter table app.messages
  add constraint message_payload_check check (
    content is not null
    or attachment_file_id is not null
    or message_type = 'system'
    or deleted_at is not null
  );
