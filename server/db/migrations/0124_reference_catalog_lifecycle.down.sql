drop trigger if exists lead_status_history_guard_active_reason on app.lead_status_history;
drop function if exists app.guard_active_loss_reason_reference();

drop trigger if exists subscription_packages_guard_active_discipline on app.subscription_packages;
drop trigger if exists teacher_disciplines_guard_active_discipline on app.teacher_disciplines;
drop trigger if exists student_disciplines_guard_active_discipline on app.student_disciplines;
drop trigger if exists branch_disciplines_guard_active_discipline on app.branch_disciplines;
drop function if exists app.guard_active_discipline_reference();

drop trigger if exists branch_disciplines_reject_physical_delete on app.branch_disciplines;
drop trigger if exists lead_loss_reasons_reject_physical_delete on app.lead_loss_reasons;
drop trigger if exists disciplines_reject_physical_delete on app.disciplines;
drop function if exists app.reject_reference_physical_delete();

drop trigger if exists lead_status_history_append_only on app.lead_status_history;
drop function if exists app.reject_lead_status_history_mutation();
drop trigger if exists reference_catalog_history_append_only on app.reference_catalog_history;
drop function if exists app.reject_reference_catalog_history_mutation();
drop table if exists app.reference_catalog_history;

alter table app.lead_status_history
  drop constraint if exists lead_status_history_reason_snapshot_check,
  drop column if exists reason_kind_snapshot,
  drop column if exists reason_name_snapshot;

delete from app.aggregate_versions
where aggregate_type in (
  'reference:discipline',
  'reference:loss_reason',
  'reference:branch_discipline'
);

drop index if exists app.disciplines_name_idx;
create unique index disciplines_name_idx
  on app.disciplines (lower(name)) where deleted_at is null;
drop index if exists app.lead_loss_reasons_name_kind_idx;
create unique index lead_loss_reasons_name_kind_idx
  on app.lead_loss_reasons (lower(name), kind) where deleted_at is null;

alter table app.branch_disciplines
  drop constraint if exists branch_disciplines_lifecycle_consistency_check,
  drop constraint if exists branch_disciplines_version_positive,
  drop constraint if exists branch_disciplines_lifecycle_state_check,
  drop column if exists archive_reason,
  drop column if exists archived_by,
  drop column if exists archived_at,
  drop column if exists updated_at,
  drop column if exists version,
  drop column if exists lifecycle_state;

alter table app.lead_loss_reasons
  drop constraint if exists lead_loss_reasons_lifecycle_consistency_check,
  drop constraint if exists lead_loss_reasons_name_not_blank,
  drop constraint if exists lead_loss_reasons_version_positive,
  drop constraint if exists lead_loss_reasons_lifecycle_state_check,
  drop column if exists archive_reason,
  drop column if exists archived_by,
  drop column if exists archived_at,
  drop column if exists version,
  drop column if exists lifecycle_state;

alter table app.disciplines
  drop constraint if exists disciplines_lifecycle_consistency_check,
  drop constraint if exists disciplines_name_not_blank,
  drop constraint if exists disciplines_version_positive,
  drop constraint if exists disciplines_lifecycle_state_check,
  drop column if exists archive_reason,
  drop column if exists archived_by,
  drop column if exists archived_at,
  drop column if exists version,
  drop column if exists lifecycle_state;
