\set ON_ERROR_STOP on

begin isolation level serializable;
set local statement_timeout = '45s';
set local lock_timeout = '5s';

do $guard$
declare
  account_count integer;
  profile_count integer;
begin
  select count(*) into account_count
  from app.users
  where (lower(email), id, role::text, deleted_at is null) in (
    ('magic1@gmail.com', '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid, 'client', true),
    ('magic2@gmail.com', '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid, 'teacher', true),
    ('magic3@gmail.com', 'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid, 'admin', true),
    ('magic4@gmail.com', '4805fac8-60d2-4483-9882-940f363160c0'::uuid, 'manager', true)
  );
  if account_count <> 4 then
    raise exception 'Demo auth account IDs/roles do not match the exact allowlist.';
  end if;

  select count(*) into profile_count
  from app.profiles
  where deleted_at is null and (user_id, id) in (
    ('18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid, 'a0fe524d-21d8-411c-8fc8-d6a113e1b9be'::uuid),
    ('9ed56659-502f-45c0-9be5-90f3a7473780'::uuid, 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid),
    ('e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid, '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid),
    ('4805fac8-60d2-4483-9882-940f363160c0'::uuid, '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid)
  );
  if profile_count <> 4 then
    raise exception 'Demo profile IDs do not match the exact allowlist.';
  end if;

  if not exists (
    select 1 from app.branches
    where id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
      and name = 'Сокол' and deleted_at is null
  ) or not exists (
    select 1 from app.rooms
    where id = 'b97da1d3-cf10-4b5a-8f77-bd1c30edd5e1'::uuid
      and branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
      and name = 'Piano room 7' and deleted_at is null
  ) or not exists (
    select 1 from app.disciplines
    where id = '13dc04ee-9a88-4fab-87ba-24d4591439d0'::uuid
      and name = 'Фортепиано' and is_active and deleted_at is null
  ) then
    raise exception 'Exact Sokol/Piano room/Piano resource allowlist mismatch.';
  end if;

  if exists (
    select 1 from app.teachers
    where profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
      and deleted_at is null and status <> 'active'
  ) then
    raise exception 'magic2 already has a non-active teacher entity; refusing to mutate it.';
  end if;
  if exists (
    select 1 from app.staff_members
    where profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
      and deleted_at is null and (role <> 'admin' or status <> 'working')
  ) then
    raise exception 'magic3 already has conflicting staff role/status; refusing to mutate it.';
  end if;
  if exists (
    select 1 from app.staff_members
    where profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
      and deleted_at is null and (role <> 'manager' or status <> 'working')
  ) then
    raise exception 'magic4 already has conflicting staff role/status; refusing to mutate it.';
  end if;

  perform 1 from app.users
  where id in (
    '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid,
    'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid,
    '4805fac8-60d2-4483-9882-940f363160c0'::uuid
  ) for update;
end
$guard$;

insert into app.teachers (profile_id, status, specialization, custom_data)
select 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid,
       'active', 'Фортепиано', '{"demoFixture":"T9.2"}'::jsonb
where not exists (
  select 1 from app.teachers
  where profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
    and deleted_at is null
);

do $teacher_guard$
begin
  if (select count(*) from app.teachers
      where profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
        and deleted_at is null and status = 'active') <> 1 then
    raise exception 'Expected exactly one active teacher entity for magic2.';
  end if;
  if exists (
    select 1 from app.user_crm_links link
    where link.user_id = '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid
      and link.entity_type = 'teacher' and link.deleted_at is null
      and link.entity_id <> (
        select id from app.teachers
        where profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
          and deleted_at is null and status = 'active'
      )
  ) then
    raise exception 'magic2 has an unexpected active teacher CRM link.';
  end if;
end
$teacher_guard$;

insert into app.teacher_disciplines (teacher_id, discipline_id)
select teacher.id, '13dc04ee-9a88-4fab-87ba-24d4591439d0'::uuid
from app.teachers teacher
where teacher.profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
  and teacher.deleted_at is null and teacher.status = 'active'
on conflict do nothing;

insert into app.teacher_branches (teacher_id, branch_id)
select teacher.id, '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
from app.teachers teacher
where teacher.profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
  and teacher.deleted_at is null and teacher.status = 'active'
on conflict do nothing;

insert into app.user_crm_links
  (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
select '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid,
       'teacher', teacher.id, null, 'manual_email', null, now()
from app.teachers teacher
where teacher.profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
  and teacher.deleted_at is null and teacher.status = 'active'
  and not exists (
    select 1 from app.user_crm_links link
    where link.user_id = '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid
      and link.entity_type = 'teacher' and link.entity_id = teacher.id
      and link.deleted_at is null
  );

insert into app.staff_members (profile_id, role, position, status, custom_data)
select '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid,
       'admin', 'Администратор', 'working', '{"demoFixture":"T9.2"}'::jsonb
where not exists (
  select 1 from app.staff_members
  where profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
    and deleted_at is null
);

insert into app.staff_members (profile_id, role, position, status, custom_data)
select '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid,
       'manager', 'Управляющий', 'working', '{"demoFixture":"T9.2"}'::jsonb
where not exists (
  select 1 from app.staff_members
  where profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
    and deleted_at is null
);

do $staff_guard$
begin
  if (select count(*) from app.staff_members
      where profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
        and deleted_at is null and role = 'admin' and status = 'working') <> 1 then
    raise exception 'Expected exactly one active admin staff entity for magic3.';
  end if;
  if (select count(*) from app.staff_members
      where profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
        and deleted_at is null and role = 'manager' and status = 'working') <> 1 then
    raise exception 'Expected exactly one active manager staff entity for magic4.';
  end if;
  if exists (
    select 1 from app.user_crm_links link
    where link.user_id = 'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid
      and link.entity_type = 'staff' and link.deleted_at is null
      and link.entity_id <> (
        select id from app.staff_members
        where profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
          and deleted_at is null
      )
  ) or exists (
    select 1 from app.user_crm_links link
    where link.user_id = '4805fac8-60d2-4483-9882-940f363160c0'::uuid
      and link.entity_type = 'staff' and link.deleted_at is null
      and link.entity_id <> (
        select id from app.staff_members
        where profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
          and deleted_at is null
      )
  ) then
    raise exception 'A demo staff account has an unexpected active CRM link.';
  end if;
end
$staff_guard$;

insert into app.staff_branch_assignments (staff_member_id, branch_id)
select staff.id, '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
from app.staff_members staff
where staff.profile_id in (
  '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid,
  '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
) and staff.deleted_at is null
on conflict (staff_member_id, branch_id)
do update set deleted_at = null;

insert into app.user_crm_links
  (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
select user_id, 'staff', staff_id, null, 'manual_email', null, now()
from (
  select 'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid as user_id, staff.id as staff_id
  from app.staff_members staff
  where staff.profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
    and staff.deleted_at is null
  union all
  select '4805fac8-60d2-4483-9882-940f363160c0'::uuid, staff.id
  from app.staff_members staff
  where staff.profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
    and staff.deleted_at is null
) support
where not exists (
  select 1 from app.user_crm_links link
  where link.user_id = support.user_id
    and link.entity_type = 'staff' and link.entity_id = support.staff_id
    and link.deleted_at is null
);

insert into app.subscription_packages
  (name, discipline_id, branch_id, lessons_total, price, validity_days, is_active, sort_order)
select 'Демо — Фортепиано, 8 часов',
       '13dc04ee-9a88-4fab-87ba-24d4591439d0'::uuid,
       '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid,
       8.00, 24000.00, 60, true, 9000
where not exists (
  select 1 from app.subscription_packages
  where is_active and deleted_at is null
);

do $postcheck$
begin
  if not exists (
    select 1
    from app.teachers teacher
    join app.teacher_disciplines discipline on discipline.teacher_id = teacher.id
    join app.teacher_branches branch on branch.teacher_id = teacher.id
    join app.user_crm_links link
      on link.entity_type = 'teacher' and link.entity_id = teacher.id and link.deleted_at is null
    where teacher.profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
      and teacher.deleted_at is null and teacher.status = 'active'
      and discipline.discipline_id = '13dc04ee-9a88-4fab-87ba-24d4591439d0'::uuid
      and branch.branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
      and link.user_id = '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid
  ) then
    raise exception 'Teacher support post-check failed.';
  end if;

  if not exists (
    select 1 from app.staff_members staff
    join app.staff_branch_assignments branch
      on branch.staff_member_id = staff.id and branch.deleted_at is null
    join app.user_crm_links link
      on link.entity_type = 'staff' and link.entity_id = staff.id and link.deleted_at is null
    where staff.profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
      and staff.role = 'admin' and staff.status = 'working' and staff.deleted_at is null
      and branch.branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
      and link.user_id = 'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid
  ) or not exists (
    select 1 from app.staff_members staff
    join app.staff_branch_assignments branch
      on branch.staff_member_id = staff.id and branch.deleted_at is null
    join app.user_crm_links link
      on link.entity_type = 'staff' and link.entity_id = staff.id and link.deleted_at is null
    where staff.profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
      and staff.role = 'manager' and staff.status = 'working' and staff.deleted_at is null
      and branch.branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
      and link.user_id = '4805fac8-60d2-4483-9882-940f363160c0'::uuid
  ) then
    raise exception 'Staff support post-check failed.';
  end if;

  if not exists (
    select 1 from app.subscription_packages
    where is_active and deleted_at is null
  ) then
    raise exception 'Subscription-package post-check failed.';
  end if;

  if not exists (
    select 1 from app.users
    where id = '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid and role::text = 'teacher'
  ) or not exists (
    select 1 from app.users
    where id = 'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid and role::text = 'admin'
  ) or not exists (
    select 1 from app.users
    where id = '4805fac8-60d2-4483-9882-940f363160c0'::uuid and role::text = 'manager'
  ) then
    raise exception 'Auth roles changed unexpectedly.';
  end if;
end
$postcheck$;

select 'SUPPORT_OK',
       (select id::text from app.teachers where profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid and deleted_at is null),
       (select id::text from app.staff_members where profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid and deleted_at is null),
       (select id::text from app.staff_members where profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid and deleted_at is null),
       (select id::text from app.subscription_packages where is_active and deleted_at is null order by sort_order, name limit 1),
       'auth-roles-unchanged';

commit;
