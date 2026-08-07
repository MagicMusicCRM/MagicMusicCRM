do $$
begin
  if exists (
    select 1 from app.audit_events where reason_text is not null
  ) then
    raise exception
      '0108 down blocked: human audit reasons would be destroyed';
  end if;
end $$;

drop index if exists app.audit_events_entity_action_created_idx;

alter table app.audit_events
  drop constraint if exists audit_events_reason_text_shape,
  drop column if exists reason_text;
