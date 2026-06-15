do $$
begin
  if not exists (select 1 from pg_type where typname = 'crm_entity_type') then
    create type app.crm_entity_type as enum ('student', 'teacher', 'group', 'lesson', 'lead', 'profile');
  end if;
end $$;

create table if not exists app.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references app.users(id) on delete cascade,
  first_name text,
  last_name text,
  phone text,
  dob date,
  avatar_file_id uuid,
  email_otp_2fa_enabled boolean not null default false,
  custom_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

insert into app.profiles (user_id, first_name, last_name, phone)
select
  u.id,
  nullif(split_part(coalesce(u.full_name, ''), ' ', 1), ''),
  nullif(trim(substr(coalesce(u.full_name, ''), length(split_part(coalesce(u.full_name, ''), ' ', 1)) + 1)), ''),
  u.phone
from app.users u
where u.deleted_at is null
  and not exists (select 1 from app.profiles p where p.user_id = u.id);

create index if not exists profiles_user_active_idx
  on app.profiles (user_id)
  where deleted_at is null;

create table if not exists app.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.rooms (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid references app.branches(id) on delete set null,
  name text not null,
  capacity integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.lead_statuses (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists app.leads (
  id uuid primary key default gen_random_uuid(),
  status_id uuid references app.lead_statuses(id) on delete set null,
  first_name text,
  last_name text,
  phone text,
  email text,
  source text,
  notes text,
  assigned_to uuid references app.users(id) on delete set null,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.students (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references app.profiles(id) on delete set null,
  lead_id uuid references app.leads(id) on delete set null,
  status text not null default 'active',
  custom_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.teachers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references app.profiles(id) on delete set null,
  status text not null default 'active',
  specialization text,
  custom_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.groups (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid references app.teachers(id) on delete set null,
  branch_id uuid references app.branches(id) on delete set null,
  room_id uuid references app.rooms(id) on delete set null,
  name text not null,
  price_per_lesson numeric(12,2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.group_students (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references app.groups(id) on delete cascade,
  student_id uuid not null references app.students(id) on delete cascade,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  unique (group_id, student_id)
);

create table if not exists app.lessons (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references app.students(id) on delete set null,
  group_id uuid references app.groups(id) on delete set null,
  teacher_id uuid references app.teachers(id) on delete set null,
  branch_id uuid references app.branches(id) on delete set null,
  room_id uuid references app.rooms(id) on delete set null,
  scheduled_at timestamptz not null,
  duration_minutes integer not null default 60,
  status text not null default 'scheduled',
  is_trial boolean not null default false,
  notes text,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint lessons_student_or_group_check check (student_id is not null or group_id is not null)
);

create table if not exists app.lesson_participation (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references app.lessons(id) on delete cascade,
  student_id uuid not null references app.students(id) on delete cascade,
  status text not null default 'scheduled',
  unique (lesson_id, student_id)
);

create table if not exists app.tasks (
  id uuid primary key default gen_random_uuid(),
  entity_type app.crm_entity_type not null,
  entity_id uuid not null,
  title text not null,
  description text,
  status text not null default 'open',
  due_at timestamptz,
  assigned_to uuid references app.users(id) on delete set null,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  amount numeric(12,2) not null,
  currency text not null default 'RUB',
  payment_date timestamptz not null default now(),
  method text,
  external_id text,
  notes text,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.expected_payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  amount numeric(12,2) not null,
  due_date date,
  status text not null default 'pending',
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists app.subscriptions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  lessons_total integer not null default 0,
  lessons_used integer not null default 0,
  starts_at date,
  expires_at date,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists app.student_balances (
  student_id uuid primary key references app.students(id) on delete cascade,
  balance numeric(12,2) not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists app.entity_comments (
  id uuid primary key default gen_random_uuid(),
  entity_type app.crm_entity_type not null,
  entity_id uuid not null,
  author_id uuid references app.users(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.profile_notes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references app.profiles(id) on delete cascade,
  author_id uuid references app.users(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists app.lead_comments (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references app.leads(id) on delete cascade,
  author_id uuid references app.users(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists students_profile_idx on app.students (profile_id);
create index if not exists teachers_profile_idx on app.teachers (profile_id);
create index if not exists group_students_student_idx on app.group_students (student_id) where left_at is null;
create index if not exists lessons_scheduled_idx on app.lessons (scheduled_at) where deleted_at is null;
create index if not exists lessons_student_scheduled_idx on app.lessons (student_id, scheduled_at) where deleted_at is null;
create index if not exists lessons_teacher_scheduled_idx on app.lessons (teacher_id, scheduled_at) where deleted_at is null;
create index if not exists payments_student_date_idx on app.payments (student_id, payment_date desc) where deleted_at is null;
create index if not exists tasks_assignee_status_due_idx on app.tasks (assigned_to, status, due_at) where deleted_at is null;
create index if not exists leads_created_idx on app.leads (created_at desc) where deleted_at is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant usage on schema app to magiccrm_app;
    grant usage on type app.user_role to magiccrm_app;
    grant usage on type app.crm_entity_type to magiccrm_app;
    grant select, insert, update, delete on all tables in schema app to magiccrm_app;
    grant usage on all sequences in schema app to magiccrm_app;
    alter default privileges in schema app
      grant select, insert, update, delete on tables to magiccrm_app;
    alter default privileges in schema app
      grant usage on sequences to magiccrm_app;
  end if;
end $$;
