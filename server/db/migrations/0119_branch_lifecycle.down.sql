drop trigger if exists branch_lifecycle_history_append_only
  on app.branch_lifecycle_history;
drop function if exists app.reject_branch_lifecycle_history_mutation();
drop table if exists app.branch_lifecycle_history;

delete from app.aggregate_versions
where aggregate_type = 'organization:branch';

drop index if exists app.branches_lifecycle_idx;

alter table app.branches
  drop constraint if exists branches_lifecycle_consistency_check,
  drop constraint if exists branches_version_positive,
  drop constraint if exists branches_lifecycle_state_check,
  drop column if exists archive_effective_date,
  drop column if exists archive_reason,
  drop column if exists archived_by,
  drop column if exists archived_at,
  drop column if exists version,
  drop column if exists lifecycle_state;
