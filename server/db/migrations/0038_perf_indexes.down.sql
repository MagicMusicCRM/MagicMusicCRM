-- server/db/migrations/0038_perf_indexes.down.sql
drop index if exists app.lesson_participation_student_idx;
drop index if exists app.lesson_participation_lesson_idx;
drop index if exists app.lessons_group_idx;
