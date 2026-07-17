-- Two more task reminder kinds beyond the original day/hour:
--   min10   — 10 minutes before the deadline (requires the 1-minute scheduler
--             tick; a 5-minute tick would fire it anywhere from 5 to 10 min out)
--   overdue — one minute AFTER the deadline passed ("задача просрочена")
-- Idempotency is unchanged: unique (task_id, kind) still means each reminder
-- is delivered exactly once per task.
alter table app.task_reminders
  drop constraint if exists task_reminders_kind_check;

alter table app.task_reminders
  add constraint task_reminders_kind_check
    check (kind in ('day', 'hour', 'min10', 'overdue'));
