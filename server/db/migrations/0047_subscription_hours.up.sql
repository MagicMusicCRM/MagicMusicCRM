-- Subscriptions are now sized and consumed in HOURS of lessons rather than a
-- raw lesson count (KVA). The columns keep their historical names
-- (lessons_total / lessons_used) to avoid churning ~10 queries + DTOs, but they
-- now hold HOURS and are numeric so fractional lessons (e.g. a 90-minute = 1.5h
-- lesson) are tracked exactly. Safe with no data migration: prod currently has
-- 0 packages and 0 subscriptions.
alter table app.subscription_packages
  alter column lessons_total type numeric(6, 2);

alter table app.subscriptions
  alter column lessons_total type numeric(6, 2),
  alter column lessons_used type numeric(6, 2);
