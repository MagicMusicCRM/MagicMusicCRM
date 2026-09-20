alter table app.lesson_teacher_compensation_facts
  add column if not exists compensation_source text;

alter table app.lesson_teacher_compensation_facts
  drop constraint if exists lesson_teacher_compensation_facts_source_check,
  add constraint lesson_teacher_compensation_facts_source_check
    check (
      compensation_source is null
      or compensation_source in ('automatic', 'manual')
    );

create or replace view app.lesson_teacher_compensation_facts_effective as
select fact.*
from app.lesson_teacher_compensation_facts fact
where not exists (
  select 1 from app.lesson_teacher_compensation_facts newer
  where newer.supersedes_fact_id = fact.id
);
