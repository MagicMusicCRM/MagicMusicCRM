drop index if exists app.user_crm_links_entity_active_idx;
drop index if exists app.user_crm_links_user_entity_active_idx;
drop table if exists app.user_crm_links;
drop index if exists app.users_app_accounts_role_created_idx;
alter table app.users drop column if exists phone_verified_at;
alter table app.users drop column if exists is_app_account;
