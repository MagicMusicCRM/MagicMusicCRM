-- One acquisition-source field for both leads and students.

alter table app.students
  add column if not exists source_id uuid references app.lead_sources(id);

-- Converted students inherit the exact source row of their lead.
update app.students student
set source_id = lead.source_id
from app.leads lead
where student.source_id is null
  and student.lead_id = lead.id
  and lead.source_id is not null;

-- Preserve every unmatched legacy adSource label in the canonical catalog.
insert into app.lead_sources (canonical_name, display_name, is_active)
select
  'legacy_' || md5(lower(btrim(value.label))),
  min(btrim(value.label)),
  false
from (
  select custom_data->>'adSource' as label from app.leads
  union all
  select custom_data->>'adSource' as label from app.students
) value
where nullif(btrim(value.label), '') is not null
  and not exists (
    select 1 from app.lead_sources source
    where lower(btrim(source.canonical_name)) = lower(btrim(value.label))
       or lower(btrim(source.display_name)) = lower(btrim(value.label))
  )
group by lower(btrim(value.label))
on conflict do nothing;

update app.leads lead
set source_id = source.id,
    source = source.display_name
from app.lead_sources source
where lead.source_id is null
  and nullif(btrim(lead.custom_data->>'adSource'), '') is not null
  and (
    lower(btrim(source.canonical_name)) = lower(btrim(lead.custom_data->>'adSource'))
    or lower(btrim(source.display_name)) = lower(btrim(lead.custom_data->>'adSource'))
    or source.canonical_name = 'legacy_' || md5(lower(btrim(lead.custom_data->>'adSource')))
  );

update app.students student
set source_id = source.id
from app.lead_sources source
where student.source_id is null
  and nullif(btrim(student.custom_data->>'adSource'), '') is not null
  and (
    lower(btrim(source.canonical_name)) = lower(btrim(student.custom_data->>'adSource'))
    or lower(btrim(source.display_name)) = lower(btrim(student.custom_data->>'adSource'))
    or source.canonical_name = 'legacy_' || md5(lower(btrim(student.custom_data->>'adSource')))
  );

create index if not exists students_source_id_idx
  on app.students (source_id)
  where deleted_at is null;

insert into app.client_custom_field_definitions (
  entity_type, field_key, label, value_type,
  is_required, is_active, is_system
)
values ('student', 'sourceId', 'Рекламный источник', 'select', true, true, true)
on conflict (entity_type, field_key) do update
set label = excluded.label,
    value_type = excluded.value_type,
    is_required = true,
    is_active = true,
    is_system = true,
    deleted_at = null,
    updated_at = now();

update app.client_custom_field_definitions
set label = 'Рекламный источник', updated_at = now()
where entity_type = 'lead' and field_key = 'sourceId';

update app.client_custom_field_definitions
set is_active = false, deleted_at = coalesce(deleted_at, now()), updated_at = now()
where field_key = 'adSource' and entity_type in ('lead', 'student');

update app.system_settings setting
set value = coalesce((
      select jsonb_agg(field.item order by field.ord)
      from jsonb_array_elements(setting.value) with ordinality as field(item, ord)
      where not (
        field.item->>'entity' in ('leads', 'students')
        and field.item->>'key' in ('adSource', 'source')
      )
    ), '[]'::jsonb),
    updated_at = now()
where setting.key = 'crm_custom_fields'
  and jsonb_typeof(setting.value) = 'array';
