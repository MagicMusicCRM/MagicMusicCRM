-- v4 T3.2.3: versioned soft archive for the two CRM client aggregates.

alter table app.leads
  add column if not exists version bigint not null default 1;

alter table app.students
  add column if not exists version bigint not null default 1;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'leads_version_positive'
      and conrelid = 'app.leads'::regclass
  ) then
    alter table app.leads
      add constraint leads_version_positive check (version > 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'students_version_positive'
      and conrelid = 'app.students'::regclass
  ) then
    alter table app.students
      add constraint students_version_positive check (version > 0);
  end if;
end $$;

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'crm:lead', lead.id::text, lead.version
from app.leads lead
on conflict (aggregate_type, aggregate_id)
do update set
  version = greatest(app.aggregate_versions.version, excluded.version),
  updated_at = now();

insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
select 'crm:student', student.id::text, student.version
from app.students student
on conflict (aggregate_type, aggregate_id)
do update set
  version = greatest(app.aggregate_versions.version, excluded.version),
  updated_at = now();

create or replace function app.sync_client_aggregate_version()
returns trigger
language plpgsql
as $$
begin
  if TG_OP = 'DELETE' then
    delete from app.aggregate_versions
    where aggregate_type = TG_ARGV[0]
      and aggregate_id = old.id::text;
    return old;
  end if;

  insert into app.aggregate_versions (aggregate_type, aggregate_id, version)
  values (TG_ARGV[0], new.id::text, new.version)
  on conflict (aggregate_type, aggregate_id)
  do update set
    version = greatest(app.aggregate_versions.version, excluded.version),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists leads_sync_aggregate_version on app.leads;
create trigger leads_sync_aggregate_version
after insert or update of version or delete on app.leads
for each row execute function app.sync_client_aggregate_version('crm:lead');

drop trigger if exists students_sync_aggregate_version on app.students;
create trigger students_sync_aggregate_version
after insert or update of version or delete on app.students
for each row execute function app.sync_client_aggregate_version('crm:student');
