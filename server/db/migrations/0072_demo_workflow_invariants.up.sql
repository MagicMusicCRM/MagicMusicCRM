-- T9.1: lead homework, atomic subscription conversion and single-owner FCM.

-- A homework may belong to a lead while the trial workflow is still in the
-- pipeline. Conversion later moves it to the created student in one transaction.
alter table app.lesson_homeworks
  add column if not exists lead_id uuid references app.leads(id) on delete cascade;

alter table app.lesson_homeworks
  alter column student_id drop not null;

alter table app.lesson_homeworks
  drop constraint if exists lesson_homeworks_student_or_lead_check;

alter table app.lesson_homeworks
  add constraint lesson_homeworks_student_or_lead_check
  check (num_nonnulls(student_id, lead_id) = 1);

create index if not exists lesson_homeworks_lead_idx
  on app.lesson_homeworks (lead_id)
  where deleted_at is null and lead_id is not null;

-- A lead can trigger exactly one subscription issuance. Unlike a generic
-- student subscription, this is a one-shot conversion command and therefore
-- has a durable database idempotency key.
alter table app.subscriptions
  add column if not exists conversion_lead_id uuid references app.leads(id) on delete set null;

create unique index if not exists subscriptions_conversion_lead_unique_idx
  on app.subscriptions (conversion_lead_id)
  where conversion_lead_id is not null;

-- One physical FCM token must never stay active for two accounts. Preserve the
-- most recently seen owner when cleaning historical duplicates before adding
-- the invariant.
with ranked_devices as (
  select id,
    row_number() over (
      partition by token_hash
      order by last_seen_at desc, updated_at desc, created_at desc, id desc
    ) as owner_rank
  from app.notification_devices
  where enabled = true
)
update app.notification_devices device
set enabled = false,
    updated_at = now()
from ranked_devices ranked
where device.id = ranked.id
  and ranked.owner_rank > 1;

create unique index if not exists notification_devices_enabled_token_unique_idx
  on app.notification_devices (token_hash)
  where enabled = true;
