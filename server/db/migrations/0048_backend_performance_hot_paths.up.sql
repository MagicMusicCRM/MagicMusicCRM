-- migrate:no-transaction
-- Backend-only hot-path indexes from the 2026-06-25 performance audit.
-- These are safe to apply online: CONCURRENTLY avoids blocking lesson/task writes.

create index concurrently if not exists lessons_room_active_overlap_idx
  on app.lessons (room_id, scheduled_at)
  include (duration_minutes, status, group_id, teacher_id, branch_id)
  where deleted_at is null
    and status <> 'cancelled'
    and room_id is not null;

create index concurrently if not exists lessons_teacher_active_overlap_idx
  on app.lessons (teacher_id, scheduled_at)
  include (duration_minutes, status, room_id, group_id, branch_id)
  where deleted_at is null
    and status <> 'cancelled'
    and teacher_id is not null;

create index concurrently if not exists tasks_entity_status_due_active_idx
  on app.tasks (entity_type, entity_id, status, due_at)
  where deleted_at is null;
