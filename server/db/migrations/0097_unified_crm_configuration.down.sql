do $$
begin
  if exists (
    select 1 from app.crm_configuration_revisions
    where not (branch_id is null and version = 1 and created_by is null)
  ) or exists (select 1 from app.crm_configuration_drafts) then
    raise exception 'cannot remove unified CRM configuration while user data exists';
  end if;
end;
$$;

delete from app.role_package_capabilities
where capability_key in ('config.crm.read', 'config.crm.edit', 'config.crm.publish');
delete from app.capability_definitions
where capability_key in ('config.crm.read', 'config.crm.edit', 'config.crm.publish');

drop trigger if exists crm_configuration_revision_immutable on app.crm_configuration_revisions;
drop function if exists app.protect_crm_configuration_revision();
drop table if exists app.crm_configuration_drafts;
drop table if exists app.crm_configuration_revisions;

alter table app.client_custom_field_definitions
  drop constraint if exists client_custom_field_value_type_check;
alter table app.client_custom_field_definitions
  add constraint client_custom_field_value_type_check
  check (value_type in ('text', 'number', 'boolean', 'date', 'select', 'email', 'phone'));
alter table app.client_custom_field_definitions
  drop column if exists placements,
  drop column if exists width,
  drop column if exists sort_order,
  drop column if exists category_label,
  drop column if exists category_key;
