\set ON_ERROR_STOP on

begin isolation level repeatable read;

create temporary table reset_keep_users on commit drop as
select id, email, password_hash, role
from app.users
where deleted_at is null
  and (
    (role = 'system_admin' and lower(email) = 'kvazar2727@gmail.com')
    or (role = 'director' and lower(email) = 'yfnfkb5957@mail.ru')
  );

create temporary table reset_keep_profiles on commit drop as
select profile.id, profile.user_id
from app.profiles profile
join reset_keep_users account on account.id = profile.user_id
where profile.deleted_at is null;

create temporary table reset_keep_staff on commit drop as
select staff.id, staff.profile_id
from app.staff_members staff
join reset_keep_profiles profile on profile.id = staff.profile_id;

create temporary table reset_keep_custom_fields on commit drop as
select id
from app.client_custom_field_definitions
where not is_system
  and is_active
  and deleted_at is null
  and field_key <> 'hollihopId';

create temporary table reset_static_counts on commit drop as
select
  (select count(*) from app.capability_definitions) as capabilities,
  (select count(*) from app.role_packages) as role_packages,
  (select count(*) from app.role_package_capabilities) as package_capabilities,
  (select count(*) from app.legal_documents) as legal_documents;

do $$
begin
  if current_database() <> 'magiccrm'
      and current_setting('app.prelaunch_reset_test', true) is distinct from 'on' then
    raise exception 'unexpected database: %', current_database();
  end if;

  if (select id from public.app_schema_migrations order by id desc limit 1)
      <> '0132_app_registration_source' then
    raise exception 'prelaunch reset is pinned to migration 0132';
  end if;

  if (select count(*) from reset_keep_users) <> 2
      or (select count(*) from reset_keep_profiles) <> 2
      or (select count(*) from reset_keep_staff) <> 2 then
    raise exception 'retained account/profile/staff allowlist mismatch';
  end if;

  if (select count(*) from reset_keep_custom_fields) <> 40 then
    raise exception 'retained custom field allowlist mismatch';
  end if;

  if (select count(*) from app.users where role = 'system_admin' and deleted_at is null) <> 1 then
    raise exception 'unexpected active system administrator account';
  end if;

  if (select count(*) from app.chats
      where slug = 'announcements' and is_system and deleted_at is null) <> 1 then
    raise exception 'system announcements chat allowlist mismatch';
  end if;

  if (select count(*) from app.lead_sources
      where canonical_name = 'app' and display_name = 'Приложение'
        and is_system and is_active and deleted_at is null) <> 1 then
    raise exception 'system application source allowlist mismatch';
  end if;
end
$$;

lock table app.users in access exclusive mode;
lock table app.profiles in access exclusive mode;
lock table app.staff_members in access exclusive mode;
lock table app.chats in access exclusive mode;
lock table app.branches in access exclusive mode;
lock table app.leads in access exclusive mode;
lock table app.students in access exclusive mode;
lock table app.client_custom_field_definitions in access exclusive mode;
lock table app.lead_sources in access exclusive mode;

do $$
declare
  truncate_targets text;
begin
  select string_agg(format('app.%I', tablename), ', ' order by tablename)
  into truncate_targets
  from pg_tables
  where schemaname = 'app'
    and tablename <> all(array[
      'capability_definitions',
      'role_packages',
      'role_package_capabilities',
      'legal_documents',
      'legal_consents',
      'users',
      'profiles',
      'staff_members',
      'chats',
      'branches',
      'leads',
      'students',
      'lead_statuses',
      'client_custom_field_definitions',
      'lead_sources',
      'system_settings',
      'file_objects'
    ]::text[]);

  if truncate_targets is null then
    raise exception 'no reset tables were resolved';
  end if;

  execute 'truncate table ' || truncate_targets || ' restart identity cascade';
end
$$;

delete from app.legal_consents
where user_id not in (select id from reset_keep_users);

delete from app.chats
where not (slug = 'announcements' and is_system and deleted_at is null);

update app.chats
set title = 'Объявления',
    type = 'group',
    branch_id = null,
    lead_id = null,
    student_id = null,
    owner_user_id = null,
    assigned_to_user_id = null,
    assigned_at = null,
    avatar_file_id = null,
    last_message_id = null,
    deleted_at = null,
    updated_at = now()
where slug = 'announcements' and is_system;

delete from app.students;
delete from app.leads;
delete from app.branches;

delete from app.staff_members
where id not in (select id from reset_keep_staff);

delete from app.profiles
where id not in (select id from reset_keep_profiles);

delete from app.users
where id not in (select id from reset_keep_users);

update app.users
set role = case lower(email)
      when 'kvazar2727@gmail.com' then 'system_admin'::app.user_role
      when 'yfnfkb5957@mail.ru' then 'director'::app.user_role
    end,
    is_app_account = true,
    profile_completed = true,
    email_verified_at = coalesce(email_verified_at, now()),
    deleted_at = null,
    updated_at = now()
where id in (select id from reset_keep_users);

update app.profiles profile
set avatar_file_id = null,
    email_otp_2fa_enabled = false,
    custom_data = '{}'::jsonb,
    deleted_at = null,
    updated_at = now()
