alter table app.schedule_plans
  add column archived_at timestamptz,
  add column archived_by uuid references app.users(id),
  add column archive_reason text,
  add constraint schedule_plan_archive_state_check check (
    (archived_at is null and archived_by is null and archive_reason is null)
    or (archived_at is not null and archived_by is not null
      and archive_reason is not null and length(trim(archive_reason)) > 0 and status = 'ended' and kind = 'individual')
  );

alter table app.lessons add column archived_at timestamptz,
  add constraint lesson_archive_state_check check (archived_at is null or lifecycle_state = 'cancelled');

create function app.guard_archived_lesson_finance() returns trigger language plpgsql as $$
declare archived timestamptz;
begin
  if new.lesson_id is null then return new; end if;
  select archived_at into archived from app.lessons where id = new.lesson_id for share;
  if archived is not null then
    raise exception using errcode = '23514', message = 'LESSON_ARCHIVED';
  end if;
  return new;
end $$;
create trigger payments_archived_lesson_guard before insert or update of lesson_id on app.payments
  for each row execute function app.guard_archived_lesson_finance();
create trigger client_facts_archived_lesson_guard before insert on app.lesson_client_charge_facts
  for each row execute function app.guard_archived_lesson_finance();
create trigger teacher_facts_archived_lesson_guard before insert on app.lesson_teacher_compensation_facts
  for each row execute function app.guard_archived_lesson_finance();
