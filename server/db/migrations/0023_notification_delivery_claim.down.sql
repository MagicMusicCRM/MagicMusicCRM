drop index if exists app.notification_deliveries_push_queued_idx;
alter table app.notification_deliveries drop column if exists dispatch_claimed_at;
