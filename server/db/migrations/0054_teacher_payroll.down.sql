alter table app.teachers drop column if exists salary;
alter table app.groups drop column if exists teacher_rate;
drop table if exists app.teacher_payouts;
drop table if exists app.teacher_rates;
