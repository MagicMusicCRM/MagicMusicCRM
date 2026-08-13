-- Canonical CRM identity. Lead and Student remain lifecycle state projections;
-- every cross-domain identity is anchored by one stable clients.id.

create table if not exists app.clients (
  id uuid primary key,
  lifecycle_state text not null,
  first_name text,
  last_name text,
  phone text,
  phone_normalized text,
  email text,
  profile_id uuid references app.profiles(id) on delete set null,
  source_id uuid references app.lead_sources(id) on delete set null,
  branch_id uuid references app.branches(id) on delete set null,
  assigned_to uuid references app.users(id) on delete set null,
  created_by uuid references app.users(id) on delete set null,
  blacklisted boolean not null default false,
  blacklist_reason text,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint clients_lifecycle_state_check
    check (lifecycle_state in ('lead', 'student'))
);

alter table app.leads add column if not exists client_id uuid;
alter table app.students add column if not exists client_id uuid;

-- Lead UUID is the canonical UUID for an already linked Lead/Student pair.
insert into app.clients (
  id, lifecycle_state, first_name, last_name, phone, phone_normalized, email,
  source_id, branch_id, assigned_to, created_by, blacklisted,
  blacklist_reason, version, created_at, updated_at, deleted_at
)
select
  lead.id,
  case when student.id is null then 'lead' else 'student' end,
  coalesce(profile.first_name, lead.first_name),
  coalesce(profile.last_name, lead.last_name),
  coalesce(profile.phone, lead.phone),
  coalesce(profile.phone_normalized, lead.phone_normalized),
  lead.email,
  coalesce(student.source_id, lead.source_id),
  coalesce(student.branch_id, lead.branch_id),
  lead.assigned_to,
  lead.created_by,
  lead.blacklisted or coalesce(student.blacklisted, false),
  coalesce(student.blacklist_reason, lead.blacklist_reason),
  greatest(lead.version, coalesce(student.version, 1)),
  least(lead.created_at, coalesce(student.created_at, lead.created_at)),
  greatest(lead.updated_at, coalesce(student.updated_at, lead.updated_at)),
  case when student.id is null then lead.deleted_at else student.deleted_at end
from app.leads lead
left join lateral (
  select candidate.*
  from app.students candidate
  left join app.client_conversion_links conversion
    on conversion.student_id = candidate.id
  where candidate.lead_id = lead.id or conversion.lead_id = lead.id
  order by (candidate.deleted_at is null) desc, candidate.created_at desc
  limit 1
) student on true
left join app.profiles profile on profile.id = student.profile_id
on conflict (id) do nothing;

insert into app.clients (
  id, lifecycle_state, first_name, last_name, phone, phone_normalized, email,
  profile_id, source_id, branch_id, blacklisted, blacklist_reason, version,
  created_at, updated_at, deleted_at
)
select
  student.id, 'student', profile.first_name, profile.last_name, profile.phone,
  profile.phone_normalized, app_user.email, student.profile_id,
  student.source_id, student.branch_id, student.blacklisted,
  student.blacklist_reason, student.version, student.created_at,
  student.updated_at, student.deleted_at
from app.students student
left join app.profiles profile on profile.id = student.profile_id
left join app.users app_user on app_user.id = profile.user_id
where not exists (
  select 1
  from app.leads lead
  left join app.client_conversion_links conversion
    on conversion.lead_id = lead.id
  where lead.id = student.lead_id or conversion.student_id = student.id
)
on conflict (id) do nothing;

update app.leads set client_id = id where client_id is null;

update app.students student
set client_id = coalesce((
  select lead.client_id
  from app.leads lead
  left join app.client_conversion_links conversion
    on conversion.lead_id = lead.id
  where lead.id = student.lead_id or conversion.student_id = student.id
  order by (lead.deleted_at is null) desc, lead.created_at desc
  limit 1
), student.id)
where student.client_id is null;

alter table app.leads
  alter column client_id set not null,
  add constraint leads_client_id_unique unique (client_id),
  add constraint leads_client_id_fk foreign key (client_id)
    references app.clients(id) on delete restrict;

alter table app.students
  alter column client_id set not null,
  add constraint students_client_id_unique unique (client_id),
  add constraint students_client_id_fk foreign key (client_id)
    references app.clients(id) on delete restrict;

