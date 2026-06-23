-- server/db/migrations/0038_perf_indexes.up.sql
-- Performance indexes for hot CRM read paths that fell back to sequential scans
-- as the HolliHop-imported data grew (47k lessons, 36k participation rows):
--   * lessons.group_id — group-class joins (schedule matrix, student balances,
--                        finance reports) had no index and scanned all lessons.
--   * lesson_participation(lesson_id) / (student_id) — the participation joins in
--                        the balance/attendance queries scanned the whole table.
create index if not exists lessons_group_idx
  on app.lessons (group_id)
  where deleted_at is null and group_id is not null;

create index if not exists lesson_participation_lesson_idx
  on app.lesson_participation (lesson_id);

create index if not exists lesson_participation_student_idx
  on app.lesson_participation (student_id);
