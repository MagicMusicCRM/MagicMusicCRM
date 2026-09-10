-- Matches the latest-reservation LATERAL read used by the schedule and student
-- lessons. A current reservation outranks newer terminal history by design.
-- This migration only adds an access path; it does not alter financial facts.
set local lock_timeout = '5s';
set local statement_timeout = '2min';
create index lesson_reservations_current_read_idx
  on app.lesson_reservations
  (lesson_id, (state = 'reserved') desc, updated_at desc, id desc)
  include (state);
