-- Row-level claim for push delivery so two concurrent dispatch drains (the new
-- periodic push loop + the on-enqueue trigger) can never send the same push
-- twice. A queued row is claimed by stamping dispatch_claimed_at; a stale claim
-- (process crashed mid-send) becomes re-claimable after a grace period.
alter table app.notification_deliveries
  add column if not exists dispatch_claimed_at timestamptz;

create index if not exists notification_deliveries_push_queued_idx
  on app.notification_deliveries (created_at)
  where channel = 'push' and status = 'queued';
