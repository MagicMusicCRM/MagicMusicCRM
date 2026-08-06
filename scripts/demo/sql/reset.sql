\set ON_ERROR_STOP on

begin isolation level repeatable read;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

create temp table demo_preserve_snapshot (
  key text primary key,
  value text not null
) on commit drop;

insert into demo_preserve_snapshot (key, value) values
  ('user_role', (
    select role::text from app.users
    where id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  )),
  ('profile_id', (
    select id::text from app.profiles
    where id = 'a0fe524d-21d8-411c-8fc8-d6a113e1b9be'::uuid
  )),
  ('legal_count', (
    select count(*)::text from app.legal_consents
    where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  )),
  ('device_signature', (
    select coalesce(md5(string_agg(
      id::text || ':' || platform || ':' || enabled::text || ':' || token_hash,
      ',' order by id
    )), 'EMPTY')
    from app.notification_devices
    where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  )),
  ('audit_count', (select count(*)::text from app.audit_events)),
  ('admin_membership_signature', (
    select coalesce(md5(string_agg(
      id::text || ':' || user_id::text || ':' || role || ':' ||
        coalesce(joined_at::text, '') || ':' || coalesce(left_at::text, ''),
      ',' order by id
    )), 'EMPTY')
    from app.chat_members
    where chat_id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
  )),
  ('announcements_chat_count', (
    select count(*)::text from app.chats
    where id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid
  )),
  ('announcements_message_count', (
    select count(*)::text from app.messages
    where chat_id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid
  )),
  ('announcements_membership_signature', (
    select coalesce(md5(string_agg(
      id::text || ':' || user_id::text || ':' || role || ':' ||
        coalesce(joined_at::text, '') || ':' || coalesce(left_at::text, ''),
      ',' order by id
    )), 'EMPTY')
    from app.chat_members
    where chat_id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid
  ));

