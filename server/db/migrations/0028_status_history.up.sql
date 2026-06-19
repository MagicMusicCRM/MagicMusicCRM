-- server/db/migrations/0028_status_history.up.sql
-- Event log of lead status + ownership transitions and student status transitions.

create table if not exists app.lead_status_history (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references app.leads(id) on delete cascade,
  old_status_id uuid references app.lead_statuses(id),
  new_status_id uuid references app.lead_statuses(id),
  old_owner_id uuid references app.users(id),
  new_owner_id uuid references app.users(id),
  changed_by uuid references app.users(id),
  changed_at timestamptz not null default now(),
  reason_id uuid references app.lead_loss_reasons(id),
  comment text,
  branch_id uuid references app.branches(id),
  source_snapshot text
);
create index if not exists lead_status_history_lead_idx
  on app.lead_status_history (lead_id, changed_at desc);

create table if not exists app.student_status_history (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  status text not null,
  branch_id uuid references app.branches(id),
  changed_at timestamptz not null default now()
);
create index if not exists student_status_history_student_idx
  on app.student_status_history (student_id, changed_at desc);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select, insert, update, delete on app.lead_status_history to magiccrm_app;
    grant select, insert, update, delete on app.student_status_history to magiccrm_app;
  end if;
end $$;
