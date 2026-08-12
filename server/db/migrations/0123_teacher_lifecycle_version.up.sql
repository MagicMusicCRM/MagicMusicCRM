alter table app.teachers
  add column if not exists version bigint not null default 1;

alter table app.teachers
  drop constraint if exists teachers_version_positive;
alter table app.teachers
  add constraint teachers_version_positive check (version > 0);
