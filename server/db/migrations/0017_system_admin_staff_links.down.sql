drop index if exists app.user_crm_links_user_type_active_idx;

alter table app.user_crm_links
  drop constraint if exists user_crm_links_source_check;

alter table app.user_crm_links
  add constraint user_crm_links_source_check
  check (link_source in ('auto_phone', 'manual_phone'));

alter table app.user_crm_links
  drop constraint if exists user_crm_links_entity_type_check;

alter table app.user_crm_links
  add constraint user_crm_links_entity_type_check
  check (entity_type::text in ('student', 'lead'));

drop table if exists app.staff_branch_assignments;
drop table if exists app.staff_members;

-- PostgreSQL enum values are intentionally not removed here.
-- app.user_role keeps 'system_admin' and app.crm_entity_type keeps 'staff'.
