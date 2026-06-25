-- Revert hours back to integer lesson counts (rounding any fractional values).
alter table app.subscription_packages
  alter column lessons_total type integer using round(lessons_total);

alter table app.subscriptions
  alter column lessons_total type integer using round(lessons_total),
  alter column lessons_used type integer using round(lessons_used);
