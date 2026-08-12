\set ON_ERROR_STOP on

begin isolation level repeatable read read only;

do $$
declare
  system_admin_count integer;
  director_count integer;
  retained_profile_count integer;
  retained_staff_count integer;
  announcement_count integer;
  app_source_count integer;
  system_field_count integer;
  retained_custom_field_count integer;
begin
  if current_database() <> 'magiccrm'
      and current_setting('app.prelaunch_reset_test', true) is distinct from 'on' then
    raise exception 'unexpected database: %', current_database();
  end if;

  if not exists (
    select 1
    from public.app_schema_migrations
    where id = '0132_app_registration_source'
  ) then
    raise exception 'migration 0132_app_registration_source is required';
  end if;

  if (select id from public.app_schema_migrations order by id desc limit 1)
      <> '0132_app_registration_source' then
    raise exception 'prelaunch reset is pinned to migration 0132';
  end if;

  select count(*) into system_admin_count
  from app.users
  where role = 'system_admin'
    and lower(email) = 'kvazar2727@gmail.com'
    and deleted_at is null
    and is_app_account
    and password_hash is not null;
  if system_admin_count <> 1 then
    raise exception 'expected exactly one retained system administrator';
  end if;

  if (select count(*) from app.users where role = 'system_admin' and deleted_at is null) <> 1 then
    raise exception 'unexpected active system administrator account';
  end if;

  select count(*) into director_count
  from app.users
  where role = 'director'
    and lower(email) = 'yfnfkb5957@mail.ru'
    and deleted_at is null
    and is_app_account
    and password_hash is not null;
  if director_count <> 1 then
    raise exception 'expected exactly one retained Natalia Nazarova director account';
  end if;

  select count(*) into retained_profile_count
  from app.users account
  join app.profiles profile
    on profile.user_id = account.id and profile.deleted_at is null
  where account.deleted_at is null
    and (
      (account.role = 'system_admin' and lower(account.email) = 'kvazar2727@gmail.com')
      or (account.role = 'director' and lower(account.email) = 'yfnfkb5957@mail.ru')
    );
  if retained_profile_count <> 2 then
    raise exception 'both retained accounts must have exactly one active profile';
  end if;

  select count(*) into retained_staff_count
  from app.users account
  join app.profiles profile
    on profile.user_id = account.id and profile.deleted_at is null
  join app.staff_members staff on staff.profile_id = profile.id
  where account.deleted_at is null
    and (
      (account.role = 'system_admin' and lower(account.email) = 'kvazar2727@gmail.com')
      or (account.role = 'director' and lower(account.email) = 'yfnfkb5957@mail.ru')
    );
  if retained_staff_count <> 2 then
    raise exception 'both retained accounts must have exactly one staff card';
  end if;

  if exists (
    select 1
    from app.users account
    join app.profiles profile on profile.user_id = account.id
    where lower(account.email) = 'yfnfkb5957@mail.ru'
      and profile.email_otp_2fa_enabled
  ) then
    raise exception 'the retained director must not require email OTP';
  end if;

  select count(*) into announcement_count
  from app.chats
  where slug = 'announcements'
    and is_system
    and deleted_at is null;
  if announcement_count <> 1 then
    raise exception 'expected exactly one active system announcements chat';
  end if;

  select count(*) into app_source_count
  from app.lead_sources
  where lower(btrim(canonical_name)) = 'app'
    and display_name = 'Приложение'
    and is_system
    and is_active
    and deleted_at is null;
  if app_source_count <> 1 then
    raise exception 'expected exactly one protected application source';
  end if;

  select count(*) into system_field_count
  from app.client_custom_field_definitions
  where is_system and is_active and deleted_at is null;
  if system_field_count <> 10 then
    raise exception 'expected 10 active system client fields, got %', system_field_count;
  end if;

  select count(*) into retained_custom_field_count
  from app.client_custom_field_definitions
  where not is_system
    and is_active
    and deleted_at is null
    and field_key <> 'hollihopId';
  if retained_custom_field_count <> 40 then
    raise exception 'expected 40 retained custom client fields, got %', retained_custom_field_count;
  end if;

  if (select count(*) from app.client_custom_field_definitions
      where field_key = 'hollihopId' and deleted_at is null) > 1 then
    raise exception 'expected at most one active HolliHop field before or after reset';
  end if;

  if (select count(*) from app.capability_definitions where active) = 0
      or (select count(*) from app.role_packages where active) <> 6
      or (select count(*) from app.role_package_capabilities) = 0 then
    raise exception 'capability registry is incomplete';
  end if;

  if (select count(*) from app.legal_documents where is_current) < 3 then
    raise exception 'current legal document baseline is incomplete';
  end if;
end
$$;

select 'PREFLIGHT' as record_type,
       'OK' as status,
       (select id from public.app_schema_migrations order by id desc limit 1) as migration;

select 'COUNTS' as record_type,
       (select count(*) from app.users) as users,
       (select count(*) from app.leads) as leads,
       (select count(*) from app.students) as students,
       (select count(*) from app.staff_members) as staff,
       (select count(*) from app.teachers) as teachers,
       (select count(*) from app.branches) as branches,
       (select count(*) from app.rooms) as rooms,
       (select count(*) from app.lessons) as lessons,
       (select count(*) from app.subscriptions) as subscriptions,
       (select count(*) from app.payments) as payments,
       (select count(*) from app.audit_events) as audit_events;

select 'FIELDS' as record_type,
       (select count(*) from app.client_custom_field_definitions
         where is_system and is_active and deleted_at is null) as system_fields,
       (select count(*) from app.client_custom_field_definitions
         where not is_system and is_active and deleted_at is null
           and field_key <> 'hollihopId') as retained_custom_fields,
       (select count(*) from app.client_custom_field_definitions
         where field_key = 'hollihopId') as hollihop_fields;

commit;
