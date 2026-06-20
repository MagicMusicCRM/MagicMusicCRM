-- server/db/migrations/0027_unified_branch_id.up.sql
-- Promote branch from custom_data->>'branchId' to a real branch_id FK across
-- the CRM entities. Column stays nullable; backfilled from existing data.

alter table app.leads    add column if not exists branch_id uuid references app.branches(id);
alter table app.students add column if not exists branch_id uuid references app.branches(id);
alter table app.payments add column if not exists branch_id uuid references app.branches(id);
alter table app.expenses add column if not exists branch_id uuid references app.branches(id);
alter table app.tasks    add column if not exists branch_id uuid references app.branches(id);
alter table app.chats    add column if not exists branch_id uuid references app.branches(id);
alter table app.chats    add column if not exists lead_id uuid references app.leads(id);
alter table app.chats    add column if not exists student_id uuid references app.students(id);

create index if not exists leads_branch_id_idx    on app.leads (branch_id)    where deleted_at is null;
create index if not exists students_branch_id_idx on app.students (branch_id) where deleted_at is null;
create index if not exists tasks_branch_id_idx     on app.tasks (branch_id)    where deleted_at is null;
create index if not exists expenses_branch_id_idx  on app.expenses (branch_id) where deleted_at is null;
create index if not exists payments_branch_id_idx  on app.payments (branch_id);
create index if not exists chats_branch_id_idx     on app.chats (branch_id);
create index if not exists chats_lead_id_idx       on app.chats (lead_id);
create index if not exists chats_student_id_idx    on app.chats (student_id);

-- Backfill students from custom_data, guarded so the cast/FK can never fail.
update app.students s
set branch_id = (coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id'))::uuid
where s.branch_id is null
  and coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id')
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and exists (
    select 1 from app.branches b
    where b.id = (coalesce(s.custom_data->>'branchId', s.custom_data->>'branch_id'))::uuid
  );

-- Backfill leads from custom_data (same guard).
update app.leads l
set branch_id = (coalesce(l.custom_data->>'branchId', l.custom_data->>'branch_id'))::uuid
where l.branch_id is null
  and coalesce(l.custom_data->>'branchId', l.custom_data->>'branch_id')
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and exists (
    select 1 from app.branches b
    where b.id = (coalesce(l.custom_data->>'branchId', l.custom_data->>'branch_id'))::uuid
  );

-- Backfill payments from their student (after students are backfilled).
update app.payments p
set branch_id = s.branch_id
from app.students s
where p.branch_id is null and p.student_id = s.id and s.branch_id is not null;

-- Backfill tasks from their linked student / lead entity.
update app.tasks t
set branch_id = s.branch_id
from app.students s
where t.branch_id is null and t.entity_type = 'student' and t.entity_id = s.id and s.branch_id is not null;

update app.tasks t
set branch_id = l.branch_id
from app.leads l
where t.branch_id is null and t.entity_type = 'lead' and t.entity_id = l.id and l.branch_id is not null;
