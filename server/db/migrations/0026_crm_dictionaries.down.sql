-- server/db/migrations/0026_crm_dictionaries.down.sql
drop table if exists app.student_disciplines;
drop table if exists app.branch_disciplines;
drop table if exists app.disciplines;
drop table if exists app.lead_sources;
drop table if exists app.lead_loss_reasons;
alter table app.lead_statuses drop column if exists requires_reason;
alter table app.lead_statuses drop column if exists is_terminal;
