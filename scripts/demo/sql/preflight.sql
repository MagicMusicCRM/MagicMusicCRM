\set ON_ERROR_STOP on

begin read only;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

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
    raise exception 'Demo account allowlist mismatch: expected the exact four user IDs and roles.';
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
    raise exception 'Demo profile allowlist mismatch: expected the exact four profile IDs.';
  end if;

  if not exists (
    select 1 from app.chats
    where id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
      and type = 'administration'
      and owner_user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and deleted_at is null
  ) then
    raise exception 'The exact magic1 administration-chat container is missing or changed.';
  end if;

  if exists (
    select 1 from app.chats
    where type = 'administration'
      and owner_user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and deleted_at is null
      and id <> '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
  ) then
    raise exception 'Unexpected second active administration chat for magic1.';
  end if;

  if not exists (
    select 1 from app.chats
    where id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid
      and slug = 'announcements'
      and is_system = true
      and deleted_at is null
  ) then
    raise exception 'The shared announcements chat allowlist entry is missing or changed.';
  end if;
end
$guard$;

select 'ACCOUNT', lower(u.email), u.id::text, u.role::text, p.id::text,
       case when u.deleted_at is null and p.deleted_at is null then 'OK' else 'BLOCKED' end
from app.users u
join app.profiles p on p.user_id = u.id
where lower(u.email) in ('magic1@gmail.com', 'magic2@gmail.com', 'magic3@gmail.com', 'magic4@gmail.com')
order by lower(u.email);

select case when exists (
         select 1 from app.notification_devices
         where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid and enabled
       ) then 'OK' else 'BLOCKER' end,
       'magic1_fcm',
       case when exists (
         select 1 from app.notification_devices
         where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid and enabled
       ) then 'At least one enabled push device is registered.'
       else 'No enabled FCM device for magic1; log in on the Client AVD before the demo.' end;

select case when exists (
         select 1
         from app.teachers t
         join app.user_crm_links l
           on l.entity_type = 'teacher' and l.entity_id = t.id and l.deleted_at is null
         where t.profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
           and t.deleted_at is null and t.status = 'active'
           and l.user_id = '9ed56659-502f-45c0-9be5-90f3a7473780'::uuid
       ) then 'OK' else 'BLOCKER' end,
       'magic2_teacher_link',
       'magic2 must have one active teacher entity and matching user_crm_links row.';

select case when exists (
         select 1
         from app.teachers t
         join app.teacher_disciplines td on td.teacher_id = t.id
         join app.teacher_branches tb on tb.teacher_id = t.id
         where t.profile_id = 'a4193eed-51ec-4464-9378-6ac63304a69c'::uuid
           and t.deleted_at is null
           and td.discipline_id = '13dc04ee-9a88-4fab-87ba-24d4591439d0'::uuid
           and tb.branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
       ) then 'OK' else 'BLOCKER' end,
       'magic2_teacher_scope',
       'magic2 must be linked to Piano and the Sokol branch.';

select case when exists (
         select 1
         from app.staff_members s
         join app.user_crm_links l
           on l.entity_type = 'staff' and l.entity_id = s.id and l.deleted_at is null
         where s.profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
           and s.deleted_at is null and s.role = 'admin' and s.status = 'working'
           and l.user_id = 'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid
       ) then 'OK' else 'BLOCKER' end,
       'magic3_staff_link',
       'magic3 must have one active admin staff entity and matching CRM link.';

select case when exists (
         select 1
         from app.staff_members s
         join app.staff_branch_assignments a on a.staff_member_id = s.id and a.deleted_at is null
         where s.profile_id = '29f0fd48-a4af-40b5-868e-abd472b7f837'::uuid
           and s.deleted_at is null
           and a.branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
       ) then 'OK' else 'BLOCKER' end,
       'magic3_staff_scope',
       'magic3 must be assigned to the Sokol branch.';

select case when exists (
         select 1
         from app.staff_members s
         join app.user_crm_links l
           on l.entity_type = 'staff' and l.entity_id = s.id and l.deleted_at is null
         where s.profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
           and s.deleted_at is null and s.role = 'manager' and s.status = 'working'
           and l.user_id = '4805fac8-60d2-4483-9882-940f363160c0'::uuid
       ) then 'OK' else 'BLOCKER' end,
       'magic4_staff_link',
       'magic4 must have one active manager staff entity and matching CRM link.';

select case when exists (
         select 1
         from app.staff_members s
         join app.staff_branch_assignments a on a.staff_member_id = s.id and a.deleted_at is null
         where s.profile_id = '4b7e363d-0dce-44f9-a468-9e0dfd00d32f'::uuid
           and s.deleted_at is null
           and a.branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
       ) then 'OK' else 'BLOCKER' end,
       'magic4_staff_scope',
       'magic4 must be assigned to the Sokol branch.';

select case when exists (
         select 1 from app.branches
         where id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
           and name = 'Сокол' and deleted_at is null
       ) then 'OK' else 'BLOCKER' end,
       'sokol_branch', 'The exact Sokol branch is required.';

select case when exists (
         select 1 from app.rooms
         where id = 'b97da1d3-cf10-4b5a-8f77-bd1c30edd5e1'::uuid
           and branch_id = '62f5f8f6-5d03-4138-9189-15064c8f4a72'::uuid
           and name = 'Piano room 7' and deleted_at is null
       ) then 'OK' else 'BLOCKER' end,
       'piano_room_7', 'The exact demo room is required.';

