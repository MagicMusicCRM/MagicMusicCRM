-- server/db/migrations/0035_users_phone_normalized.up.sql
-- Extend the canonical phone foundation (0025) to app.users: add the
-- phone_normalized column, a partial index mirroring the lead/profile indexes,
-- and a one-time backfill using the same CASE expression as 0025.
alter table app.users add column if not exists phone_normalized text;

create index if not exists users_phone_normalized_idx
  on app.users (phone_normalized) where deleted_at is null;

-- Backfill canonical phone (mirror of normalizedPhoneExpr / normalizePhoneRu).
update app.users u
set phone_normalized = case
    when length(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g')) = 11
         and left(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
      then '+7' || right(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g'), 10)
    when length(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g')) = 10
         and left(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
      then '+7' || regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g')
    else null
  end
where u.deleted_at is null;
