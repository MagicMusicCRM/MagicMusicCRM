do $$
begin
  if exists (
    select 1
    from app.student_funnel_revisions
    where client_type = 'lead'
      and not (branch_id is null and version = 1 and created_by is null)
  ) then
    raise exception 'cannot remove client pipelines while published lead revisions exist';
  end if;
end;
$$;

alter table app.student_funnel_revisions
  disable trigger student_funnel_revision_immutable;
delete from app.student_funnel_revisions where client_type = 'lead';
alter table app.student_funnel_revisions
  enable trigger student_funnel_revision_immutable;

drop index if exists app.client_pipeline_school_version_unique;
drop index if exists app.client_pipeline_branch_version_unique;
drop index if exists app.client_pipeline_branch_latest_idx;

create unique index student_funnel_school_version_unique
  on app.student_funnel_revisions(version)
  where branch_id is null;
create unique index student_funnel_branch_version_unique
  on app.student_funnel_revisions(branch_id, version)
  where branch_id is not null;
create index student_funnel_branch_latest_idx
  on app.student_funnel_revisions(branch_id, version desc);

alter table app.student_funnel_revisions
  drop constraint if exists student_funnel_revisions_client_type_check;
alter table app.student_funnel_revisions drop column if exists client_type;

drop index if exists app.lead_statuses_stage_key_unique;
delete from app.lead_statuses status
where status.stage_key = 'new'
  and status.name = 'Новые'
  and not exists (
    select 1 from app.leads lead where lead.status_id = status.id
  );
alter table app.lead_statuses drop column if exists stage_key;
