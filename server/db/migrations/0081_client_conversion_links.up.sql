create table if not exists app.client_conversion_links (
  lead_id uuid primary key references app.leads(id) on delete restrict,
  student_id uuid not null unique references app.students(id) on delete restrict,
  converted_by uuid references app.users(id) on delete set null,
  converted_at timestamptz not null default now()
);

insert into app.client_conversion_links (lead_id, student_id, converted_at)
select distinct on (student.lead_id)
  student.lead_id,
  student.id,
  student.created_at
from app.students student
where student.lead_id is not null
order by
  student.lead_id,
  (student.deleted_at is null) desc,
  student.created_at asc,
  student.id asc
on conflict do nothing;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert on app.client_conversion_links to magiccrm_app;
  end if;
end $$;
