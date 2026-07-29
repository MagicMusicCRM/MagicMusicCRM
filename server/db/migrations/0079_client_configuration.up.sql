-- v4 T3.1.2: versioned lead sources and normalized typed custom fields.
-- Legacy system_settings/custom_data remain as a compatibility read surface;
-- all historical values are copied, including untyped values that cannot be
-- safely coerced.

alter table app.lead_sources
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists version bigint not null default 1;

alter table app.leads
  add column if not exists source_id uuid references app.lead_sources(id);

-- Known legacy source labels first resolve to the seeded catalog.
update app.leads lead
set source_id = (
  select source.id
  from app.lead_sources source
  where source.deleted_at is null
    and (
      lower(btrim(source.canonical_name)) = lower(btrim(lead.source))
      or lower(btrim(source.display_name)) = lower(btrim(lead.source))
    )
  order by
    (
      lower(btrim(source.canonical_name)) = lower(btrim(lead.source))
    ) desc,
    source.id asc
  limit 1
)
where lead.source_id is null
  and nullif(btrim(lead.source), '') is not null
  and exists (
    select 1
    from app.lead_sources source
    where source.deleted_at is null
      and (
        lower(btrim(source.canonical_name)) = lower(btrim(lead.source))
        or lower(btrim(source.display_name)) = lower(btrim(lead.source))
      )
  );

-- Preserve every unknown historical source as an archived-safe catalog row.
insert into app.lead_sources (
  canonical_name,
  display_name,
  is_active
)
select
  'legacy_' || md5(lower(btrim(legacy.source))),
  min(btrim(legacy.source)),
  false
from app.leads legacy
where legacy.source_id is null
  and nullif(btrim(legacy.source), '') is not null
group by lower(btrim(legacy.source))
on conflict do nothing;

update app.leads lead
set source_id = source.id
from app.lead_sources source
where lead.source_id is null
  and nullif(btrim(lead.source), '') is not null
  and source.canonical_name = 'legacy_' || md5(lower(btrim(lead.source)));

create index if not exists leads_source_id_idx
  on app.leads (source_id)
  where deleted_at is null;

create table if not exists app.client_custom_field_definitions (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  field_key text not null,
  label text not null,
  value_type text not null,
  is_required boolean not null default false,
  is_active boolean not null default true,
  is_system boolean not null default false,
  options jsonb not null default '[]'::jsonb,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint client_custom_field_entity_check
    check (entity_type in ('lead', 'student')),
  constraint client_custom_field_key_check
    check (field_key ~ '^[A-Za-z][A-Za-z0-9_]{0,63}$'),
  constraint client_custom_field_value_type_check
    check (value_type in ('text', 'number', 'boolean', 'date', 'select', 'email', 'phone')),
  constraint client_custom_field_options_check
    check (jsonb_typeof(options) = 'array'),
  constraint client_custom_field_definition_unique
    unique (entity_type, field_key)
);

create index if not exists client_custom_field_definitions_active_idx
  on app.client_custom_field_definitions (entity_type, is_active, label);

create table if not exists app.client_custom_field_values (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null
    references app.client_custom_field_definitions(id) on delete restrict,
  entity_type text not null,
  entity_id uuid not null,
  value_text text,
  value_number numeric,
  value_boolean boolean,
  value_date date,
  value_json jsonb,
  validation_state text not null default 'valid',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_custom_field_value_entity_check
    check (entity_type in ('lead', 'student')),
  constraint client_custom_field_value_state_check
    check (validation_state in ('valid', 'legacy_untyped')),
  constraint client_custom_field_value_single_typed_check
    check (
      num_nonnulls(
        value_text,
        value_number,
        value_boolean,
        value_date,
        value_json
      ) = 1
    ),
  constraint client_custom_field_value_unique
    unique (definition_id, entity_type, entity_id)
);

create index if not exists client_custom_field_values_entity_idx
  on app.client_custom_field_values (entity_type, entity_id);

-- Required core fields are visible in the same configuration projection but
-- remain system-owned and are never copied into the custom values table.
insert into app.client_custom_field_definitions (
  entity_type,
  field_key,
  label,
  value_type,
  is_required,
  is_active,
  is_system
)
values
  ('lead', 'firstName', 'Имя', 'text', true, true, true),
  ('lead', 'lastName', 'Фамилия', 'text', true, true, true),
  ('lead', 'phone', 'Телефон', 'phone', true, true, true),
  ('lead', 'sourceId', 'Источник', 'select', true, true, true),
  ('student', 'firstName', 'Имя', 'text', true, true, true),
  ('student', 'lastName', 'Фамилия', 'text', true, true, true),
  ('student', 'phone', 'Телефон', 'phone', true, true, true),
  ('student', 'branchId', 'Филиал', 'select', true, true, true),
  ('student', 'status', 'Статус клиента', 'select', true, true, true)
