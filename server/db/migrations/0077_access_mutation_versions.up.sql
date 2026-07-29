insert into app.aggregate_versions (
  aggregate_type,
  aggregate_id,
  version
)
select
  'access:user',
  access_version.user_id::text,
  access_version.version
from app.user_access_versions access_version
on conflict (aggregate_type, aggregate_id) do nothing;

insert into app.aggregate_versions (
  aggregate_type,
  aggregate_id,
  version
)
select
  'access:role-package',
  package.role::text,
  package.package_version
from app.role_packages package
where package.active
on conflict (aggregate_type, aggregate_id) do nothing;

create or replace function app.initialize_user_access_version()
returns trigger
language plpgsql
as $$
begin
  insert into app.user_access_versions (user_id, version)
  values (new.id, 1)
  on conflict (user_id) do nothing;

  insert into app.aggregate_versions (
    aggregate_type,
    aggregate_id,
    version
  )
  values ('access:user', new.id::text, 1)
  on conflict (aggregate_type, aggregate_id) do nothing;

  return new;
end;
$$;

drop trigger if exists users_initialize_access_version on app.users;
create trigger users_initialize_access_version
after insert on app.users
for each row
execute function app.initialize_user_access_version();
