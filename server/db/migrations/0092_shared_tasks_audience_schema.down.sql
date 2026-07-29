do $$
begin
  if exists (
    select 1 from app.shared_tasks where origin = 'runtime'
  ) then
    raise exception
      'Refusing destructive rollback: runtime SharedTask rows exist';
  end if;
end $$;

drop trigger if exists task_audience_resolution_audits_append_only
  on app.task_audience_resolution_audits;
drop trigger if exists task_closes_append_only on app.task_closes;
drop function if exists app.reject_shared_task_append_only_fact();

drop table if exists app.shared_task_legacy_links;
drop table if exists app.task_audience_resolution_audits;
drop table if exists app.shared_task_reminders;
drop table if exists app.task_closes;
drop table if exists app.task_audiences;
drop table if exists app.shared_tasks;
