drop trigger if exists schedule_series_guard_active_teacher on app.schedule_series;
drop trigger if exists lessons_guard_active_teacher on app.lessons;
drop trigger if exists staff_branches_guard_active_staff on app.staff_branch_assignments;
drop trigger if exists teacher_branches_guard_active_teacher on app.teacher_branches;
drop function if exists app.guard_active_teacher_schedule_reference();
drop function if exists app.guard_active_staff_assignment();
drop function if exists app.guard_active_teacher_assignment();

drop trigger if exists person_lifecycle_history_append_only
  on app.person_lifecycle_history;
drop function if exists app.reject_person_lifecycle_history_mutation();
drop table if exists app.person_lifecycle_history;

drop index if exists app.staff_members_lifecycle_idx;
drop index if exists app.teachers_lifecycle_idx;

alter table app.staff_members
  drop constraint if exists staff_members_lifecycle_state_check,
  drop constraint if exists staff_members_version_positive,
  drop column if exists lifecycle_snapshot,
  drop column if exists lifecycle_account_was_active,
  drop column if exists lifecycle_previous_status,
  drop column if exists offboard_reason,
  drop column if exists offboarded_by,
  drop column if exists offboarded_at,
  drop column if exists version,
  drop column if exists lifecycle_state;

alter table app.teachers
  drop constraint if exists teachers_lifecycle_state_check,
  drop column if exists lifecycle_snapshot,
  drop column if exists lifecycle_account_was_active,
  drop column if exists lifecycle_previous_status,
  drop column if exists offboard_reason,
  drop column if exists offboarded_by,
  drop column if exists offboarded_at,
  drop column if exists lifecycle_state;

alter table app.users
  drop column if exists email_changed_at,
  drop column if exists password_changed_at;
