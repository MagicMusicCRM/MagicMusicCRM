-- Real task priority + a with-time / all-day distinction for the due date.
--
-- Until now «приоритет» was a filter dropdown wired to nothing: the board query
-- LIKE-matched the English key («high») against the task's Russian title/
-- description, so it near-always returned zero. There was no column to store a
-- priority at all. This adds one, plus `due_all_day` so a task can carry a date
-- without a meaningful time (the owner asked for «время / без времени»).

alter table app.tasks
  add column if not exists priority text not null default 'medium';

alter table app.tasks
  drop constraint if exists tasks_priority_check;
alter table app.tasks
  add constraint tasks_priority_check
  check (priority in ('low', 'medium', 'high'));

alter table app.tasks
  add column if not exists due_all_day boolean not null default false;

-- The board orders by due_at and filters overdue by it constantly.
create index if not exists tasks_priority_idx
  on app.tasks (priority) where deleted_at is null;
