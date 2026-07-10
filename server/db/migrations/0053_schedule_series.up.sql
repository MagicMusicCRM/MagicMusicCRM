-- KVA-236: постоянное расписание. Серия — шаблон «каждый <день недели> в
-- <время> у <педагога> в <аудитории>» с периодом действия; valid_until IS NULL
-- означает «до бесконечности» (требование заказчика: «с 15.07 и до
-- бесконечности») — занятия догенерируются воркером по горизонту.
create table if not exists app.schedule_series (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references app.students(id) on delete cascade,
  group_id uuid references app.groups(id) on delete cascade,
  teacher_id uuid references app.teachers(id) on delete set null,
  room_id uuid references app.rooms(id) on delete set null,
  branch_id uuid references app.branches(id) on delete set null,
  weekday smallint not null check (weekday between 1 and 7), -- ISO: 1 = Пн
  begin_time time not null,
  duration_minutes integer not null default 60 check (duration_minutes > 0),
  valid_from date not null,
  valid_until date,
  notes text,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint schedule_series_target_check
    check (student_id is not null or group_id is not null),
  constraint schedule_series_period_check
    check (valid_until is null or valid_until >= valid_from)
);

create index if not exists schedule_series_student_idx
  on app.schedule_series (student_id) where deleted_at is null;
create index if not exists schedule_series_group_idx
  on app.schedule_series (group_id) where deleted_at is null;

-- Связь занятия с серией. series_date — какую дату серии закрывает строка:
-- перенос меняет scheduled_at, но series_date остаётся, поэтому генератор
-- не создаёт дубль на исходную дату; отменённое (deleted_at) занятие тоже
-- не восстанавливается. original_scheduled_at — «перенесено с …».
alter table app.lessons
  add column if not exists series_id uuid references app.schedule_series(id) on delete set null,
  add column if not exists series_date date,
  add column if not exists original_scheduled_at timestamptz;

create index if not exists lessons_series_idx
  on app.lessons (series_id, series_date) where series_id is not null;
