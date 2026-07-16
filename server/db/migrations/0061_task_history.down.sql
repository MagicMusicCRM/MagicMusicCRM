-- server/db/migrations/0061_task_history.down.sql
drop index if exists app.task_history_source_idx;
drop index if exists app.task_history_field_idx;
drop index if exists app.task_history_task_idx;
drop table if exists app.task_history;
