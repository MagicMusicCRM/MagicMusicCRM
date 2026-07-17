-- Revert to the original day/hour kinds. Rows carrying the new kinds must go
-- first, otherwise the narrower constraint cannot be validated.
delete from app.task_reminders where kind in ('min10', 'overdue');

alter table app.task_reminders
  drop constraint if exists task_reminders_kind_check;

alter table app.task_reminders
  add constraint task_reminders_kind_check
    check (kind in ('day', 'hour'));
