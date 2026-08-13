alter table app.client_custom_field_definitions
  drop constraint if exists client_custom_field_visibility_check,
  drop constraint if exists client_custom_field_definition_key_unique;

alter table app.client_custom_field_definitions
  add column entity_type text;

-- Keep the existing UUID for Lead when a field is shared; create a Student
-- projection and move Student values to it. Student-only fields keep their UUID.
update app.client_custom_field_definitions
set entity_type = case
  when visible_on_lead then 'lead'
  else 'student'
end;

create temporary table restored_student_field_ids (
  source_id uuid primary key,
  student_id uuid not null
) on commit drop;

with inserted as (
  insert into app.client_custom_field_definitions (
    id, entity_type, field_key, label, value_type, is_required, is_active,
    is_system, options, version, created_at, updated_at, deleted_at,
    category_key, category_label, sort_order, width, placements,
    visible_on_lead, visible_on_student
  )
  select
    gen_random_uuid(), 'student', field_key, label, value_type, is_required,
    is_active, is_system, options, version, created_at, updated_at, deleted_at,
    category_key, category_label, sort_order, width, placements, false, true
  from app.client_custom_field_definitions
  where visible_on_lead and visible_on_student
  returning id, field_key
)
insert into restored_student_field_ids (source_id, student_id)
select source.id, inserted.id
from app.client_custom_field_definitions source
join inserted using (field_key)
where source.visible_on_lead and source.visible_on_student
  and source.entity_type = 'lead';

update app.client_custom_field_values value
set definition_id = restored.student_id,
    updated_at = now()
from restored_student_field_ids restored
where value.definition_id = restored.source_id
  and value.entity_type = 'student';

alter table app.client_custom_field_definitions
  alter column entity_type set not null,
  add constraint client_custom_field_entity_check
    check (entity_type in ('lead', 'student')),
  add constraint client_custom_field_definition_unique
    unique (entity_type, field_key);

drop index if exists app.client_custom_field_definitions_active_idx;
create index client_custom_field_definitions_active_idx
  on app.client_custom_field_definitions (entity_type, is_active, label);

alter table app.client_custom_field_definitions
  drop column visible_on_lead,
  drop column visible_on_student;
