do $$
begin
  if exists (select 1 from app.user_capability_overrides) then
    raise exception
      'Refusing destructive rollback: user capability overrides exist';
  end if;
  if exists (select 1 from app.user_access_versions where version > 1) then
    raise exception
      'Refusing destructive rollback: access versions have advanced';
  end if;
end $$;

drop table if exists app.user_access_versions;
drop table if exists app.user_capability_overrides;
drop table if exists app.role_package_capabilities;
drop table if exists app.role_packages;
drop table if exists app.capability_definitions;
