drop trigger if exists users_initialize_access_version on app.users;
drop function if exists app.initialize_user_access_version();

delete from app.aggregate_versions
where aggregate_type in ('access:user', 'access:role-package');