do $identity_guard$
begin
  if (select count(*)
      from app.users
      where (id, lower(email), role::text, deleted_at is null) in (
        ('18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid, 'magic1@gmail.com', 'client', true),
        ('9ed56659-502f-45c0-9be5-90f3a7473780'::uuid, 'magic2@gmail.com', 'teacher', true),
        ('e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid, 'magic3@gmail.com', 'admin', true),
        ('4805fac8-60d2-4483-9882-940f363160c0'::uuid, 'magic4@gmail.com', 'manager', true)
      )) <> 4 then
    raise exception 'Exact four-account demo identity/role allowlist mismatch.';
  end if;
  if not exists (
    select 1 from app.users
    where id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and lower(email) = 'magic1@gmail.com'
      and role::text = 'client'
      and deleted_at is null
  ) then
    raise exception 'magic1 auth identity/role allowlist mismatch.';
  end if;
  if not exists (
    select 1 from app.profiles
    where id = 'a0fe524d-21d8-411c-8fc8-d6a113e1b9be'::uuid
      and user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and deleted_at is null
  ) then
    raise exception 'magic1 profile allowlist mismatch.';
  end if;
  if not exists (
    select 1 from app.chats
    where id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
      and type = 'administration'
      and owner_user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and deleted_at is null
  ) then
    raise exception 'magic1 administration-chat allowlist mismatch.';
  end if;
  if not exists (
    select 1 from app.chats
    where id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid
      and slug = 'announcements' and is_system and deleted_at is null
  ) then
    raise exception 'Shared announcements allowlist mismatch.';
  end if;

  perform 1 from app.users
  where id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  for update;
  perform 1 from app.profiles
  where id = 'a0fe524d-21d8-411c-8fc8-d6a113e1b9be'::uuid
  for update;
  perform 1 from app.chats
  where id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid
  for update;
end
$identity_guard$;

create temp table demo_target_chats (id uuid primary key) on commit drop;
insert into demo_target_chats values ('1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid);

create temp table demo_target_leads (id uuid primary key) on commit drop;
insert into demo_target_leads (id)
select distinct link.entity_id
from app.user_crm_links link
join app.leads lead on lead.id = link.entity_id
where link.user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  and link.entity_type = 'lead'
on conflict do nothing;
insert into demo_target_leads (id)
select lead_id from app.chats
where id in (select id from demo_target_chats) and lead_id is not null
on conflict do nothing;

create temp table demo_target_students (id uuid primary key) on commit drop;
insert into demo_target_students (id)
select id from app.students
where profile_id = 'a0fe524d-21d8-411c-8fc8-d6a113e1b9be'::uuid
union
select link.entity_id
from app.user_crm_links link
join app.students student on student.id = link.entity_id
where link.user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  and link.entity_type = 'student'
union
select id from app.students where lead_id in (select id from demo_target_leads)
union
select student_id from app.chats
where id in (select id from demo_target_chats) and student_id is not null
on conflict do nothing;

insert into demo_target_leads (id)
select distinct lead_id from app.students
where id in (select id from demo_target_students) and lead_id is not null
on conflict do nothing;

create temp table demo_target_lessons (id uuid primary key) on commit drop;
insert into demo_target_lessons (id)
select id from app.lessons
where lead_id in (select id from demo_target_leads)
   or student_id in (select id from demo_target_students);

create temp table demo_target_series (id uuid primary key) on commit drop;
insert into demo_target_series (id)
select id from app.schedule_series
where student_id in (select id from demo_target_students);

create temp table demo_target_homeworks (id uuid primary key) on commit drop;
insert into demo_target_homeworks (id)
select homework.id
from app.lesson_homeworks homework
where homework.student_id in (select id from demo_target_students)
   or homework.lesson_id in (select id from demo_target_lessons)
   or nullif(to_jsonb(homework) ->> 'lead_id', '')::uuid in (select id from demo_target_leads);

create temp table demo_target_tasks (id uuid primary key) on commit drop;
insert into demo_target_tasks (id)
select id from app.shared_tasks
where deleted_at is null and (
     (linked_entity_type = 'lead' and linked_entity_id in (select id from demo_target_leads))
  or (linked_entity_type = 'student' and linked_entity_id in (select id from demo_target_students))
  or (linked_entity_type = 'lesson' and linked_entity_id in (select id from demo_target_lessons))
);

create temp table demo_target_notifications (id uuid primary key) on commit drop;
insert into demo_target_notifications (id)
select notification.id
from app.notifications notification
where (
    notification.data ->> 'entityType' = 'lead'
    and exists (
      select 1 from demo_target_leads target
      where target.id::text = notification.data ->> 'entityId'
    )
  ) or (
    notification.data ->> 'entityType' = 'student'
    and exists (
      select 1 from demo_target_students target
      where target.id::text = notification.data ->> 'entityId'
    )
  ) or (
    notification.data ->> 'entityType' = 'lesson'
    and exists (
      select 1 from demo_target_lessons target
      where target.id::text = notification.data ->> 'entityId'
    )
  ) or exists (
    select 1 from demo_target_lessons target
    where target.id::text = notification.data ->> 'lessonId'
  ) or (
    notification.data ->> 'entityType' = 'homework'
    and exists (
      select 1 from demo_target_homeworks target
      where target.id::text = notification.data ->> 'entityId'
    )
  ) or exists (
    select 1 from demo_target_homeworks target
    where target.id::text = notification.data ->> 'homeworkId'
  ) or (
    notification.data ->> 'entityType' = 'task'
    and exists (
      select 1 from demo_target_tasks target
      where target.id::text = notification.data ->> 'entityId'
    )
  ) or exists (
    select 1 from demo_target_tasks target
    where target.id::text = notification.data ->> 'taskId'
  );

-- Preserve proofs are captured after the graph is known. They make an overly
-- broad notification cleanup fail the transaction instead of silently erasing
-- an unrelated bell item (including shared-announcement notifications).
insert into demo_preserve_snapshot (key, value) values
  ('unrelated_notification_recipient_signature', (
    select coalesce(md5(string_agg(recipient.id::text, ',' order by recipient.id)), 'EMPTY')
    from app.notification_recipients recipient
    where recipient.notification_id not in (select id from demo_target_notifications)
  )),
  ('unrelated_notification_delivery_signature', (
    select coalesce(md5(string_agg(delivery.id::text, ',' order by delivery.id)), 'EMPTY')
    from app.notification_deliveries delivery
    where delivery.notification_id not in (select id from demo_target_notifications)
  )),
  ('unrelated_notification_email_outbox_signature', (
    select coalesce(md5(string_agg(outbox.id::text, ',' order by outbox.id)), 'EMPTY')
    from app.email_outbox outbox
    where not exists (
        select 1 from demo_target_notifications target
        where target.id::text = outbox.payload ->> 'notificationId'
      )
  ));

do $dependency_guard$
begin
  if exists (
    select 1 from app.user_crm_links
    where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and entity_type::text not in ('lead', 'student')
      and deleted_at is null
  ) then
    raise exception 'Unexpected non-client CRM link exists for magic1.';
  end if;

  if exists (
    select 1 from app.user_crm_links
    where user_id <> '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and deleted_at is null
      and ((entity_type = 'lead' and entity_id in (select id from demo_target_leads))
        or (entity_type = 'student' and entity_id in (select id from demo_target_students)))
  ) then
    raise exception 'A target lead/student is actively linked to another user.';
  end if;

  if exists (
    select 1 from app.chats
    where id not in (select id from demo_target_chats)
      and (lead_id in (select id from demo_target_leads)
        or student_id in (select id from demo_target_students))
  ) then
    raise exception 'A target CRM entity is referenced by an unexpected chat.';
  end if;

  if (select count(*) from app.chat_members
      where chat_id in (select id from demo_target_chats) and left_at is null) <> 3
     or exists (
       select 1 from app.chat_members
       where chat_id in (select id from demo_target_chats)
         and left_at is null
         and user_id not in (
           '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid,
           'e811d61e-d260-4c4c-8ae6-0a686b0dac3f'::uuid,
           '4805fac8-60d2-4483-9882-940f363160c0'::uuid
         )
     ) then
    raise exception 'magic1 administration-chat membership allowlist mismatch.';
  end if;

  if exists (
    select 1 from app.students
    where lead_id in (select id from demo_target_leads)
      and id not in (select id from demo_target_students)
  ) then
    raise exception 'A target lead is referenced by an unexpected student.';
  end if;

  if exists (
    select 1 from app.lessons
    where lead_id in (select id from demo_target_leads)
      and student_id is not null
      and student_id not in (select id from demo_target_students)
  ) then
    raise exception 'A target lead lesson belongs to an unexpected student.';
  end if;

  if exists (
    select 1 from app.lesson_participation
    where lesson_id in (select id from demo_target_lessons)
      and student_id not in (select id from demo_target_students)
  ) then
    raise exception 'A target direct lesson has participation for another student.';
  end if;

  if exists (
    select 1 from app.lesson_homeworks
    where lesson_id in (select id from demo_target_lessons)
      and student_id not in (select id from demo_target_students)
  ) then
    raise exception 'A target direct lesson has homework for another student.';
  end if;

  if exists (
    select 1 from app.duplicate_candidates
    where (entity_type_a = 'lead' and entity_id_a in (select id from demo_target_leads))
       or (entity_type_b = 'lead' and entity_id_b in (select id from demo_target_leads))
       or (entity_type_a = 'student' and entity_id_a in (select id from demo_target_students))
       or (entity_type_b = 'student' and entity_id_b in (select id from demo_target_students))
  ) then
    raise exception 'Target CRM entities have duplicate-candidate history; manual review is required.';
  end if;

  if exists (
    select 1 from app.import_source_records
    where (target_table = 'leads' and target_id in (select id from demo_target_leads))
       or (target_table = 'students' and target_id in (select id from demo_target_students))
  ) then
    raise exception 'Target CRM entities have import provenance; manual review is required.';
  end if;

  if exists (
    select 1 from app.merge_log
    where (entity_type = 'lead' and (loser_id in (select id from demo_target_leads) or winner_id in (select id from demo_target_leads)))
       or (entity_type = 'student' and (loser_id in (select id from demo_target_students) or winner_id in (select id from demo_target_students)))
  ) then
    raise exception 'Target CRM entities have merge history; manual review is required.';
  end if;

  if exists (
    select 1 from app.phone_review_queue
    where (entity_type = 'lead' and entity_id in (select id from demo_target_leads))
       or (entity_type = 'student' and entity_id in (select id from demo_target_students))
  ) then
    raise exception 'Target CRM entities are present in phone-review queue; manual review is required.';
  end if;

  perform 1 from app.user_crm_links
  where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  for update;
  perform 1 from app.leads where id in (select id from demo_target_leads) for update;
  perform 1 from app.students where id in (select id from demo_target_students) for update;
  perform 1 from app.lessons where id in (select id from demo_target_lessons) for update;
end
$dependency_guard$;

update app.chats
set last_message_id = null,
    lead_id = null,
    student_id = null,
    branch_id = null,
    assigned_to_user_id = null,
    assigned_at = null,
    updated_at = now()
where id in (select id from demo_target_chats);

delete from app.chat_inbox_state where chat_id in (select id from demo_target_chats);
delete from app.chat_work_events where chat_id in (select id from demo_target_chats);
update app.chat_members
set last_read_message_id = null, muted_until = null
where chat_id in (select id from demo_target_chats);
delete from app.messages where chat_id in (select id from demo_target_chats);

delete from app.notification_recipients recipient
where recipient.notification_id in (select id from demo_target_notifications);
delete from app.notification_deliveries delivery
where delivery.notification_id in (select id from demo_target_notifications);
delete from app.email_outbox outbox
where exists (
    select 1 from demo_target_notifications target
    where target.id::text = outbox.payload ->> 'notificationId'
  );
delete from app.notifications notification
where notification.id in (select id from demo_target_notifications);

update app.shared_tasks
set deleted_at = coalesce(deleted_at, now()), updated_at = now()
where id in (select id from demo_target_tasks);
delete from app.entity_comments
where (entity_type = 'lead' and entity_id in (select id from demo_target_leads))
   or (entity_type = 'student' and entity_id in (select id from demo_target_students));
delete from app.family_members
where (entity_type = 'lead' and entity_id in (select id from demo_target_leads))
   or (entity_type = 'student' and entity_id in (select id from demo_target_students));

delete from app.lesson_homeworks
where id in (select id from demo_target_homeworks);
delete from app.lesson_participation
where student_id in (select id from demo_target_students)
   or lesson_id in (select id from demo_target_lessons);
delete from app.lesson_reminders where lesson_id in (select id from demo_target_lessons);
delete from app.subscriptions subscription
where subscription.student_id in (select id from demo_target_students)
   or nullif(to_jsonb(subscription) ->> 'conversion_lead_id', '')::uuid in (select id from demo_target_leads);
delete from app.payments where student_id in (select id from demo_target_students);
delete from app.expected_payments where student_id in (select id from demo_target_students);
delete from app.account_adjustments where student_id in (select id from demo_target_students);
delete from app.student_balances where student_id in (select id from demo_target_students);
delete from app.student_disciplines where student_id in (select id from demo_target_students);
delete from app.group_students where student_id in (select id from demo_target_students);

delete from app.lessons where id in (select id from demo_target_lessons);
delete from app.schedule_series where id in (select id from demo_target_series);

delete from app.user_crm_links
where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
  and entity_type in ('lead', 'student');
delete from app.students where id in (select id from demo_target_students);
delete from app.leads where id in (select id from demo_target_leads);

do $postcheck$
declare
  current_signature text;
begin
  if not exists (
    select 1 from app.users
    where id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and lower(email) = 'magic1@gmail.com'
      and role::text = (select value from demo_preserve_snapshot where key = 'user_role')
      and deleted_at is null
  ) then
    raise exception 'Post-check failed: auth account/role changed.';
  end if;
  if not exists (
    select 1 from app.profiles
    where id::text = (select value from demo_preserve_snapshot where key = 'profile_id')
      and user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
      and deleted_at is null
  ) then
    raise exception 'Post-check failed: profile changed.';
  end if;
  if (select count(*)::text from app.legal_consents
      where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid)
     <> (select value from demo_preserve_snapshot where key = 'legal_count') then
    raise exception 'Post-check failed: legal consents changed.';
  end if;

  select coalesce(md5(string_agg(
    id::text || ':' || platform || ':' || enabled::text || ':' || token_hash,
    ',' order by id
  )), 'EMPTY') into current_signature
  from app.notification_devices
  where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid;
  if current_signature <> (select value from demo_preserve_snapshot where key = 'device_signature') then
    raise exception 'Post-check failed: FCM devices changed.';
  end if;

  select coalesce(md5(string_agg(recipient.id::text, ',' order by recipient.id)), 'EMPTY')
  into current_signature
  from app.notification_recipients recipient
  where recipient.notification_id not in (select id from demo_target_notifications);
  if current_signature <> (select value from demo_preserve_snapshot where key = 'unrelated_notification_recipient_signature') then
    raise exception 'Post-check failed: unrelated notification recipients changed.';
  end if;

  select coalesce(md5(string_agg(delivery.id::text, ',' order by delivery.id)), 'EMPTY')
  into current_signature
  from app.notification_deliveries delivery
  where delivery.notification_id not in (select id from demo_target_notifications);
  if current_signature <> (select value from demo_preserve_snapshot where key = 'unrelated_notification_delivery_signature') then
    raise exception 'Post-check failed: unrelated notification deliveries changed.';
  end if;

  select coalesce(md5(string_agg(outbox.id::text, ',' order by outbox.id)), 'EMPTY')
  into current_signature
  from app.email_outbox outbox
  where not exists (
      select 1 from demo_target_notifications target
      where target.id::text = outbox.payload ->> 'notificationId'
    );
  if current_signature <> (select value from demo_preserve_snapshot where key = 'unrelated_notification_email_outbox_signature') then
    raise exception 'Post-check failed: unrelated notification email outbox changed.';
  end if;

  if exists (
       select 1 from app.notification_recipients recipient
       where recipient.notification_id in (select id from demo_target_notifications)
     ) or exists (
       select 1 from app.notification_deliveries delivery
       where delivery.notification_id in (select id from demo_target_notifications)
     ) or exists (
       select 1 from app.email_outbox outbox
       where exists (
           select 1 from demo_target_notifications target
           where target.id::text = outbox.payload ->> 'notificationId'
         )
     ) then
    raise exception 'Post-check failed: target demo notification graph is not clean.';
  end if;
  if exists (
    select 1
    from app.notifications notification
    where notification.id in (select id from demo_target_notifications)
  ) then
    raise exception 'Post-check failed: orphan target notification remains.';
  end if;

  if (select count(*)::text from app.audit_events)
     <> (select value from demo_preserve_snapshot where key = 'audit_count') then
    raise exception 'Post-check failed: immutable audit trail changed.';
  end if;

  select coalesce(md5(string_agg(
    id::text || ':' || user_id::text || ':' || role || ':' ||
      coalesce(joined_at::text, '') || ':' || coalesce(left_at::text, ''),
    ',' order by id
  )), 'EMPTY') into current_signature
  from app.chat_members
  where chat_id = '1c752e9f-b736-4e7e-8b48-84b5e462e4e5'::uuid;
  if current_signature <> (select value from demo_preserve_snapshot where key = 'admin_membership_signature') then
    raise exception 'Post-check failed: administration-chat memberships changed.';
  end if;

  if (select count(*)::text from app.chats
      where id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid)
     <> (select value from demo_preserve_snapshot where key = 'announcements_chat_count')
     or (select count(*)::text from app.messages
         where chat_id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid)
        <> (select value from demo_preserve_snapshot where key = 'announcements_message_count') then
    raise exception 'Post-check failed: shared announcements changed.';
  end if;

  select coalesce(md5(string_agg(
    id::text || ':' || user_id::text || ':' || role || ':' ||
      coalesce(joined_at::text, '') || ':' || coalesce(left_at::text, ''),
    ',' order by id
  )), 'EMPTY') into current_signature
  from app.chat_members
  where chat_id = 'b4799a54-4876-40bd-80c8-b9fff8228a93'::uuid;
  if current_signature <> (select value from demo_preserve_snapshot where key = 'announcements_membership_signature') then
    raise exception 'Post-check failed: announcements memberships changed.';
  end if;

  if exists (select 1 from app.leads where id in (select id from demo_target_leads))
     or exists (select 1 from app.students where id in (select id from demo_target_students))
     or exists (select 1 from app.lessons where id in (select id from demo_target_lessons))
     or exists (
       select 1 from app.user_crm_links
       where user_id = '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc'::uuid
         and entity_type in ('lead', 'student')
     ) then
    raise exception 'Post-check failed: target CRM graph is not empty.';
  end if;

  if exists (select 1 from app.messages where chat_id in (select id from demo_target_chats))
     or exists (select 1 from app.chat_inbox_state where chat_id in (select id from demo_target_chats))
     or exists (select 1 from app.chat_work_events where chat_id in (select id from demo_target_chats))
     or exists (
       select 1 from app.chats
       where id in (select id from demo_target_chats)
         and (last_message_id is not null or lead_id is not null or student_id is not null
           or branch_id is not null or assigned_to_user_id is not null or assigned_at is not null)
     ) then
    raise exception 'Post-check failed: private administration chat is not clean.';
  end if;
end
$postcheck$;

select 'RESET_OK',
       (select count(*) from demo_target_leads)::text,
       (select count(*) from demo_target_students)::text,
       (select count(*) from demo_target_lessons)::text,
       (select count(*) from demo_target_tasks)::text,
       'auth-profile-role-legal-fcm-chat-memberships-announcements-audit-preserved';

commit;
