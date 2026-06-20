alter table app.chats    drop column if exists student_id;
alter table app.chats    drop column if exists lead_id;
alter table app.chats    drop column if exists branch_id;
alter table app.tasks    drop column if exists branch_id;
alter table app.expenses drop column if exists branch_id;
alter table app.payments drop column if exists branch_id;
alter table app.students drop column if exists branch_id;
alter table app.leads    drop column if exists branch_id;
