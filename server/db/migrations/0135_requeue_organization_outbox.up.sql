-- Organization lifecycle events were valid facts, but releases through 1.5.6
-- could not dispatch them and eventually dead-lettered them. Keep the facts
-- intact and re-arm only the delivery metadata now that the worker supports
-- every organization lifecycle event type.
update app.platform_outbox_events
set attempts = 0,
    available_at = now(),
    claimed_at = null,
    claimed_by = null,
    last_error = null,
    dead_lettered_at = null
where published_at is null
  and dead_lettered_at is not null
  and event_type in (
    'organization.branch.changed',
    'organization.room.changed',
    'organization.group.changed',
    'organization.person.changed'
  );