create index if not exists clients_lifecycle_active_idx
  on app.clients (lifecycle_state, updated_at desc)
  where deleted_at is null;
create index if not exists clients_branch_active_idx
  on app.clients (branch_id, lifecycle_state, updated_at desc)
  where deleted_at is null;
create index if not exists clients_phone_active_idx
  on app.clients (phone_normalized)
  where deleted_at is null and phone_normalized is not null;

create or replace function app.resolve_client_id(
  requested_entity_type text,
  requested_entity_id uuid
)
returns uuid stable language sql as $$
  select case requested_entity_type
    when 'lead' then (
      select lead.client_id from app.leads lead where lead.id = requested_entity_id
    )
    when 'student' then (
      select student.client_id from app.students student where student.id = requested_entity_id
    )
  end;
$$;

create or replace function app.ensure_client_custom_value_identity()
returns trigger language plpgsql as $$
begin
  new.client_id := coalesce(
    new.client_id,
    app.resolve_client_id(new.entity_type, new.entity_id)
  );
  if new.client_id is null then
    raise exception using
      errcode = '23503',
      message = 'custom field value references an unknown Client';
  end if;
  return new;
end;
$$;

-- Custom values follow canonical Client identity. Legacy entity columns remain
-- as compatibility metadata while consumers migrate.
alter table app.client_custom_field_values add column if not exists client_id uuid;

update app.client_custom_field_values value
set client_id = case value.entity_type
  when 'lead' then (select lead.client_id from app.leads lead where lead.id = value.entity_id)
  when 'student' then (select student.client_id from app.students student where student.id = value.entity_id)
end;

