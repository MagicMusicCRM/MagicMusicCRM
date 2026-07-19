-- Owner decision 2026-07-19: these legacy student fields must not be offered
-- by the CRM card. Only the configurable schema is changed. Existing values in
-- students.custom_data remain intact for historical imports and calculations.
update app.system_settings
set value = (
      select coalesce(jsonb_agg(field order by ordinal), '[]'::jsonb)
      from jsonb_array_elements(value) with ordinality as fields(field, ordinal)
      where field->>'key' not in ('workplace', 'position', 'individualPrice')
    ),
    updated_at = now()
where key = 'crm_custom_fields'
  and jsonb_typeof(value) = 'array';
