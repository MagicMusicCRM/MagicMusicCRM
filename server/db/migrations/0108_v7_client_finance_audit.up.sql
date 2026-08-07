alter table app.audit_events
  add column if not exists reason_text text;

alter table app.audit_events
  drop constraint if exists audit_events_reason_text_shape;

alter table app.audit_events
  add constraint audit_events_reason_text_shape check (
    reason_text is null
    or (
      char_length(btrim(reason_text)) between 1 and 500
      and reason_text = btrim(reason_text)
    )
  );

create index if not exists audit_events_entity_action_created_idx
  on app.audit_events (entity_type, entity_id, action, created_at desc, id);
