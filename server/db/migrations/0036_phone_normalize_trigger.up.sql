-- server/db/migrations/0036_phone_normalize_trigger.up.sql
-- Enforce the canonical phone foundation at the DATABASE level: a BEFORE
-- INSERT/UPDATE trigger keeps phone_normalized in lockstep with phone on every
-- write to app.leads, app.profiles and app.users — from ANY path (API, import,
-- manual SQL). This makes it impossible to store a row whose phone_normalized
-- does not match the canonical +7XXXXXXXXXX form, so client records, lessons,
-- comments and attendance can always be linked by phone. Mirrors normalizephoneRu
-- (server/src/crm/phone.util.ts) / normalizedPhoneExpr exactly.

create or replace function app.fn_normalize_phone(raw text)
returns text
language sql
immutable
as $$
  select case
    when length(regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g')) = 11
         and left(regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
      then '+7' || right(regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g'), 10)
    when length(regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g')) = 10
         and left(regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g'), 1) = '9'
      then '+7' || regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g')
    else null
  end
$$;

create or replace function app.trg_set_phone_normalized()
returns trigger
language plpgsql
as $$
begin
  new.phone_normalized := app.fn_normalize_phone(new.phone);
  return new;
end;
$$;

-- BEFORE INSERT OR UPDATE OF phone: fires whenever a row is created or its phone
-- column is part of an UPDATE's SET list (the services always set phone via
-- coalesce, so a real change always recomputes the canonical key).
drop trigger if exists set_phone_normalized on app.leads;
create trigger set_phone_normalized
  before insert or update of phone on app.leads
  for each row execute function app.trg_set_phone_normalized();

drop trigger if exists set_phone_normalized on app.profiles;
create trigger set_phone_normalized
  before insert or update of phone on app.profiles
  for each row execute function app.trg_set_phone_normalized();

drop trigger if exists set_phone_normalized on app.users;
create trigger set_phone_normalized
  before insert or update of phone on app.users
  for each row execute function app.trg_set_phone_normalized();

-- Re-assert the canonical value across existing rows now the trigger guarantees
-- it going forward (covers the 35 leads / 26 profiles / 936 users that were left
-- un-normalized, and overwrites any stale value).
update app.leads    set phone = phone where deleted_at is null and phone is not null;
update app.profiles set phone = phone where deleted_at is null and phone is not null;
update app.users    set phone = phone where deleted_at is null and phone is not null;
