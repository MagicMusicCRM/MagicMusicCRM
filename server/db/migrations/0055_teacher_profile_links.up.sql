-- KVA-238: явные связи педагога со справочниками.
-- Дисциплины — мультивыбор (m2m к app.disciplines вместо одной текстовой
-- specialization). Запрет «урок с чужой дисциплиной» сознательно НЕ вводим.
create table if not exists app.teacher_disciplines (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.teachers(id) on delete cascade,
  discipline_id uuid not null references app.disciplines(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (teacher_id, discipline_id)
);

-- Явная привязка педагога к филиалам (может работать в двух филиалах).
-- Раньше филиалы выводились только косвенно из групп/занятий.
create table if not exists app.teacher_branches (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.teachers(id) on delete cascade,
  branch_id uuid not null references app.branches(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (teacher_id, branch_id)
);
