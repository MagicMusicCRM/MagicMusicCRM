alter table app.lesson_participation
  drop column if exists attendance_kind,
  drop column if exists charge_share,
  drop column if exists charged_hours;
