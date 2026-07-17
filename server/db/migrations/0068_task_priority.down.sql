drop index if exists app.tasks_priority_idx;

alter table app.tasks
  drop constraint if exists tasks_priority_check;

alter table app.tasks
  drop column if exists due_all_day;

alter table app.tasks
  drop column if exists priority;
