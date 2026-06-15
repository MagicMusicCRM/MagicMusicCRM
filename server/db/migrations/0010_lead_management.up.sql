alter table app.lead_statuses
  add column if not exists color text;

alter table app.leads
  add column if not exists custom_data jsonb not null default '{}'::jsonb;

alter table app.lessons
  add column if not exists lead_id uuid references app.leads(id) on delete set null;

alter table app.lessons
  drop constraint if exists lessons_student_or_group_check;

alter table app.lessons
  add constraint lessons_student_or_group_or_lead_check
  check (student_id is not null or group_id is not null or lead_id is not null);

create index if not exists lessons_lead_scheduled_idx
  on app.lessons (lead_id, scheduled_at)
  where deleted_at is null and lead_id is not null;
