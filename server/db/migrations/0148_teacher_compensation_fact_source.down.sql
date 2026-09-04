lock table app.lesson_teacher_compensation_facts in share row exclusive mode;

do $$
begin
  if exists (
    select 1
    from app.lesson_teacher_compensation_facts
    where compensation_source is not null
  ) then
    raise exception 'Refusing destructive rollback: explicit teacher compensation source facts exist';
  end if;
end $$;

drop view if exists app.lesson_teacher_compensation_facts_effective;

alter table app.lesson_teacher_compensation_facts
  drop constraint if exists lesson_teacher_compensation_facts_source_check,
  drop column if exists compensation_source;

create view app.lesson_teacher_compensation_facts_effective as
select fact.*
from app.lesson_teacher_compensation_facts fact
where not exists (
  select 1 from app.lesson_teacher_compensation_facts newer
  where newer.supersedes_fact_id = fact.id
);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.lesson_teacher_compensation_facts_effective to magiccrm_app;
  end if;
end $$;
