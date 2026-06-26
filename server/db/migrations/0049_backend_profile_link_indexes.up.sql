-- migrate:no-transaction
-- Backend-only profile linking indexes from the 2026-06-25 performance audit.

create index concurrently if not exists students_profile_active_idx
  on app.students (profile_id)
  where deleted_at is null;

create index concurrently if not exists teachers_profile_active_idx
  on app.teachers (profile_id)
  where deleted_at is null;
