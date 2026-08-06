-- Preserve canonical student values in the legacy compatibility key.
update app.students student
set custom_data = jsonb_set(
      coalesce(student.custom_data, '{}'::jsonb),
      '{adSource}',
      to_jsonb(source.display_name),
      true
    ),
    updated_at = now()
from app.lead_sources source
where source.id = student.source_id;

update app.leads lead
set custom_data = jsonb_set(
      coalesce(lead.custom_data, '{}'::jsonb),
      '{adSource}',
      to_jsonb(source.display_name),
      true
    ),
    updated_at = now()
from app.lead_sources source
where source.id = lead.source_id;

update app.client_custom_field_definitions
set is_active = true, deleted_at = null, updated_at = now()
where field_key = 'adSource' and entity_type in ('lead', 'student');

delete from app.client_custom_field_definitions
where entity_type = 'student' and field_key = 'sourceId' and is_system;

update app.client_custom_field_definitions
set label = 'Источник', updated_at = now()
where entity_type = 'lead' and field_key = 'sourceId';

drop index if exists app.students_source_id_idx;
alter table app.students drop column if exists source_id;
