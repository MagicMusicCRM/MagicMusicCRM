-- P5c (KVA-200): lesson homeworks + attachments.

-- Allow homework file attachments to reuse the shared file_objects table.
alter type app.file_purpose add value if not exists 'homework_attachment';

create table if not exists app.lesson_homeworks (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid references app.lessons(id),
  student_id uuid not null references app.students(id),
  assigned_by uuid references app.users(id),
  title text not null,
  description text,
  status text not null default 'assigned',
  due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists lesson_homeworks_student_idx
  on app.lesson_homeworks (student_id)
  where deleted_at is null;

create index if not exists lesson_homeworks_lesson_idx
  on app.lesson_homeworks (lesson_id)
  where deleted_at is null;

create table if not exists app.homework_attachments (
  id uuid primary key default gen_random_uuid(),
  homework_id uuid not null references app.lesson_homeworks(id) on delete cascade,
  file_id uuid not null references app.file_objects(id),
  uploaded_by uuid references app.users(id),
  kind text not null default 'assignment',
  created_at timestamptz not null default now()
);

create index if not exists homework_attachments_homework_idx
  on app.homework_attachments (homework_id);
