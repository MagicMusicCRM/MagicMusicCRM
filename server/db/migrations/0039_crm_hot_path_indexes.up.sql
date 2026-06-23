-- server/db/migrations/0039_crm_hot_path_indexes.up.sql
-- app.groups had only its PRIMARY KEY, so the hot CRM read paths that filter
-- groups by teacher/branch/room (getTeachers' correlated aggregates, listGroups)
-- fell back to full sequential scans. Live prod stats (pg_stat_user_tables):
-- groups seq_scan=2.3M, seq_tup_read=9.9B over ~4.3k rows. Index the FK columns.
create index if not exists groups_teacher_idx
  on app.groups (teacher_id)
  where deleted_at is null;

create index if not exists groups_branch_idx
  on app.groups (branch_id)
  where deleted_at is null;

create index if not exists groups_room_idx
  on app.groups (room_id)
  where deleted_at is null;

-- group_students has a unique (group_id, student_id) index which covers
-- group-first lookups, but "which groups is this student in" scanned the table.
create index if not exists group_students_student_idx
  on app.group_students (student_id);
