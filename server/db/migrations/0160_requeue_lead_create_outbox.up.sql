-- Rearm only resolvable Lead-create delivery failures after the worker gained
-- support for this event. Preserve event identity, payload and command facts;
-- record the failed delivery state in append-only audit first.
with failed as materialized (
  select event.*,
    idempotency.result_ref->>'leadId' as resolved_lead_id
  from app.platform_outbox_events event
  join app.idempotency_records idempotency
    on idempotency.outbox_event_id = event.event_id
  where event.event_type = 'crm.lead.create.committed'
    and event.aggregate_type = 'client_create_command'
    and idempotency.operation = 'crm.lead.create'
    and idempotency.status = 'completed'
    and nullif(idempotency.result_ref->>'leadId', '') is not null
    and event.published_at is null
    and event.dead_lettered_at is not null
  for update of event
), audited as (
  insert into app.audit_events (
    action, entity_type, entity_id, request_id, reason, before_ref, after_ref
  )
  select 'platform.outbox.requeued', 'platform:outbox', event_id::text,
    'migration:0160_requeue_lead_create_outbox',
    'Supported Lead-create invalidation handler; retry delivery only',
    jsonb_build_object(
      'attempts', attempts,
      'lastError', last_error,
      'deadLetteredAt', dead_lettered_at,
      'availableAt', available_at,
      'claimedAt', claimed_at,
      'claimedBy', claimed_by
    ),
    jsonb_build_object(
      'attempts', 0,
      'deliveryState', 'pending',
      'entityId', resolved_lead_id
    )
  from failed
  returning entity_id
)
update app.platform_outbox_events event
set attempts = 0,
    available_at = now(),
    claimed_at = null,
    claimed_by = null,
    last_error = null,
    dead_lettered_at = null
from audited
where event.event_id::text = audited.entity_id;
