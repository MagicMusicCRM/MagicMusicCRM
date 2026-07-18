-- Serialize recurring-series lifecycle and make materialization idempotent
-- under concurrent workers. `superseded_by` also prevents a queued/retried
-- PATCH from creating a second continuation from an already-split series.

alter table app.schedule_series
  add column if not exists superseded_by uuid
    references app.schedule_series(id) on delete set null;

create index if not exists schedule_series_superseded_by_idx
  on app.schedule_series (superseded_by)
  where superseded_by is not null;

-- Prevent an old API/materializer process from inserting between the
-- duplicate preflight and unique-index build. SHARE conflicts with lesson
-- INSERT/UPDATE/DELETE but still permits reads for the short migration window.
lock table app.lessons in share mode;

-- Only live rows compete. A soft-deleted occurrence intentionally continues
-- to block regeneration through the service's broader NOT EXISTS check, while
-- this unique index closes the concurrent INSERT race for active rows.
-- Never guess which duplicate owns the authoritative payments/homework/history.
-- Production is preflighted before deploy; any unexpected environment aborts
-- here with a diagnostic and requires an explicit data merge.
do $$
begin
  if exists (
    select 1
    from app.lessons
    where deleted_at is null
      and series_id is not null
      and series_date is not null
    group by series_id, series_date
    having count(*) > 1
  ) then
    raise exception
      'Cannot enforce lessons_series_date_active_unique_idx: duplicate active occurrences exist';
  end if;
end
$$;

create unique index if not exists lessons_series_date_active_unique_idx
  on app.lessons (series_id, series_date)
  where deleted_at is null;