where profile.id in (select id from reset_keep_profiles);

update app.staff_members staff
set role = account.role::text,
    position = case account.role
      when 'system_admin' then 'Администратор системы'
      when 'director' then 'Директор'
      else staff.position
    end,
    status = 'working',
    custom_data = '{}'::jsonb,
    deleted_at = null,
    lifecycle_state = 'active',
    version = 1,
    offboarded_at = null,
    offboarded_by = null,
    offboard_reason = null,
    lifecycle_previous_status = null,
    lifecycle_account_was_active = null,
    lifecycle_snapshot = '{}'::jsonb,
    updated_at = now()
from app.profiles profile
join app.users account on account.id = profile.user_id
where staff.profile_id = profile.id
  and staff.id in (select id from reset_keep_staff);

insert into app.user_crm_links (
  user_id, entity_type, entity_id, matched_phone, link_source,
  confirmed_at, created_by
)
select account.id,
       'staff'::app.crm_entity_type,
       staff.id,
       profile.phone,
       'manual_email',
       now(),
       (select id from app.users where lower(email) = 'yfnfkb5957@mail.ru')
from app.users account
join app.profiles profile on profile.user_id = account.id
join app.staff_members staff on staff.profile_id = profile.id
where account.id in (select id from reset_keep_users);

insert into app.user_access_versions (user_id, version, changed_at)
select id, 1, now() from reset_keep_users;

insert into app.chat_members (chat_id, user_id, role)
select announcement.id,
       account.id,
       case when account.role in ('director', 'system_admin') then 'admin' else 'member' end
from app.chats announcement
cross join app.users account
where announcement.slug = 'announcements'
  and announcement.is_system
  and announcement.deleted_at is null;

delete from app.client_custom_field_definitions
where not is_system
  and (
    field_key = 'hollihopId'
    or not is_active
    or deleted_at is not null
  );

delete from app.lead_sources where not is_system;

update app.lead_sources
set canonical_name = 'app',
    display_name = 'Приложение',
    is_active = true,
    is_system = true,
    deleted_at = null,
    version = greatest(version, 1),
    updated_at = now()
where is_system;

delete from app.lead_statuses;
insert into app.lead_statuses (
  stage_key, name, color, sort_order, is_terminal, requires_reason
)
values ('new', 'Новые', 'cyan', 0, false, false);

insert into app.lead_loss_reasons (name, kind, sort_order)
values
  ('Дорого', 'lost', 1),
  ('Неудобное расписание', 'lost', 2),
  ('Нет нужного преподавателя', 'lost', 3),
  ('Выбрали конкурента', 'lost', 4),
  ('Не отвечает', 'lost', 5),
  ('Передумал', 'lost', 6),
  ('Дубль', 'lost', 7),
  ('Нецелевой лид', 'lost', 8),
  ('Филиал далеко', 'lost', 9),
  ('Пауза (семейные обстоятельства)', 'paused', 10),
  ('Другое', 'lost', 99);

insert into app.student_funnel_revisions (
  client_type, branch_id, version, patch, effective_snapshot, reason
)
values
  (
    'lead', null, 1,
    '{"stages":[{"key":"new","label":"Новые","style":"cyan","active":true,"terminal":false,"requiresReason":false,"allowedTransitions":[]}]}'::jsonb,
    '{"stages":[{"key":"new","label":"Новые","style":"cyan","active":true,"terminal":false,"requiresReason":false,"allowedTransitions":[]}]}'::jsonb,
    'Системная конфигурация чистого старта'
  ),
  (
    'student', null, 1,
    '{"stages":[{"key":"trial","label":"Пробные","style":"cyan","active":true,"allowedTransitions":["active","inactive"]},{"key":"active","label":"Активные","style":"green","active":true,"allowedTransitions":["paused","completed","inactive"]},{"key":"paused","label":"Пауза","style":"amber","active":true,"allowedTransitions":["active","completed","inactive"]},{"key":"completed","label":"Завершили обучение","style":"slate","active":true,"allowedTransitions":["active"]},{"key":"inactive","label":"Неактивные","style":"gray","active":true,"allowedTransitions":["active"]}]}'::jsonb,
    '{"stages":[{"key":"trial","label":"Пробные","style":"cyan","active":true,"allowedTransitions":["active","inactive"]},{"key":"active","label":"Активные","style":"green","active":true,"allowedTransitions":["paused","completed","inactive"]},{"key":"paused","label":"Пауза","style":"amber","active":true,"allowedTransitions":["active","completed","inactive"]},{"key":"completed","label":"Завершили обучение","style":"slate","active":true,"allowedTransitions":["active"]},{"key":"inactive","label":"Неактивные","style":"gray","active":true,"allowedTransitions":["active"]}]}'::jsonb,
    'Системная конфигурация чистого старта'
  );

delete from app.system_settings
where key not in ('crm_custom_fields', 'lead_board_unassigned_sort_order');

