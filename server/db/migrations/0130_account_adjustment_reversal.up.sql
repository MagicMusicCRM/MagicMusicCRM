-- UAT-06A: every mutable-looking personal-account correction is still an
-- immutable fact.  Backfill the shared aggregate version used by the signed
-- preview/commit reversal flow; the reversal itself is represented by an
-- equal-and-opposite fact plus a reporting exclusion for both facts.

create table if not exists app.account_adjustment_aggregate_version_backfill (
  adjustment_id uuid primary key
    references app.account_adjustments(id) on delete restrict,
  previous_version bigint,
  backfilled_version bigint not null,
  recorded_at timestamptz not null default now(),
  constraint account_adjustment_backfill_previous_version_nonnegative
    check (previous_version is null or previous_version >= 0),
  constraint account_adjustment_backfill_version_positive
    check (backfilled_version > 0)
);

insert into app.account_adjustment_aggregate_version_backfill (
  adjustment_id,
  previous_version,
  backfilled_version
)
select
  adjustment.id,
  aggregate.version,
  greatest(1, coalesce(aggregate.version, 0))
from app.account_adjustments adjustment
left join app.aggregate_versions aggregate
  on aggregate.aggregate_type = 'commerce:payment-adjustment'
 and aggregate.aggregate_id = adjustment.id::text
where adjustment.source_payment_id is not null
  and (aggregate.aggregate_id is null or aggregate.version < 1)
on conflict (adjustment_id) do nothing;

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'commerce:payment-adjustment', adjustment.id::text, 1
from app.account_adjustments adjustment
where adjustment.source_payment_id is not null
on conflict (aggregate_type, aggregate_id)
do update set
  version = greatest(app.aggregate_versions.version, excluded.version),
  updated_at = now();
