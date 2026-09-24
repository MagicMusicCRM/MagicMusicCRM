-- Restore missing settings rows without changing any existing operator choices.
-- The original 0062 seed is idempotent but has already run in production.
insert into app.notification_preferences (role, event_type, enabled, channels)
select role.role, event.event_type,
  role.role in ('admin', 'manager', 'director'),
  case when event.event_type = 'new_lead'
    then array['in_app', 'push']::text[]
    else array['push']::text[]
  end
from (values ('admin'), ('manager'), ('director'), ('teacher')) as role(role)
cross join (values
  ('new_lead'),
  ('task_reminder_day'),
  ('task_reminder_hour'),
  ('task_reminder_min10'),
  ('task_reminder_overdue')
) as event(event_type)
on conflict (role, event_type) do nothing;
