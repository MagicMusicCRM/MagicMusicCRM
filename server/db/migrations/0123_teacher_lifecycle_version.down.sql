alter table app.teachers
  drop constraint if exists teachers_version_positive,
  drop column if exists version;
