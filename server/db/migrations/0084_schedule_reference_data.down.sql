do $$
begin
  if exists (select 1 from app.branch_hours)
    or exists (select 1 from app.branch_hour_exceptions)
    or exists (select 1 from app.teacher_availability_rules) then
    raise exception
      'Refusing destructive rollback: schedule reference data exists';
  end if;
end $$;

drop trigger if exists teacher_availability_validate_timezone
  on app.teacher_availability_rules;
drop trigger if exists branches_validate_schedule_timezone on app.branches;
drop function if exists app.assert_schedule_timezone();

drop table if exists app.teacher_availability_rules;
drop table if exists app.branch_hour_exceptions;
drop table if exists app.branch_hours;

drop index if exists app.teacher_branches_active_idx;

alter table app.teacher_branches
  drop constraint if exists teacher_branches_version_positive,
  drop constraint if exists teacher_branches_active_range_check,
  drop column if exists updated_at,
  drop column if exists version,
  drop column if exists active_until,
  drop column if exists active_from;

alter table app.teachers
  drop constraint if exists teachers_schedule_reference_version_positive,
  drop column if exists schedule_reference_version;

alter table app.branches
  drop constraint if exists branches_timezone_name_nonempty,
  drop constraint if exists branches_schedule_reference_version_positive,
  drop column if exists schedule_reference_version,
  drop column if exists timezone_name;
