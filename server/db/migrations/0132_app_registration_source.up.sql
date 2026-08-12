-- Keep one canonical acquisition source for clients originating in the app.

alter table app.lead_sources
  add column if not exists is_system boolean not null default false;

do $$
declare
  app_source_id uuid;
begin
  select source.id
  into app_source_id
  from app.lead_sources source
  where lower(btrim(source.canonical_name)) = 'app'
  order by (source.deleted_at is null) desc, source.created_at asc, source.id asc
  limit 1;

  if app_source_id is null then
    insert into app.lead_sources (
      canonical_name,
      display_name,
      is_active,
      is_system
    )
    values ('app', 'Приложение', true, true)
    returning id into app_source_id;
  else
    update app.lead_sources
    set canonical_name = 'app',
        display_name = 'Приложение',
        is_active = true,
        is_system = true,
        deleted_at = null,
        version = version + 1,
        updated_at = now()
    where id = app_source_id
      and (
        canonical_name is distinct from 'app'
        or display_name is distinct from 'Приложение'
        or is_active is distinct from true
        or is_system is distinct from true
        or deleted_at is not null
      );
  end if;

  update app.lead_sources
  set is_system = false,
      version = version + 1,
      updated_at = now()
  where id <> app_source_id
    and is_system;

  update app.leads lead
  set source_id = app_source_id,
      source = 'Приложение',
      updated_at = now()
  where lead.deleted_at is null
    and lead.source_id is null
    and (
      lower(btrim(coalesce(lead.source, ''))) in (
        'app',
        'приложение',
        'через приложение'
      )
      or exists (
        select 1
        from app.user_crm_links link
        join app.users account
          on account.id = link.user_id
         and account.deleted_at is null
         and account.is_app_account
         and account.role = 'client'
        where link.entity_type = 'lead'
          and link.entity_id = lead.id
          and link.deleted_at is null
      )
    );

  update app.leads lead
  set source = 'Приложение',
      updated_at = now()
  where lead.source_id = app_source_id
    and lead.source is distinct from 'Приложение';

  update app.students student
  set source_id = coalesce(
        (
          select lead.source_id
          from app.leads lead
          where lead.id = student.lead_id
            and lead.deleted_at is null
        ),
        app_source_id
      ),
      updated_at = now()
  where (
      exists (
        select 1
        from app.user_crm_links link
        join app.users account
          on account.id = link.user_id
         and account.deleted_at is null
         and account.is_app_account
         and account.role = 'client'
        where link.entity_type = 'student'
          and link.entity_id = student.id
          and link.deleted_at is null
      )
      or exists (
        select 1
        from app.profiles profile
        join app.users account
          on account.id = profile.user_id
         and account.deleted_at is null
         and account.is_app_account
         and account.role = 'client'
        where profile.id = student.profile_id
          and profile.deleted_at is null
      )
    )
    and student.deleted_at is null
    and student.source_id is null;
end
$$;

create or replace function app.guard_system_lead_source()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'TRUNCATE' then
    raise exception 'lead sources cannot be truncated while the system source exists';
  end if;

  if tg_op = 'DELETE' then
    if old.is_system then
      raise exception 'system lead source cannot be deleted';
    end if;
    return old;
  end if;

  if new.is_system and (
    lower(btrim(new.canonical_name)) <> 'app'
    or new.display_name <> 'Приложение'
    or not new.is_active
    or new.deleted_at is not null
  ) then
    raise exception 'invalid system lead source';
  end if;

  if tg_op = 'UPDATE' and old.is_system and not new.is_system then
    raise exception 'system lead source cannot be demoted';
  end if;

  return new;
end;
$$;

drop trigger if exists lead_sources_system_guard on app.lead_sources;
create trigger lead_sources_system_guard
before insert or update or delete on app.lead_sources
for each row execute function app.guard_system_lead_source();

drop trigger if exists lead_sources_truncate_guard on app.lead_sources;
create trigger lead_sources_truncate_guard
before truncate on app.lead_sources
for each statement execute function app.guard_system_lead_source();
