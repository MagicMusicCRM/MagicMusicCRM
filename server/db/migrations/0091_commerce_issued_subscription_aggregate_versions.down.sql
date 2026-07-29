do $$
begin
  if exists (
    select 1
    from app.subscription_lifecycle_events event
    where event.event_type in ('replace', 'cancel')
  ) then
    raise exception using
      errcode = '23514',
      message = 'subscription lifecycle history exists; aggregate-version rollback is unsafe';
  end if;

  if exists (
    select 1
    from app.issued_subscription_aggregate_version_backfill backfill
    left join app.aggregate_versions aggregate
      on aggregate.aggregate_type = 'commerce:issued-subscription'
      and aggregate.aggregate_id = backfill.subscription_id::text
    where aggregate.aggregate_id is null
      or aggregate.version <> backfill.backfilled_version
  ) then
    raise exception using
      errcode = '23514',
      message = 'issued subscription aggregate advanced; aggregate-version rollback is unsafe';
  end if;
end $$;

update app.aggregate_versions aggregate
set version = backfill.previous_version,
  updated_at = now()
from app.issued_subscription_aggregate_version_backfill backfill
where aggregate.aggregate_type = 'commerce:issued-subscription'
  and aggregate.aggregate_id = backfill.subscription_id::text
  and backfill.previous_version is not null;

delete from app.aggregate_versions aggregate
using app.issued_subscription_aggregate_version_backfill backfill
where aggregate.aggregate_type = 'commerce:issued-subscription'
  and aggregate.aggregate_id = backfill.subscription_id::text
  and backfill.previous_version is null;

drop table app.issued_subscription_aggregate_version_backfill;
