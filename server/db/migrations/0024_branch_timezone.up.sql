-- Per-branch UTC offset so lesson times can render correctly for branches
-- outside Moscow. Default 180 minutes (UTC+3, Moscow) keeps existing behaviour
-- unchanged. Russia does not observe DST, so a fixed offset is sufficient.
alter table app.branches
  add column if not exists utc_offset_minutes integer not null default 180;
