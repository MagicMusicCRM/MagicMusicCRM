do $$
begin
  if exists (
    select 1 from app.shared_tasks
    where origin = 'runtime' and priority <> 'medium'
  ) then
    raise exception '0101 rollback refused: runtime task priorities would be lost';
  end if;
  if exists (
    select 1
    from app.task_audience_resolution_audits audit
    left join app.task_audiences audience on audience.id = audit.matched_audience_id
    where audit.matched_audience_id is not null and audience.id is null
  ) then
    raise exception '0101 rollback refused: mutable audience history cannot restore legacy FK';
  end if;
end $$;

drop view if exists app.canonical_tasks;
drop view if exists app.shared_task_visibility;
drop view if exists app.shared_task_recipients;

delete from app.audit_events
where entity_type = 'shared_task'
  and action like 'workflow.shared_task_legacy_%'
  and metadata ? 'legacyHistoryId';

drop index if exists app.shared_tasks_priority_idx;
drop index if exists app.shared_tasks_branch_idx;
alter table app.shared_tasks drop constraint if exists shared_tasks_priority_check;
alter table app.shared_tasks drop column if exists priority;
alter table app.shared_tasks drop column if exists branch_id;

alter table app.task_audience_resolution_audits
  drop constraint if exists task_audience_resolution_audits_matched_audience_id_fkey;
alter table app.task_audience_resolution_audits
  add constraint task_audience_resolution_audits_matched_audience_id_fkey
  foreign key (matched_audience_id) references app.task_audiences(id) on delete restrict;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete
      on app.tasks, app.task_history, app.task_reminders to magiccrm_app;
  end if;
end $$;
