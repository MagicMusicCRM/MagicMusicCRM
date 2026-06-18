-- Room-based schedule lookup and overlap detection
create index if not exists lessons_room_scheduled_idx
  on app.lessons (room_id, scheduled_at)
  where deleted_at is null;

-- Branch filter for schedule matrix
create index if not exists lessons_branch_scheduled_idx
  on app.lessons (branch_id, scheduled_at)
  where deleted_at is null;
