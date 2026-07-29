do $$
begin
  if exists (select 1 from app.lesson_client_charge_facts)
    or exists (select 1 from app.lesson_teacher_compensation_facts) then
    raise exception using
      errcode = '23514',
      message = 'lesson settlement facts exist; rollback would destroy immutable financial evidence';
  end if;
end $$;

drop trigger if exists lesson_teacher_compensation_facts_immutable
  on app.lesson_teacher_compensation_facts;
drop trigger if exists lesson_client_charge_facts_immutable
  on app.lesson_client_charge_facts;

drop table if exists app.lesson_teacher_compensation_facts;
drop table if exists app.lesson_client_charge_facts;

drop trigger if exists lesson_snapshots_immutable on app.lesson_snapshots;
drop trigger if exists lesson_snapshots_fill_duration on app.lesson_snapshots;
drop function if exists app.fill_lesson_snapshot_duration();
alter table app.lesson_snapshots
  drop constraint if exists lesson_snapshots_duration_positive,
  drop column if exists duration_minutes;
create trigger lesson_snapshots_immutable
before update or delete on app.lesson_snapshots
for each row execute function app.reject_immutable_lesson_fact();
