alter table app.student_funnel_revisions
  add column if not exists client_type text not null default 'student';

alter table app.student_funnel_revisions
  drop constraint if exists student_funnel_revisions_client_type_check;
alter table app.student_funnel_revisions
  add constraint student_funnel_revisions_client_type_check
  check (client_type in ('lead', 'student'));

drop index if exists app.student_funnel_school_version_unique;
drop index if exists app.student_funnel_branch_version_unique;
drop index if exists app.student_funnel_branch_latest_idx;

create unique index client_pipeline_school_version_unique
  on app.student_funnel_revisions(client_type, version)
  where branch_id is null;
create unique index client_pipeline_branch_version_unique
  on app.student_funnel_revisions(client_type, branch_id, version)
  where branch_id is not null;
create index client_pipeline_branch_latest_idx
  on app.student_funnel_revisions(client_type, branch_id, version desc);

alter table app.lead_statuses add column if not exists stage_key text;
insert into app.lead_statuses (
  stage_key, name, color, sort_order, is_terminal, requires_reason
)
select 'new', 'Новые', 'cyan', 0, false, false
where not exists (select 1 from app.lead_statuses);
update app.lead_statuses
set stage_key = 'lead_' || replace(id::text, '-', '')
where stage_key is null;
alter table app.lead_statuses alter column stage_key set not null;
create unique index if not exists lead_statuses_stage_key_unique
  on app.lead_statuses(stage_key);

insert into app.student_funnel_revisions (
  client_type,
  branch_id,
  version,
  patch,
  effective_snapshot,
  reason
)
select
  'lead',
  null,
  1,
  jsonb_build_object('stages', snapshot.stages),
  jsonb_build_object('stages', snapshot.stages),
  'Начальная конфигурация воронки лидов'
from (
  select jsonb_agg(
    jsonb_build_object(
      'key', status.stage_key,
      'label', status.name,
      'style', case
        when coalesce(status.color, '') ~ '^(cyan|green|amber|slate|gray|red|#[0-9A-Fa-f]{6})$'
          then status.color
        else 'gray'
      end,
      'active', true,
      'terminal', status.is_terminal,
      'requiresReason', status.requires_reason,
      'allowedTransitions', coalesce((
        select jsonb_agg(target.stage_key order by target.sort_order, target.name, target.id)
        from app.lead_statuses target
        where target.id <> status.id
      ), '[]'::jsonb)
    )
    order by status.sort_order, status.name, status.id
  ) as stages
  from app.lead_statuses status
) snapshot
where snapshot.stages is not null
on conflict do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.student_funnel_revisions to magiccrm_app;
  end if;
end;
$$;
