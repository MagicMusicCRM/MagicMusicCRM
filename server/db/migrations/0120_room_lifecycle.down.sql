drop trigger if exists schedule_series_guard_active_room
  on app.schedule_series;
drop trigger if exists lessons_guard_active_room on app.lessons;
drop trigger if exists groups_guard_active_room on app.groups;
drop function if exists app.guard_active_room_reference();

drop trigger if exists rooms_guard_active_parent_branch on app.rooms;
drop function if exists app.guard_room_parent_branch_active();

drop trigger if exists room_lifecycle_history_append_only
  on app.room_lifecycle_history;
drop function if exists app.reject_room_lifecycle_history_mutation();
drop table if exists app.room_lifecycle_history;

delete from app.aggregate_versions
where aggregate_type = 'organization:room';

drop index if exists app.rooms_lifecycle_idx;

alter table app.rooms
  drop constraint if exists rooms_lifecycle_consistency_check,
  drop constraint if exists rooms_version_positive,
  drop constraint if exists rooms_lifecycle_state_check,
  drop column if exists archive_effective_date,
  drop column if exists archive_reason,
  drop column if exists archived_by,
  drop column if exists archived_at,
  drop column if exists version,
  drop column if exists lifecycle_state;
