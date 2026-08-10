-- Append-only exclusions let client offboarding remove one participant from
-- future group settlements without mutating the immutable lesson snapshot.

create table app.lesson_participant_exclusions (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete restrict,
  student_id uuid not null references app.students(id) on delete restrict,
  reason_code text not null,
  actor_user_id uuid not null references app.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (lesson_id, student_id),
  constraint lesson_participant_exclusions_reason_check
    check (reason_code ~ '^[A-Za-z0-9._:-]{1,120}$')
);

create trigger lesson_participant_exclusions_immutable
before update or delete on app.lesson_participant_exclusions
for each row execute function app.reject_immutable_lesson_fact();

create index lesson_participant_exclusions_student_idx
  on app.lesson_participant_exclusions (student_id, lesson_id);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.lesson_participant_exclusions to magiccrm_app;
  end if;
end $$;
