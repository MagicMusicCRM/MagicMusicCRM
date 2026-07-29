do $$
begin
  if exists (
    select 1
    from app.subscription_package_versions history
    join app.subscription_packages package
      on package.id = history.package_id
    where history.version <> package.version
  )
    or exists (
      select 1
      from app.idempotency_records record
      join app.subscription_packages package
        on package.id::text = record.result_ref ->> 'packageId'
      where record.operation like 'crm.subscription-package.%'
        and record.status = 'completed'
        and (record.result_ref ->> 'packageVersion')::bigint
          <> package.version
    ) then
    raise exception using
      errcode = '23514',
      message = 'catalog version history exists; rollback would break idempotent replay';
  end if;
end $$;

drop trigger if exists subscription_package_versions_immutable
  on app.subscription_package_versions;
drop table if exists app.subscription_package_versions;
drop function if exists app.reject_subscription_package_version_mutation();

delete from app.aggregate_versions
where aggregate_type = 'commerce:subscription-package';