select case when exists (
         select 1 from app.disciplines
         where id = '13dc04ee-9a88-4fab-87ba-24d4591439d0'::uuid
           and name = 'Фортепиано' and is_active and deleted_at is null
       ) then 'OK' else 'BLOCKER' end,
       'piano_discipline', 'The exact Piano discipline is required.';

select case when exists (
         select 1 from app.subscription_packages
         where is_active and deleted_at is null
       ) then 'OK' else 'BLOCKER' end,
       'active_subscription_package',
       'At least one active subscription package is required.';

select 'DEVICE', lower(u.email), count(d.id)::text,
       count(d.id) filter (where d.enabled)::text,
       coalesce(max(d.last_seen_at)::text, '')
from app.users u
left join app.notification_devices d on d.user_id = u.id
where lower(u.email) in ('magic1@gmail.com', 'magic2@gmail.com', 'magic3@gmail.com', 'magic4@gmail.com')
group by lower(u.email)
order by lower(u.email);

with linked_leads as (
  select distinct link.entity_id as id
  from app.user_crm_links link
  join app.leads lead on lead.id = link.entity_id
  where link.user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
    and link.entity_type = 'lead'
  union
  select lead_id from app.chats
  where id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
    and lead_id is not null
), initial_students as (
  select student.id from app.students student
  where student.profile_id = 'a0fe524d-21d8-411c-8fc8-d6a113e1b9be'::uuid
  union
  select link.entity_id from app.user_crm_links link
  join app.students student on student.id = link.entity_id
  where link.user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
    and link.entity_type = 'student'
  union
  select student.id from app.students student
  where student.lead_id in (select id from linked_leads)
  union
  select student_id from app.chats
  where id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
    and student_id is not null
), target_leads as (
  select id from linked_leads
  union
  select lead_id from app.students
  where id in (select id from initial_students) and lead_id is not null
), target_students as (
  select id from initial_students
  union
  select id from app.students where lead_id in (select id from target_leads)
), target_lessons as (
  select id from app.lessons
  where lead_id in (select id from target_leads)
     or student_id in (select id from target_students)
), target_homeworks as (
  select homework.id from app.lesson_homeworks homework
  where homework.student_id in (select id from target_students)
     or homework.lesson_id in (select id from target_lessons)
     or nullif(to_jsonb(homework) ->> 'lead_id', '')::uuid in (select id from target_leads)
), target_tasks as (
  select task.id from app.shared_tasks task
  where task.deleted_at is null and (
       (task.linked_entity_type = 'lead' and task.linked_entity_id in (select id from target_leads))
    or (task.linked_entity_type = 'student' and task.linked_entity_id in (select id from target_students))
    or (task.linked_entity_type = 'lesson' and task.linked_entity_id in (select id from target_lessons))
  )
), target_notifications as (
  select notification.id
  from app.notifications notification
  where (
      notification.data ->> 'entityType' = 'lead'
      and exists (
        select 1 from target_leads target
        where target.id::text = notification.data ->> 'entityId'
      )
    ) or (
      notification.data ->> 'entityType' = 'student'
      and exists (
        select 1 from target_students target
        where target.id::text = notification.data ->> 'entityId'
      )
    ) or (
      notification.data ->> 'entityType' = 'lesson'
      and exists (
        select 1 from target_lessons target
        where target.id::text = notification.data ->> 'entityId'
      )
    ) or exists (
      select 1 from target_lessons target
      where target.id::text = notification.data ->> 'lessonId'
    ) or (
      notification.data ->> 'entityType' = 'homework'
      and exists (
        select 1 from target_homeworks target
        where target.id::text = notification.data ->> 'entityId'
      )
    ) or exists (
      select 1 from target_homeworks target
      where target.id::text = notification.data ->> 'homeworkId'
    ) or (
      notification.data ->> 'entityType' = 'task'
      and exists (
        select 1 from target_tasks target
        where target.id::text = notification.data ->> 'entityId'
      )
    ) or exists (
      select 1 from target_tasks target
      where target.id::text = notification.data ->> 'taskId'
    )
), reset_plan as (
  select 'leads' as entity, count(*)::text as count from target_leads
  union all select 'students', count(*)::text from target_students
  union all select 'crm_links', count(*)::text from app.user_crm_links
    where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid and entity_type in ('lead', 'student')
  union all select 'private_chat_messages', count(*)::text from app.messages
    where chat_id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
  union all select 'lessons', count(*)::text from target_lessons
  union all select 'schedule_series', count(*)::text from app.schedule_series
    where student_id in (select id from target_students)
  union all select 'homework', count(*)::text from target_homeworks
  union all select 'subscriptions', count(*)::text from app.subscriptions subscription
    where subscription.student_id in (select id from target_students)
       or nullif(to_jsonb(subscription) ->> 'conversion_lead_id', '')::uuid in (select id from target_leads)
  union all select 'payments', count(*)::text from app.payments
    where student_id in (select id from target_students)
  union all select 'tasks', count(*)::text from target_tasks
  union all select 'entity_comments', count(*)::text from app.entity_comments
    where (entity_type = 'lead' and entity_id in (select id from target_leads))
       or (entity_type = 'student' and entity_id in (select id from target_students))
  union all select 'target_notifications', count(*)::text from target_notifications
  union all select 'notification_recipients', count(*)::text from app.notification_recipients
    where notification_id in (select id from target_notifications)
  union all select 'notification_deliveries', count(*)::text from app.notification_deliveries
    where notification_id in (select id from target_notifications)
  union all select 'notification_email_outbox', count(*)::text from app.email_outbox outbox
    where exists (
        select 1 from target_notifications target
        where target.id::text = outbox.payload ->> 'notificationId'
      )
)
select 'RESET_PLAN', entity, count from reset_plan order by entity;

commit;
