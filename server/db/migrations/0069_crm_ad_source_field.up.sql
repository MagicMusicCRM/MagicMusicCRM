-- Preserve any legacy value before hiding the duplicate UI field. The
-- HolliHop importer writes students.adSource directly; these guarded copies
-- cover older/manual rows that only have source and never overwrite adSource.
update app.students
set custom_data = jsonb_set(
    coalesce(custom_data, '{}'::jsonb),
    '{adSource}',
    custom_data->'source',
    true
  ),
  updated_at = now()
where deleted_at is null
  and nullif(btrim(custom_data->>'source'), '') is not null
  and nullif(btrim(custom_data->>'adSource'), '') is null;

update app.leads
set custom_data = jsonb_set(
    coalesce(custom_data, '{}'::jsonb),
    '{adSource}',
    custom_data->'source',
    true
  ),
  updated_at = now()
where deleted_at is null
  and nullif(btrim(custom_data->>'source'), '') is not null
  and nullif(btrim(custom_data->>'adSource'), '') is null;

with current_setting as (
  select case
    when jsonb_typeof(value) = 'array' then value
    else '[]'::jsonb
  end as value
  from app.system_settings
  where key = 'crm_custom_fields'
),
normalized_current as (
  select coalesce(
    (select value from current_setting),
    '[]'::jsonb
  ) as value
),
cleaned as (
  select coalesce(
    jsonb_agg(field.item order by field.ord)
      filter (
        where not (
          field.item->>'entity' in ('students', 'leads')
          and field.item->>'key' = 'source'
        )
      ),
    '[]'::jsonb
  ) as value
  from normalized_current,
    jsonb_array_elements(normalized_current.value)
      with ordinality as field(item, ord)
),
source_options as (
  select coalesce(
    (
      select field.item->'options'
      from normalized_current,
        jsonb_array_elements(normalized_current.value) as field(item)
      where field.item->>'entity' = 'leads'
        and field.item->>'key' = 'adSource'
        and jsonb_typeof(field.item->'options') = 'array'
      limit 1
    ),
    (
      select field.item->'options'
      from normalized_current,
        jsonb_array_elements(normalized_current.value) as field(item)
      where field.item->>'entity' in ('students', 'leads')
        and field.item->>'key' = 'source'
        and jsonb_typeof(field.item->'options') = 'array'
      order by case when field.item->>'entity' = 'students' then 0 else 1 end
      limit 1
    ),
    '[]'::jsonb
  ) as value
),
patched as (
  select case
    when exists (
      select 1
      from cleaned,
        jsonb_array_elements(cleaned.value) as field(item)
      where field.item->>'entity' = 'students'
        and field.item->>'key' = 'adSource'
    ) then cleaned.value
    else cleaned.value || jsonb_build_array(
      jsonb_build_object(
        'entity', 'students',
        'key', 'adSource',
        'label', 'Рекламный источник',
        'type', 'select',
        'required', false,
        'options', source_options.value
      )
    )
  end as value
  from cleaned, source_options
)
update app.system_settings setting
set value = patched.value,
  updated_at = now()
from patched
where setting.key = 'crm_custom_fields';
