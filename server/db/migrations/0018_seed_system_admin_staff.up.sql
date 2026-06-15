with existing_user as (
  select id
  from app.users
  where lower(email) = 'kvazar2727@gmail.com'
    and deleted_at is null
  limit 1
),
updated_user as (
  update app.users
  set
    full_name = 'Садуакасов Уалихан Алимжанович',
    role = 'system_admin'::app.user_role,
    is_app_account = true,
    profile_completed = true,
    email_verified_at = coalesce(email_verified_at, now()),
    updated_at = now()
  where id in (select id from existing_user)
  returning id
),
inserted_user as (
  insert into app.users (
    email,
    full_name,
    role,
    profile_completed,
    is_app_account,
    email_verified_at
  )
  select
    'kvazar2727@gmail.com',
    'Садуакасов Уалихан Алимжанович',
    'system_admin'::app.user_role,
    true,
    true,
    now()
  where not exists (select 1 from existing_user)
  returning id
),
upsert_user as (
  select id from updated_user
  union all
  select id from inserted_user
),
upsert_profile as (
  insert into app.profiles (
    user_id,
    first_name,
    last_name,
    custom_data
  )
  select
    id,
    'Уалихан',
    'Садуакасов',
    jsonb_build_object(
      'middleName', 'Алимжанович',
      'seededRole', 'Администратор системы'
    )
  from upsert_user
  on conflict (user_id)
  do update set
    first_name = coalesce(app.profiles.first_name, excluded.first_name),
    last_name = coalesce(app.profiles.last_name, excluded.last_name),
    custom_data = app.profiles.custom_data || excluded.custom_data,
    updated_at = now()
  returning id
)
insert into app.staff_members (
  profile_id,
  role,
  position,
  status,
  custom_data
)
select
  id,
  'system_admin',
  'Администратор системы',
  'working',
  jsonb_build_object('seededBy', '0018_seed_system_admin_staff')
from upsert_profile
where not exists (
  select 1
  from app.staff_members existing_staff
  where existing_staff.profile_id = upsert_profile.id
    and existing_staff.deleted_at is null
);