do $$
begin
  if exists (
    select 1
    from app.client_custom_field_values
    where client_id is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'canonical client migration found orphan custom field values';
  end if;
  if exists (
    select 1
    from app.client_custom_field_values
    group by definition_id, client_id
    having count(*) > 1 and count(distinct jsonb_build_object(
      'text', value_text, 'number', value_number, 'boolean', value_boolean,
      'date', value_date, 'json', value_json
    )) > 1
  ) then
    raise exception using
      errcode = '23514',
      message = 'canonical client migration found conflicting field values';
  end if;
end $$;

delete from app.client_custom_field_values duplicate
using app.client_custom_field_values survivor
where duplicate.definition_id = survivor.definition_id
  and duplicate.client_id = survivor.client_id
  and duplicate.id <> survivor.id
  and (
    (survivor.entity_type = 'student' and duplicate.entity_type = 'lead')
    or (survivor.entity_type = duplicate.entity_type and survivor.id < duplicate.id)
  );

alter table app.client_custom_field_values
  alter column client_id set not null,
  add constraint client_custom_field_values_client_fk foreign key (client_id)
    references app.clients(id) on delete restrict,
  add constraint client_custom_field_value_client_unique
    unique (definition_id, client_id);

drop trigger if exists client_custom_values_ensure_client
  on app.client_custom_field_values;
create trigger client_custom_values_ensure_client
before insert or update of entity_type, entity_id, client_id
on app.client_custom_field_values
for each row execute function app.ensure_client_custom_value_identity();

create or replace function app.ensure_canonical_client_identity()
returns trigger language plpgsql as $$
declare
  resolved_client_id uuid;
begin
  if tg_table_name = 'leads' then
    resolved_client_id := coalesce(new.client_id, new.id);
  else
    if new.lead_id is not null then
      select lead.client_id into resolved_client_id
      from app.leads lead where lead.id = new.lead_id;
    end if;
    resolved_client_id := coalesce(new.client_id, resolved_client_id, new.id);
  end if;
  new.client_id := resolved_client_id;
  insert into app.clients (id, lifecycle_state)
  values (resolved_client_id,
    case when tg_table_name = 'students' then 'student' else 'lead' end)
  on conflict (id) do update
  set lifecycle_state = case
    when excluded.lifecycle_state = 'student' then 'student'
    else app.clients.lifecycle_state
  end,
  updated_at = now();
  return new;
end;
$$;

create or replace function app.refresh_canonical_client_identity(target_id uuid)
returns void language plpgsql as $$
begin
  update app.clients client
  set lifecycle_state = case when student.id is not null then 'student' else 'lead' end,
      first_name = coalesce(profile.first_name, lead.first_name),
      last_name = coalesce(profile.last_name, lead.last_name),
      phone = coalesce(profile.phone, lead.phone),
      phone_normalized = coalesce(profile.phone_normalized, lead.phone_normalized),
      email = coalesce(nullif(lead.email, ''), nullif(app_user.email, '')),
      profile_id = student.profile_id,
      source_id = coalesce(student.source_id, lead.source_id),
      branch_id = coalesce(student.branch_id, lead.branch_id),
      assigned_to = lead.assigned_to,
      created_by = lead.created_by,
      blacklisted = coalesce(student.blacklisted, false)
        or coalesce(lead.blacklisted, false),
      blacklist_reason = coalesce(student.blacklist_reason, lead.blacklist_reason),
      version = greatest(coalesce(student.version, 1), coalesce(lead.version, 1)),
      created_at = least(
        coalesce(lead.created_at, student.created_at),
        coalesce(student.created_at, lead.created_at)
      ),
      updated_at = greatest(
        coalesce(lead.updated_at, student.updated_at),
        coalesce(student.updated_at, lead.updated_at)
      ),
      deleted_at = case when student.id is not null
        then student.deleted_at else lead.deleted_at end
  from app.clients anchor
  left join app.leads lead on lead.client_id = anchor.id
  left join app.students student on student.client_id = anchor.id
  left join app.profiles profile on profile.id = student.profile_id
  left join app.users app_user on app_user.id = profile.user_id
  where anchor.id = target_id and client.id = anchor.id;
end;
$$;

create or replace function app.refresh_canonical_client_identity_trigger()
returns trigger language plpgsql as $$
begin
  perform app.refresh_canonical_client_identity(coalesce(new.client_id, old.client_id));
  return coalesce(new, old);
end;
$$;

create or replace function app.refresh_canonical_client_from_profile_trigger()
returns trigger language plpgsql as $$
declare
  target_client_id uuid;
begin
  select student.client_id into target_client_id
  from app.students student
  where student.profile_id = coalesce(new.id, old.id)
  limit 1;
  if target_client_id is not null then
    perform app.refresh_canonical_client_identity(target_client_id);
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function app.refresh_canonical_client_from_user_trigger()
returns trigger language plpgsql as $$
declare
  target_client_id uuid;
begin
  select student.client_id into target_client_id
  from app.profiles profile
  join app.students student on student.profile_id = profile.id
  where profile.user_id = coalesce(new.id, old.id)
  limit 1;
  if target_client_id is not null then
    perform app.refresh_canonical_client_identity(target_client_id);
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists leads_ensure_canonical_client on app.leads;
create trigger leads_ensure_canonical_client
before insert on app.leads
for each row execute function app.ensure_canonical_client_identity();
drop trigger if exists students_ensure_canonical_client on app.students;
create trigger students_ensure_canonical_client
before insert on app.students
for each row execute function app.ensure_canonical_client_identity();

drop trigger if exists leads_refresh_canonical_client on app.leads;
create trigger leads_refresh_canonical_client
after insert or update on app.leads
for each row execute function app.refresh_canonical_client_identity_trigger();
drop trigger if exists students_refresh_canonical_client on app.students;
create trigger students_refresh_canonical_client
after insert or update on app.students
for each row execute function app.refresh_canonical_client_identity_trigger();

drop trigger if exists profiles_refresh_canonical_client on app.profiles;
create trigger profiles_refresh_canonical_client
after update of first_name, last_name, phone, phone_normalized, deleted_at
on app.profiles
for each row execute function app.refresh_canonical_client_from_profile_trigger();

drop trigger if exists users_refresh_canonical_client on app.users;
create trigger users_refresh_canonical_client
after update of email, deleted_at on app.users
for each row execute function app.refresh_canonical_client_from_user_trigger();

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update on app.clients to magiccrm_app;
    grant execute on function app.refresh_canonical_client_identity(uuid)
      to magiccrm_app;
    grant execute on function app.resolve_client_id(text, uuid)
      to magiccrm_app;
    grant execute on function app.ensure_client_custom_value_identity()
      to magiccrm_app;
    grant execute on function app.refresh_canonical_client_from_profile_trigger()
      to magiccrm_app;
    grant execute on function app.refresh_canonical_client_from_user_trigger()
      to magiccrm_app;
  end if;
end $$;
