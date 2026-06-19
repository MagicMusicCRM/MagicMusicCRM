-- server/db/migrations/0025_phone_normalization.down.sql
drop table if exists app.phone_review_queue;
alter table app.leads drop column if exists phone_normalized;
alter table app.profiles drop column if exists phone_normalized;