insert into app.system_settings (key, value, updated_by)
select 'crm_custom_fields',
       coalesce(jsonb_agg(
         jsonb_strip_nulls(jsonb_build_object(
           'entity', case definition.entity_type
             when 'lead' then 'leads'
             when 'student' then 'students'
           end,
           'key', definition.field_key,
           'label', definition.label,
           'type', definition.value_type,
           'required', definition.is_required,
           'options', case
             when jsonb_array_length(definition.options) > 0
               then definition.options
             else null
           end
         )) order by definition.entity_type, definition.sort_order,
           definition.label, definition.field_key
       ), '[]'::jsonb),
       (select id from app.users where lower(email) = 'yfnfkb5957@mail.ru')
from app.client_custom_field_definitions definition
where not definition.is_system
  and definition.is_active
  and definition.deleted_at is null
on conflict (key) do update
set value = excluded.value,
    updated_by = excluded.updated_by,
    updated_at = now();

insert into app.system_settings (key, value, updated_by)
values (
  'lead_board_unassigned_sort_order',
  '0'::jsonb,
  (select id from app.users where lower(email) = 'yfnfkb5957@mail.ru')
)
on conflict (key) do update
set value = excluded.value,
    updated_by = excluded.updated_by,
    updated_at = now();

delete from app.file_objects;

insert into app.audit_events (
  actor_user_id, action, entity_type, entity_id, metadata
)
select id,
       'system.prelaunch_reset_applied',
       'school',
       'primary',
       jsonb_build_object(
         'retainedSystemAdministrators', 1,
         'retainedDirectors', 1,
         'retainedCustomFields', 40,
         'removedFieldKey', 'hollihopId',
         'migration', '0132_app_registration_source'
       )
from app.users
where lower(email) = 'yfnfkb5957@mail.ru';

do $$
declare
  expected reset_static_counts%rowtype;
  table_row record;
  actual_count bigint;
  expected_count bigint;
begin
  select * into expected from reset_static_counts;

  if (select count(*) from app.capability_definitions) <> expected.capabilities
      or (select count(*) from app.role_packages) <> expected.role_packages
      or (select count(*) from app.role_package_capabilities) <> expected.package_capabilities
      or (select count(*) from app.legal_documents) <> expected.legal_documents then
    raise exception 'system registry or legal document baseline changed';
  end if;

  if (select count(*) from app.users) <> 2
      or (select count(*) from app.profiles) <> 2
      or (select count(*) from app.staff_members) <> 2
      or (select count(*) from app.chats) <> 1
      or (select count(*) from app.branches) <> 0
      or (select count(*) from app.leads) <> 0
      or (select count(*) from app.students) <> 0
      or (select count(*) from app.lead_statuses) <> 1
      or (select count(*) from app.lead_sources) <> 1
      or (select count(*) from app.file_objects) <> 0 then
    raise exception 'primary clean-state count mismatch';
  end if;

  if exists (
    select 1 from reset_keep_users before_reset
    join app.users after_reset on after_reset.id = before_reset.id
    where after_reset.password_hash is distinct from before_reset.password_hash
  ) then
    raise exception 'retained password hash changed';
  end if;

  if (select count(*) from app.client_custom_field_definitions
      where is_system and is_active and deleted_at is null) <> 10
      or (select count(*) from app.client_custom_field_definitions
      where not is_system and is_active and deleted_at is null) <> 40
      or exists (select 1 from app.client_custom_field_definitions
      where field_key = 'hollihopId') then
    raise exception 'client field clean-state mismatch';
  end if;

  if exists (
    select 1 from reset_keep_custom_fields retained
    left join app.client_custom_field_definitions definition
      on definition.id = retained.id
    where definition.id is null
  ) then
    raise exception 'a retained custom client field was deleted';
  end if;

  for table_row in
    select tablename
    from pg_tables
    where schemaname = 'app'
      and tablename <> all(array[
        'capability_definitions', 'role_packages',
        'role_package_capabilities', 'legal_documents', 'legal_consents',
        'users', 'profiles', 'staff_members', 'chats', 'branches', 'leads',
        'students', 'lead_statuses', 'client_custom_field_definitions',
        'lead_sources', 'system_settings', 'file_objects'
      ]::text[])
  loop
    execute format('select count(*) from app.%I', table_row.tablename)
      into actual_count;
    expected_count := case table_row.tablename
      when 'audit_events' then 1
      when 'chat_members' then 2
      when 'lead_loss_reasons' then 11
      when 'student_funnel_revisions' then 2
      when 'user_access_versions' then 2
      when 'user_crm_links' then 2
      else 0
    end;
    if actual_count <> expected_count then
      raise exception 'unexpected row count in app.%: expected %, got %',
        table_row.tablename, expected_count, actual_count;
    end if;
  end loop;
end
$$;

select 'RESET' as record_type,
       'OK' as status,
       (select count(*) from app.users) as users,
       (select count(*) from app.staff_members) as staff,
       (select count(*) from app.client_custom_field_definitions
         where is_system and is_active and deleted_at is null) as system_fields,
       (select count(*) from app.client_custom_field_definitions
         where not is_system and is_active and deleted_at is null) as custom_fields,
       (select count(*) from app.lead_sources) as sources,
       (select count(*) from app.chats) as chats;

commit;
