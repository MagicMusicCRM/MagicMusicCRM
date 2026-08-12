drop trigger if exists groups_guard_assignment_change on app.groups;
drop function if exists app.guard_group_assignment_change();

drop trigger if exists groups_reject_physical_delete on app.groups;
drop function if exists app.reject_group_physical_delete();

drop trigger if exists group_students_guard_active_group on app.group_students;
drop function if exists app.guard_group_membership_parent_active();

drop trigger if exists schedule_plans_guard_active_group on app.schedule_plans;
drop trigger if exists schedule_series_guard_active_group on app.schedule_series;
drop trigger if exists lessons_guard_active_group on app.lessons;
drop function if exists app.guard_active_group_schedule_reference();

drop trigger if exists groups_guard_active_references on app.groups;
drop function if exists app.guard_group_active_references();

drop trigger if exists group_lifecycle_history_append_only
  on app.group_lifecycle_history;
drop function if exists app.reject_group_lifecycle_history_mutation();
drop table if exists app.group_lifecycle_history;

delete from app.aggregate_versions
where aggregate_type = 'organization:group';

drop index if exists app.groups_lifecycle_idx;

alter table app.groups
  drop constraint if exists groups_lifecycle_consistency_check,
  drop constraint if exists groups_version_positive,
  drop constraint if exists groups_lifecycle_state_check,
  drop column if exists archive_effective_date,
  drop column if exists archive_reason,
  drop column if exists archived_by,
  drop column if exists archived_at,
  drop column if exists version,
  drop column if exists lifecycle_state;
