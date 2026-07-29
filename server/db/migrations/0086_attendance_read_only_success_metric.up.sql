-- v4 T4.2.5: remove attendance from the active write domain.
--
-- Historical participation rows remain available for migration and audit, but
-- the runtime role cannot create, edit, delete or truncate them.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    revoke insert, update, delete, truncate
      on app.lesson_participation
      from magiccrm_app;
    grant select on app.lesson_participation to magiccrm_app;
  end if;
end $$;

comment on table app.lesson_participation is
  'Legacy attendance evidence: read-only for runtime; not an active business domain.';

-- Client lesson success is derived exclusively from the terminal lifecycle.
-- Reporting may consume this read model without consulting legacy attendance.
create or replace view app.client_lesson_success_metrics as
select
  snapshot.client_type,
  snapshot.client_id,
  count(*) filter (
    where lesson.lifecycle_state = 'successfully_completed'
  )::bigint as successfully_completed_lessons
from app.lesson_snapshots snapshot
join app.lessons lesson on lesson.id = snapshot.lesson_id
where lesson.deleted_at is null
group by snapshot.client_type, snapshot.client_id;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.client_lesson_success_metrics to magiccrm_app;
  end if;
end $$;
