-- P5b (KVA-199) rollback.

alter table app.lesson_participation drop column if exists subscription_id;
alter table app.subscriptions drop column if exists payment_id;
alter table app.subscriptions drop column if exists package_id;
drop table if exists app.subscription_packages;