on conflict (entity_type, field_key) do nothing;

-- Normalize the accepted client field definitions from the compatibility
-- setting. Rejected/teacher fields were already filtered by migrations 0069
-- and 0073; only Lead/Student definitions belong to SYS-CRM.
with configured as (
  select
    case field.item->>'entity'
      when 'leads' then 'lead'
      when 'students' then 'student'
    end as entity_type,
    field.item->>'key' as field_key,
    coalesce(nullif(btrim(field.item->>'label'), ''), field.item->>'key') as label,
    case field.item->>'type'
      when 'number' then 'number'
      when 'boolean' then 'boolean'
      when 'date' then 'date'
      when 'select' then 'select'
      when 'email' then 'email'
      when 'phone' then 'phone'
      else 'text'
    end as value_type,
    coalesce((field.item->>'required')::boolean, false) as is_required,
    case
      when jsonb_typeof(field.item->'options') = 'array'
        then field.item->'options'
      else '[]'::jsonb
    end as options
  from app.system_settings setting,
    jsonb_array_elements(
      case
        when jsonb_typeof(setting.value) = 'array' then setting.value
        else '[]'::jsonb
      end
    ) as field(item)
  where setting.key = 'crm_custom_fields'
    and field.item->>'entity' in ('leads', 'students')
    and coalesce(field.item->>'key', '') ~ '^[A-Za-z][A-Za-z0-9_]{0,63}$'
)
insert into app.client_custom_field_definitions (
  entity_type,
  field_key,
  label,
  value_type,
  is_required,
  options
)
select
  entity_type,
  field_key,
  label,
  value_type,
  is_required,
  options
from configured
where entity_type is not null
on conflict (entity_type, field_key) do nothing;

-- Typed backfill. Invalid historical values are retained in value_json and
-- explicitly marked legacy_untyped; new writes may never create that state.
with raw_values as (
  select
    definition.id as definition_id,
    definition.entity_type,
    definition.value_type,
    source.entity_id,
    source.raw_value
  from app.client_custom_field_definitions definition
  join lateral (
    select lead.id as entity_id, lead.custom_data->definition.field_key as raw_value
    from app.leads lead
    where definition.entity_type = 'lead'
      and lead.custom_data ? definition.field_key
    union all
    select student.id as entity_id, student.custom_data->definition.field_key as raw_value
    from app.students student
    where definition.entity_type = 'student'
      and student.custom_data ? definition.field_key
  ) source on true
  where not definition.is_system
),
coerced as (
  select
    definition_id,
    entity_type,
    entity_id,
    case
      when value_type in ('text', 'select', 'email', 'phone')
        and jsonb_typeof(raw_value) = 'string'
        then raw_value #>> '{}'
    end as value_text,
    case
      when value_type = 'number'
        and (
          jsonb_typeof(raw_value) = 'number'
          or (
            jsonb_typeof(raw_value) = 'string'
            and (raw_value #>> '{}') ~ '^-?[0-9]+([.][0-9]+)?$'
          )
        )
        then (raw_value #>> '{}')::numeric
    end as value_number,
    case
      when value_type = 'boolean' and jsonb_typeof(raw_value) = 'boolean'
        then (raw_value #>> '{}')::boolean
      when value_type = 'boolean'
        and jsonb_typeof(raw_value) = 'string'
        and lower(raw_value #>> '{}') in ('true', 'false')
        then (raw_value #>> '{}')::boolean
    end as value_boolean,
    case
      when value_type = 'date'
        and jsonb_typeof(raw_value) = 'string'
        and (raw_value #>> '{}') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        and pg_input_is_valid(raw_value #>> '{}', 'date')
        then (raw_value #>> '{}')::date
    end as value_date,
    raw_value
  from raw_values
)
insert into app.client_custom_field_values (
  definition_id,
  entity_type,
  entity_id,
  value_text,
  value_number,
  value_boolean,
  value_date,
  value_json,
  validation_state
)
select
  definition_id,
  entity_type,
  entity_id,
  value_text,
  value_number,
  value_boolean,
  value_date,
  case
    when num_nonnulls(value_text, value_number, value_boolean, value_date) = 0
      then raw_value
  end,
  case
    when num_nonnulls(value_text, value_number, value_boolean, value_date) = 0
      then 'legacy_untyped'
    else 'valid'
  end
from coerced
where raw_value is not null
on conflict (definition_id, entity_type, entity_id) do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete
      on app.client_custom_field_definitions to magiccrm_app;
    grant select, insert, update, delete
      on app.client_custom_field_values to magiccrm_app;
  end if;
end $$;
