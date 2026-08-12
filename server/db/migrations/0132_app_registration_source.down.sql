drop trigger if exists lead_sources_truncate_guard on app.lead_sources;
drop trigger if exists lead_sources_system_guard on app.lead_sources;
drop function if exists app.guard_system_lead_source();

alter table app.lead_sources
  drop column if exists is_system;
