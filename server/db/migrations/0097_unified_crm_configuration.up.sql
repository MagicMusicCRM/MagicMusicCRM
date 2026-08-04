alter table app.client_custom_field_definitions
  add column if not exists category_key text not null default 'general',
  add column if not exists category_label text not null default 'Основная информация',
  add column if not exists sort_order integer not null default 0,
  add column if not exists width text not null default 'full',
  add column if not exists placements jsonb not null default '["create","edit","card"]'::jsonb;

alter table app.client_custom_field_definitions
  drop constraint if exists client_custom_field_value_type_check;
alter table app.client_custom_field_definitions
  add constraint client_custom_field_value_type_check check (
    value_type in (
      'text', 'textarea', 'number', 'money', 'duration', 'boolean', 'toggle',
      'date', 'datetime', 'select', 'radio', 'multi_select',
      'checkbox_group', 'email', 'phone', 'url'
    )
  );

create table if not exists app.crm_configuration_revisions (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid references app.branches(id),
  version bigint not null check (version > 0),
  patch jsonb not null check (jsonb_typeof(patch) = 'object'),
  effective_snapshot jsonb not null check (jsonb_typeof(effective_snapshot) = 'object'),
  impact jsonb not null default '{}'::jsonb check (jsonb_typeof(impact) = 'object'),
  reason text not null check (nullif(btrim(reason), '') is not null),
  rollback_from_version bigint,
  created_by uuid references app.users(id),
  created_at timestamptz not null default now()
);

create unique index if not exists crm_configuration_school_version_unique
  on app.crm_configuration_revisions(version) where branch_id is null;
create unique index if not exists crm_configuration_branch_version_unique
  on app.crm_configuration_revisions(branch_id, version) where branch_id is not null;
create index if not exists crm_configuration_branch_latest_idx
  on app.crm_configuration_revisions(branch_id, version desc);

create table if not exists app.crm_configuration_drafts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references app.users(id) on delete cascade,
  branch_id uuid references app.branches(id),
  base_version bigint not null check (base_version >= 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  updated_at timestamptz not null default now()
);
create unique index if not exists crm_configuration_school_draft_unique
  on app.crm_configuration_drafts(user_id) where branch_id is null;
create unique index if not exists crm_configuration_branch_draft_unique
  on app.crm_configuration_drafts(user_id, branch_id) where branch_id is not null;

insert into app.crm_configuration_revisions (
  branch_id, version, patch, effective_snapshot, impact, reason
)
select null, 1, snapshot, snapshot, '{"seed":true}'::jsonb,
  'Импорт действующей конфигурации клиентов'
from (
  select jsonb_build_object(
    'categories', jsonb_build_array(
      jsonb_build_object('key', 'general', 'label', 'Основная информация', 'order', 0, 'active', true)
    ),
    'fields', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', definition.id,
        'entityType', definition.entity_type,
        'key', definition.field_key,
        'label', definition.label,
        'valueType', definition.value_type,
        'required', definition.is_required,
        'active', definition.is_active and definition.deleted_at is null,
        'system', definition.is_system,
        'categoryKey', definition.category_key,
        'order', definition.sort_order,
        'width', definition.width,
        'placements', definition.placements,
        'options', coalesce(definition.options, '[]'::jsonb)
      ) order by definition.entity_type, definition.sort_order, definition.label)
      from app.client_custom_field_definitions definition
    ), '[]'::jsonb),
    'optionSets', '[]'::jsonb,
    'businessSettings', jsonb_build_array(
      jsonb_build_object(
        'key', 'default_lesson_duration_minutes', 'label', 'Длительность занятия по умолчанию',
        'valueType', 'integer', 'unit', 'мин', 'min', 15, 'max', 240, 'value', 60,
        'branchOverridable', true
      ),
      jsonb_build_object(
        'key', 'payment_reminder_days', 'label', 'Напомнить об оплате заранее',
        'valueType', 'integer', 'unit', 'дн.', 'min', 0, 'max', 60, 'value', 3,
        'branchOverridable', true
      )
    )
  ) as snapshot
) seed
where not exists (select 1 from app.crm_configuration_revisions);

create or replace function app.protect_crm_configuration_revision()
returns trigger language plpgsql as $$
begin
  raise exception using errcode = '23514', message = 'crm configuration revisions are immutable';
end;
$$;
drop trigger if exists crm_configuration_revision_immutable on app.crm_configuration_revisions;
create trigger crm_configuration_revision_immutable
before update or delete on app.crm_configuration_revisions
for each row execute function app.protect_crm_configuration_revision();

insert into app.capability_definitions (
  capability_key, version, description, domain, risk_level, override_mode
)
values
  ('config.crm.read', 1, 'Read effective CRM configuration', 'config', 'medium', 'allow_deny'),
  ('config.crm.edit', 1, 'Edit CRM configuration drafts', 'config', 'high', 'allow_deny'),
  ('config.crm.publish', 1, 'Publish and rollback CRM configuration', 'config', 'critical', 'allow_deny')
on conflict (capability_key, version) do nothing;

insert into app.role_package_capabilities (
  package_id, capability_key, capability_version, effect
)
select package.id, definition.capability_key, 1,
  case when package.role in ('director', 'system_admin') then 'allow' else 'deny' end
from app.role_packages package
cross join (values ('config.crm.read'), ('config.crm.edit'), ('config.crm.publish')) definition(capability_key)
where package.active
on conflict (package_id, capability_key) do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.crm_configuration_revisions to magiccrm_app;
    grant select, insert, update, delete on app.crm_configuration_drafts to magiccrm_app;
  end if;
end $$;
