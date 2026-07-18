drop index if exists app.lessons_series_date_active_unique_idx;
drop index if exists app.schedule_series_superseded_by_idx;

alter table app.schedule_series
  drop column if exists superseded_by;
