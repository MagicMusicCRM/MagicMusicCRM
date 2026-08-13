drop trigger if exists students_refresh_canonical_client on app.students;
drop trigger if exists leads_refresh_canonical_client on app.leads;
drop trigger if exists students_ensure_canonical_client on app.students;
drop trigger if exists leads_ensure_canonical_client on app.leads;
drop trigger if exists client_custom_values_ensure_client
  on app.client_custom_field_values;
drop trigger if exists profiles_refresh_canonical_client on app.profiles;
drop trigger if exists users_refresh_canonical_client on app.users;

drop function if exists app.refresh_canonical_client_from_profile_trigger();
drop function if exists app.refresh_canonical_client_from_user_trigger();
drop function if exists app.refresh_canonical_client_identity_trigger();
drop function if exists app.ensure_client_custom_value_identity();
drop function if exists app.refresh_canonical_client_identity(uuid);
drop function if exists app.ensure_canonical_client_identity();
drop function if exists app.resolve_client_id(text, uuid);

alter table app.client_custom_field_values
  drop constraint if exists client_custom_field_value_client_unique,
  drop constraint if exists client_custom_field_values_client_fk,
  drop column if exists client_id;

alter table app.students
  drop constraint if exists students_client_id_fk,
  drop constraint if exists students_client_id_unique,
  drop column if exists client_id;

alter table app.leads
  drop constraint if exists leads_client_id_fk,
  drop constraint if exists leads_client_id_unique,
  drop column if exists client_id;

drop table if exists app.clients;
