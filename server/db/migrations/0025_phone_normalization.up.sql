-- server/db/migrations/0025_phone_normalization.up.sql
-- Canonical phone foundation: phone_normalized column + review queue + backfill.
alter table app.leads add column if not exists phone_normalized text;
alter table app.profiles add column if not exists phone_normalized text;

create index if not exists leads_phone_normalized_idx
  on app.leads (phone_normalized) where deleted_at is null;
create index if not exists profiles_phone_normalized_idx
  on app.profiles (phone_normalized) where deleted_at is null;

create table if not exists app.phone_review_queue (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  raw_phone text,
  reason text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references app.users(id) on delete set null,
  constraint phone_review_queue_entity_check check (entity_type in ('lead', 'profile')),
  constraint phone_review_queue_reason_check check (reason in ('empty', 'too_short', 'non_ru')),
  constraint phone_review_queue_identity_unique unique (entity_type, entity_id)
);

create index if not exists phone_review_queue_open_idx
  on app.phone_review_queue (created_at desc) where resolved_at is null;

-- Backfill canonical phone (mirror of normalizedPhoneExpr / normalizePhoneRu).
update app.leads l
set phone_normalized = case
    when length(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')) = 11
         and left(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
      then '+7' || right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 10)
    when length(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')) = 10
         and left(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
      then '+7' || regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')
    else null
  end
where l.deleted_at is null;

update app.profiles p
set phone_normalized = case
    when length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) = 11
         and left(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 1) in ('7', '8')
      then '+7' || right(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 10)
    when length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) = 10
         and left(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 1) = '9'
      then '+7' || regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')
    else null
  end
where p.deleted_at is null;

-- Route un-normalizable rows into the review queue.
insert into app.phone_review_queue (entity_type, entity_id, raw_phone, reason)
select 'lead', l.id, l.phone,
  case
    when regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g') = '' then 'empty'
    when length(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g')) < 10 then 'too_short'
    else 'non_ru'
  end
from app.leads l
where l.deleted_at is null and l.phone_normalized is null
on conflict (entity_type, entity_id) do nothing;

insert into app.phone_review_queue (entity_type, entity_id, raw_phone, reason)
select 'profile', p.id, p.phone,
  case
    when regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = '' then 'empty'
    when length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) < 10 then 'too_short'
    else 'non_ru'
  end
from app.profiles p
where p.deleted_at is null and p.phone_normalized is null
on conflict (entity_type, entity_id) do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.phone_review_queue to magiccrm_app;
  end if;
end $$;
