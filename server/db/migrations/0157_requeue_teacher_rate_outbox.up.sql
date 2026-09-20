-- Preserve the failed delivery state in append-only audit before rearming it.
-- Event identity, payload, request, aggregate and financial facts are unchanged.
with failed as materialized (
  select * from app.platform_outbox_events
  where event_type = 'crm.lesson_teacher_rate.changed'
    and aggregate_type = 'schedule:teacher-rate-bulk'
    and aggregate_id = 'global'
    and payload->>'action' = 'bulk_set'
    and published_at is null and dead_lettered_at is not null
  for update
), audited as (
  insert into app.audit_events (
    action, entity_type, entity_id, request_id, reason, before_ref, after_ref
  )
  select 'platform.outbox.requeued', 'platform:outbox', event_id::text,
    'migration:0157_requeue_teacher_rate_outbox',
    'Supported teacher-rate invalidation handler; retry delivery only',
    jsonb_build_object('attempts', attempts, 'lastError', last_error,
      'deadLetteredAt', dead_lettered_at, 'availableAt', available_at,
      'claimedAt', claimed_at, 'claimedBy', claimed_by),
    jsonb_build_object('attempts', 0, 'deliveryState', 'pending')
  from failed
  returning entity_id
)
update app.platform_outbox_events event
set attempts = 0, available_at = now(), claimed_at = null, claimed_by = null,
    last_error = null, dead_lettered_at = null
from audited
where event.event_id::text = audited.entity_id;
