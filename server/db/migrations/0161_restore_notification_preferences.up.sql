-- Restore missing settings rows without changing any existing operator choices.
-- The original 0062 seed is idempotent but has already run in production.
insert into app.notification_preferences (role, event_type, enabled, channels)
select role.role, 'new_lead',
  role.role in ('admin', 'manager', 'director'),
  array['in_app', 'push']::text[]
from (values ('admin'), ('manager'), ('director'), ('teacher')) as role(role)
on conflict (role, event_type) do nothing;
