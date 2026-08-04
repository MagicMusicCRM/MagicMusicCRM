create table if not exists app.student_funnel_revisions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid references app.branches(id),
  version bigint not null check (version > 0),
  patch jsonb not null check (jsonb_typeof(patch) = 'object'),
  effective_snapshot jsonb not null
    check (jsonb_typeof(effective_snapshot) = 'object'),
  reason text not null check (nullif(btrim(reason), '') is not null),
  rollback_from_version bigint,
  created_by uuid references app.users(id),
  created_at timestamptz not null default now()
);

create unique index if not exists student_funnel_school_version_unique
  on app.student_funnel_revisions(version)
  where branch_id is null;

create unique index if not exists student_funnel_branch_version_unique
  on app.student_funnel_revisions(branch_id, version)
  where branch_id is not null;

create index if not exists student_funnel_branch_latest_idx
  on app.student_funnel_revisions(branch_id, version desc);

insert into app.student_funnel_revisions (
  branch_id,
  version,
  patch,
  effective_snapshot,
  reason
)
values (
  null,
  1,
  '{
    "stages": [
      {"key":"trial","label":"Пробные","style":"cyan","active":true,"allowedTransitions":["active","inactive"]},
      {"key":"active","label":"Активные","style":"green","active":true,"allowedTransitions":["paused","completed","inactive"]},
      {"key":"paused","label":"Пауза","style":"amber","active":true,"allowedTransitions":["active","completed","inactive"]},
      {"key":"completed","label":"Завершили обучение","style":"slate","active":true,"allowedTransitions":["active"]},
      {"key":"inactive","label":"Неактивные","style":"gray","active":true,"allowedTransitions":["active"]}
    ]
  }'::jsonb,
  '{
    "stages": [
      {"key":"trial","label":"Пробные","style":"cyan","active":true,"allowedTransitions":["active","inactive"]},
      {"key":"active","label":"Активные","style":"green","active":true,"allowedTransitions":["paused","completed","inactive"]},
      {"key":"paused","label":"Пауза","style":"amber","active":true,"allowedTransitions":["active","completed","inactive"]},
      {"key":"completed","label":"Завершили обучение","style":"slate","active":true,"allowedTransitions":["active"]},
      {"key":"inactive","label":"Неактивные","style":"gray","active":true,"allowedTransitions":["active"]}
    ]
  }'::jsonb,
  'Системная конфигурация v6'
)
on conflict do nothing;

create or replace function app.protect_student_funnel_revision()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '23514',
    message = 'student funnel revisions are immutable';
end;
$$;

drop trigger if exists student_funnel_revision_immutable
  on app.student_funnel_revisions;
create trigger student_funnel_revision_immutable
before update or delete on app.student_funnel_revisions
for each row execute function app.protect_student_funnel_revision();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.student_funnel_revisions to magiccrm_app;
  end if;
end;
$$;
