-- One logical field definition for the Client lifecycle. Lead/Student are
-- visibility targets, not separate field identities.

alter table app.client_custom_field_definitions
  add column if not exists visible_on_lead boolean not null default false,
  add column if not exists visible_on_student boolean not null default false;

update app.client_custom_field_definitions
set visible_on_lead = entity_type = 'lead',
    visible_on_student = entity_type = 'student';

do $$
begin
  if exists (
    select 1
    from app.client_custom_field_definitions
    group by field_key
    having count(distinct value_type) > 1
  ) then
    raise exception using
      errcode = '23514',
      message = 'canonical client field migration found incompatible value types';
  end if;
end $$;

create temporary table canonical_client_field_survivors on commit drop as
select distinct on (field_key)
  field_key,
  id as survivor_id
from app.client_custom_field_definitions
order by field_key,
  is_system desc,
  (is_active and deleted_at is null) desc,
  updated_at desc,
  id;

-- A corrupt database could already contain two values for the same logical
-- field/entity. Refuse to guess which value should win.
do $$
begin
  if exists (
    select 1
    from app.client_custom_field_values value
    join app.client_custom_field_definitions definition
      on definition.id = value.definition_id
    join canonical_client_field_survivors survivor
      on survivor.field_key = definition.field_key
    group by survivor.survivor_id, value.entity_type, value.entity_id
    having count(*) > 1
  ) then
    raise exception using
      errcode = '23514',
      message = 'canonical client field migration found duplicate client values';
  end if;
end $$;

update app.client_custom_field_values value
set definition_id = survivor.survivor_id,
    updated_at = now()
from app.client_custom_field_definitions definition
join canonical_client_field_survivors survivor
  on survivor.field_key = definition.field_key
where value.definition_id = definition.id
  and value.definition_id <> survivor.survivor_id;

with ranked_definitions as (
  select
    definition.*,
    row_number() over (
      partition by definition.field_key
      order by
        (definition.id = survivor.survivor_id) desc,
        definition.is_system desc,
        (definition.is_active and definition.deleted_at is null) desc,
        definition.updated_at desc,
        definition.id
    ) as merge_rank
  from app.client_custom_field_definitions definition
  join canonical_client_field_survivors survivor
    on survivor.field_key = definition.field_key
), merged as (
  select
    survivor.survivor_id,
    bool_or(definition.visible_on_lead and definition.is_active
      and definition.deleted_at is null) as visible_on_lead,
    bool_or(definition.visible_on_student and definition.is_active
      and definition.deleted_at is null) as visible_on_student,
    bool_or(definition.is_required) as is_required,
    bool_or(definition.is_active and definition.deleted_at is null) as is_active,
    bool_or(definition.is_system) as is_system,
    coalesce((
      select jsonb_agg(
        option_label order by merge_rank, option_order, option_label
      )
      from (
        select distinct on (option_label)
          option_label,
          merge_rank,
          option_order
        from (
          select
            option.value #>> '{}' as option_label,
            option_definition.merge_rank,
            option.ordinality as option_order
          from ranked_definitions option_definition
          cross join lateral jsonb_array_elements(option_definition.options)
            with ordinality option(value, ordinality)
          where option_definition.field_key = survivor.field_key
            and jsonb_typeof(option.value) = 'string'
        ) candidates
        order by option_label, merge_rank, option_order
      ) labels
      where nullif(btrim(option_label), '') is not null
    ), '[]'::jsonb) as options
  from canonical_client_field_survivors survivor
  join app.client_custom_field_definitions definition
    on definition.field_key = survivor.field_key
  group by survivor.survivor_id, survivor.field_key
)
update app.client_custom_field_definitions definition
set visible_on_lead = merged.visible_on_lead,
    visible_on_student = merged.visible_on_student,
    is_required = merged.is_required,
    is_active = merged.is_active,
    is_system = merged.is_system,
    options = merged.options,
    deleted_at = case when merged.is_active then null
      else coalesce(definition.deleted_at, now()) end,
    version = definition.version + 1,
    updated_at = now()
from merged
where definition.id = merged.survivor_id;

delete from app.client_custom_field_definitions definition
using canonical_client_field_survivors survivor
where definition.field_key = survivor.field_key
  and definition.id <> survivor.survivor_id;

alter table app.client_custom_field_definitions
  drop constraint if exists client_custom_field_definition_unique,
  drop constraint if exists client_custom_field_entity_check,
  drop column if exists entity_type;

alter table app.client_custom_field_definitions
  add constraint client_custom_field_definition_key_unique unique (field_key),
  add constraint client_custom_field_visibility_check check (
    visible_on_lead or visible_on_student or not is_active
  );

drop index if exists app.client_custom_field_definitions_active_idx;
create index client_custom_field_definitions_active_idx
  on app.client_custom_field_definitions (
    visible_on_lead, visible_on_student, is_active, sort_order, label
  );
