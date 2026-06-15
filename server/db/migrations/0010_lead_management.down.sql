drop index if exists app.lessons_lead_scheduled_idx;

alter table app.lessons
  drop constraint if exists lessons_student_or_group_or_lead_check;

alter table app.lessons
  add constraint lessons_student_or_group_check
  check (student_id is not null or group_id is not null);

alter table app.lessons
  drop column if exists lead_id;

alter table app.leads
  drop column if exists custom_data;

alter table app.lead_statuses
  drop column if exists color;
