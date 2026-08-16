do $$
begin
  if exists (
    select 1
    from app.issued_subscription_aggregate_version_repair repair
    left join app.aggregate_versions aggregate
      on aggregate.aggregate_type = 'commerce:issued-subscription'
      and aggregate.aggregate_id = repair.subscription_id::text
    where aggregate.aggregate_id is null
      or aggregate.version <> repair.repaired_version
  ) then
    raise exception using
      errcode = '23514',
      message = 'repaired subscription aggregate advanced; rollback is unsafe';
  end if;
end $$;

update app.aggregate_versions aggregate
set version = repair.previous_version,
  updated_at = now()
from app.issued_subscription_aggregate_version_repair repair
where aggregate.aggregate_type = 'commerce:issued-subscription'
  and aggregate.aggregate_id = repair.subscription_id::text
  and repair.previous_version is not null;

delete from app.aggregate_versions aggregate
using app.issued_subscription_aggregate_version_repair repair
where aggregate.aggregate_type = 'commerce:issued-subscription'
  and aggregate.aggregate_id = repair.subscription_id::text
  and repair.previous_version is null;

drop table app.issued_subscription_aggregate_version_repair;
