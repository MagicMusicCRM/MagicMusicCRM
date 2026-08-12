do $$
begin
  if exists (
    select 1
    from app.commerce_reporting_exclusions exclusion
    where exclusion.source_kind = 'account_adjustment'
  ) then
    raise exception using
      errcode = '23514',
      message = 'account adjustment reversal history exists; rollback is unsafe';
  end if;

  if exists (
    select 1
    from app.account_adjustment_aggregate_version_backfill backfill
    left join app.aggregate_versions aggregate
      on aggregate.aggregate_type = 'commerce:payment-adjustment'
     and aggregate.aggregate_id = backfill.adjustment_id::text
    where aggregate.aggregate_id is null
       or aggregate.version <> backfill.backfilled_version
  ) then
    raise exception using
      errcode = '23514',
      message = 'account adjustment aggregate advanced; rollback is unsafe';
  end if;
end $$;

update app.aggregate_versions aggregate
set version = backfill.previous_version,
    updated_at = now()
from app.account_adjustment_aggregate_version_backfill backfill
where aggregate.aggregate_type = 'commerce:payment-adjustment'
  and aggregate.aggregate_id = backfill.adjustment_id::text
  and backfill.previous_version is not null;

delete from app.aggregate_versions aggregate
using app.account_adjustment_aggregate_version_backfill backfill
where aggregate.aggregate_type = 'commerce:payment-adjustment'
  and aggregate.aggregate_id = backfill.adjustment_id::text
  and backfill.previous_version is null;

drop table app.account_adjustment_aggregate_version_backfill;
