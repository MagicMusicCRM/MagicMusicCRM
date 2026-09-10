-- Do not discard archive history during a rollback.
do $$ begin
  if exists (select 1 from app.schedule_plans where archived_at is not null) then
    raise exception 'Restore the compatible application; archive history cannot be dropped';
  end if;
end $$;
drop trigger payments_archived_lesson_guard on app.payments;
drop trigger client_facts_archived_lesson_guard on app.lesson_client_charge_facts;
drop trigger teacher_facts_archived_lesson_guard on app.lesson_teacher_compensation_facts;
drop function app.guard_archived_lesson_finance();
alter table app.lessons drop constraint lesson_archive_state_check, drop column archived_at;
alter table app.schedule_plans drop constraint schedule_plan_archive_state_check,
  drop column archive_reason, drop column archived_by, drop column archived_at;
