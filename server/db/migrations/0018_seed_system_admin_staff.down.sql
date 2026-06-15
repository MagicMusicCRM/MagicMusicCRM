update app.staff_members sm
set deleted_at = coalesce(deleted_at, now()),
    updated_at = now()
from app.profiles p
join app.users u on u.id = p.user_id
where sm.profile_id = p.id
  and lower(u.email) = 'kvazar2727@gmail.com'
  and sm.deleted_at is null
  and sm.custom_data ->> 'seededBy' = '0018_seed_system_admin_staff';

update app.users
set role = 'admin'::app.user_role,
    updated_at = now()
where lower(email) = 'kvazar2727@gmail.com'
  and role = 'system_admin'::app.user_role;
