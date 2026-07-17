-- server/db/migrations/0062_notification_preferences.up.sql
-- Who gets which notification, per role — spec §4 «Настройка уведомлений по
-- ролям (админ/управляющий/директор)».
--
-- Before this, recipients were a literal in two SQL queries
-- (`u.role in ('admin','manager','director')` in the task reminder fan-out and
-- in notifyNewLead), so changing them meant a deploy.
--
-- Scope note: this governs ROLE BROADCASTS only. Two recipient rules stay in
-- code on purpose:
--   * the task assignee always gets their own task's reminders — that is not a
--     preference, it is what "assigned to you" means;
--   * lesson reminders go to the lesson's students, which is a relationship,
--     not a role.

create table if not exists app.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  -- Text, not app.user_role: the rest of the notification code compares roles
  -- as text precisely because 'director' postdates the enum in some databases,
  -- and an enum cast would make the whole fan-out query throw.
  role text not null,
  event_type text not null,
  enabled boolean not null default true,
  -- Per-role delivery: a director may want the bell but not a push at 23:00.
  channels text[] not null default array['in_app', 'push'],
  updated_by uuid references app.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (role, event_type),
  constraint notification_preferences_channels_check
    check (channels <@ array['in_app', 'push', 'email'])
);

create index if not exists notification_preferences_event_idx
  on app.notification_preferences (event_type)
  where enabled;

-- Seed = today's hardcoded behaviour, so the migration changes nothing on its
-- own. Roles absent from a broadcast are seeded explicitly as disabled rather
-- than omitted: the settings screen has to render an off switch to turn on, and
-- "no row" would render as nothing at all.
insert into app.notification_preferences (role, event_type, enabled, channels)
select r.role, e.event_type,
  r.role in ('admin', 'manager', 'director'),
  case
    when e.event_type = 'new_lead' then array['in_app', 'push']
    else array['push']
  end
from (values ('admin'), ('manager'), ('director'), ('teacher')) as r(role)
cross join (values
  ('new_lead'),
  ('task_reminder_day'),
  ('task_reminder_hour'),
  ('task_reminder_min10'),
  ('task_reminder_overdue')
) as e(event_type)
on conflict (role, event_type) do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.notification_preferences to magiccrm_app;
  end if;
end $$;
