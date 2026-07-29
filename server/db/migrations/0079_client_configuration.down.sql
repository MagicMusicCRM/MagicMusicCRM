drop index if exists app.client_custom_field_values_entity_idx;
drop table if exists app.client_custom_field_values;
drop index if exists app.client_custom_field_definitions_active_idx;
drop table if exists app.client_custom_field_definitions;

drop index if exists app.leads_source_id_idx;
alter table app.leads drop column if exists source_id;

alter table app.lead_sources
  drop column if exists version,
  drop column if exists updated_at;
