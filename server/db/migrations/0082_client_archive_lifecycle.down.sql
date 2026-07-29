drop trigger if exists students_sync_aggregate_version on app.students;
drop trigger if exists leads_sync_aggregate_version on app.leads;
drop function if exists app.sync_client_aggregate_version();

delete from app.aggregate_versions
where aggregate_type in ('crm:lead', 'crm:student');

alter table app.students
  drop constraint if exists students_version_positive,
  drop column if exists version;

alter table app.leads
  drop constraint if exists leads_version_positive,
  drop column if exists version;
