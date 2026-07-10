alter table app.lessons
  drop column if exists series_id,
  drop column if exists series_date,
  drop column if exists original_scheduled_at;

drop table if exists app.schedule_series;
