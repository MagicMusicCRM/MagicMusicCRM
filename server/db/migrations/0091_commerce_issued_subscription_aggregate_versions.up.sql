-- v4 T5.2.3: bring every immutable-snapshot issued subscription into the
-- shared Platform Integrity version registry before replace/cancel commands
-- start advancing the aggregate.

create table if not exists app.issued_subscription_aggregate_version_backfill (
  subscription_id uuid primary key
    references app.subscriptions(id) on delete restrict,
  previous_version bigint,
  backfilled_version bigint not null,
  recorded_at timestamptz not null default now(),
  constraint issued_subscription_backfill_previous_version_nonnegative
    check (previous_version is null or previous_version >= 0),
  constraint issued_subscription_backfill_version_positive
    check (backfilled_version > 0)
);

insert into app.issued_subscription_aggregate_version_backfill (
  subscription_id,
  previous_version,
  backfilled_version
)
select
  subscription.id,
  aggregate.version,
  greatest(subscription.version, coalesce(aggregate.version, 0))
from app.subscriptions subscription
left join app.aggregate_versions aggregate
  on aggregate.aggregate_type = 'commerce:issued-subscription'
  and aggregate.aggregate_id = subscription.id::text
where subscription.commercial_snapshot is not null
  and (
    aggregate.aggregate_id is null
    or aggregate.version < subscription.version
  )
on conflict (subscription_id) do nothing;

insert into app.aggregate_versions (
  aggregate_type,
  aggregate_id,
  version
)
select
  'commerce:issued-subscription',
  subscription.id::text,
  subscription.version
from app.subscriptions subscription
where subscription.commercial_snapshot is not null
on conflict (aggregate_type, aggregate_id)
do update set
  version = greatest(app.aggregate_versions.version, excluded.version),
  updated_at = now();
