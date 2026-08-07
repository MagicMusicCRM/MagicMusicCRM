do $$
begin
  if exists (select 1 from app.lesson_settlement_corrections) then
    raise exception 'Refusing destructive rollback: settlement corrections exist';
  end if;
end $$;

drop view if exists app.lesson_teacher_compensation_facts_effective;
drop view if exists app.lesson_client_charge_facts_effective;
drop trigger if exists lesson_settlement_corrections_immutable
  on app.lesson_settlement_corrections;

drop index if exists app.lesson_teacher_compensation_facts_correction_idx;
drop index if exists app.lesson_teacher_compensation_facts_supersedes_idx;
drop index if exists app.lesson_teacher_compensation_facts_root_idx;
alter table app.lesson_teacher_compensation_facts
  drop column if exists supersedes_fact_id,
  drop column if exists correction_id;
alter table app.lesson_teacher_compensation_facts
  add constraint lesson_teacher_compensation_facts_lesson_id_key unique (lesson_id);

drop index if exists app.lesson_client_charge_facts_correction_subject_idx;
drop index if exists app.lesson_client_charge_facts_supersedes_idx;
drop index if exists app.lesson_client_charge_facts_root_subject_idx;
alter table app.lesson_client_charge_facts
  drop column if exists supersedes_fact_id,
  drop column if exists correction_id;
create unique index lesson_client_charge_facts_subject_unique_idx
  on app.lesson_client_charge_facts (lesson_id, client_type, client_id);

drop index if exists app.lesson_settlement_corrections_supersedes_idx;
drop index if exists app.lesson_settlement_corrections_root_idx;
drop table if exists app.lesson_settlement_corrections;
