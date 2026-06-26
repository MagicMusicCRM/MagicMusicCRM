-- migrate:no-transaction
drop index concurrently if exists app.tasks_entity_status_due_active_idx;
drop index concurrently if exists app.lessons_teacher_active_overlap_idx;
drop index concurrently if exists app.lessons_room_active_overlap_idx;
