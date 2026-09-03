-- Released reservations are immutable history. Rebooking creates a new row.
-- Keep at most one live reservation per lesson/subscription pair.
drop index if exists app.lesson_reservations_lesson_subscription_idx;

create unique index lesson_reservations_lesson_subscription_idx
  on app.lesson_reservations (lesson_id, subscription_id)
  where state = 'reserved';

create index lesson_reservations_history_idx
  on app.lesson_reservations (lesson_id, subscription_id, created_at, id);
