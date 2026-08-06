-- Stage 6: finish the lossless cutover from app.tasks to app.shared_tasks.

alter table app.shared_tasks
  add column if not exists priority text not null default 'medium';
alter table app.shared_tasks
  add column if not exists branch_id uuid references app.branches(id) on delete set null;

alter table app.shared_tasks
  drop constraint if exists shared_tasks_priority_check;
alter table app.shared_tasks
  add constraint shared_tasks_priority_check
  check (priority in ('low', 'medium', 'high'));

create index if not exists shared_tasks_priority_idx
  on app.shared_tasks (priority, state, start_at)
  where deleted_at is null;
create index if not exists shared_tasks_branch_idx
  on app.shared_tasks (branch_id, state, start_at)
  where deleted_at is null;

-- Resolution audits are immutable historical facts. Their selector snapshot
-- already carries the audience identity, so a mutable task audience cannot
-- keep an on-delete-restrict foreign key without making every edit fail.
alter table app.task_audience_resolution_audits
  drop constraint if exists task_audience_resolution_audits_matched_audience_id_fkey;

-- 0092 records a lossless legacy link. Use it to carry the remaining field
-- that did not exist in the first shared-task schema.
update app.shared_tasks shared
set priority = source.priority,
    branch_id = source.branch_id
from (
  select link.shared_task_id, min(task.priority) as priority,
    min(task.branch_id::text)::uuid as branch_id
  from app.shared_task_legacy_links link
  join app.tasks task on task.id = link.legacy_task_id
  group by link.shared_task_id
) source
where shared.id = source.shared_task_id;

-- Old unassigned tasks were manager-visible. They must not disappear merely
-- because the canonical model requires an audience. Prefer their known branch;
-- use the existing school audience only when the old row had no branch.
insert into app.task_audiences (task_id, audience_type, target_id)
select distinct shared.id, 'branch', task.branch_id
from app.shared_tasks shared
join app.shared_task_legacy_links link on link.shared_task_id = shared.id
join app.tasks task on task.id = link.legacy_task_id
where shared.origin = 'legacy_backfill'
  and task.branch_id is not null
  and not exists (
    select 1 from app.task_audiences audience where audience.task_id = shared.id
  )
on conflict do nothing;

insert into app.task_audiences (task_id, audience_type, target_id)
select shared.id, 'allBranches', null
from app.shared_tasks shared
where shared.origin = 'legacy_backfill'
  and not exists (
    select 1 from app.task_audiences audience where audience.task_id = shared.id
  )
on conflict do nothing;

-- Preserve the old field-by-field history in the canonical history stream.
-- Deterministic ids make the backfill idempotent during migration rehearsal.
insert into app.audit_events (
  id, actor_user_id, action, entity_type, entity_id, metadata,
  before_ref, after_ref, created_at
)
select (
    substr(md5('shared-task-history:' || history.id::text), 1, 8) || '-' ||
    substr(md5('shared-task-history:' || history.id::text), 9, 4) || '-4' ||
    substr(md5('shared-task-history:' || history.id::text), 14, 3) || '-a' ||
    substr(md5('shared-task-history:' || history.id::text), 18, 3) || '-' ||
    substr(md5('shared-task-history:' || history.id::text), 21, 12)
  )::uuid,
  history.changed_by,
  'workflow.shared_task_legacy_' || history.field,
  'shared_task',
  link.shared_task_id::text,
  jsonb_build_object(
    'legacyTaskId', history.task_id,
    'legacyHistoryId', history.id,
    'source', history.source,
    'oldUserId', history.old_user_id,
    'newUserId', history.new_user_id
  ),
  jsonb_build_object('field', history.field, 'value', history.old_value),
  jsonb_build_object('field', history.field, 'value', history.new_value),
  history.changed_at
from app.task_history history
join app.shared_task_legacy_links link on link.legacy_task_id = history.task_id
on conflict (id) do nothing;

-- Dynamic recipient projection for dashboards, badges and linked-record reads.
-- Mutation and audited resolution remain owned by SharedTaskRepository.
create or replace view app.shared_task_recipients as
select distinct resolved.task_id, resolved.user_id
from (
  select audience.task_id, audience.target_id as user_id
  from app.task_audiences audience
  join app.users actor
    on audience.audience_type = 'user'
   and actor.id = audience.target_id
   and actor.deleted_at is null

  union all

  select audience.task_id, link.user_id
  from app.task_audiences audience
  join app.staff_branch_assignments assignment
    on audience.audience_type = 'branch'
   and assignment.branch_id = audience.target_id
   and assignment.deleted_at is null
  join app.staff_members staff
    on staff.id = assignment.staff_member_id and staff.deleted_at is null
  join app.user_crm_links link
    on link.entity_type::text = 'staff'
   and link.entity_id = staff.id
   and link.deleted_at is null
  join app.users actor on actor.id = link.user_id and actor.deleted_at is null

  union all

  select audience.task_id, link.user_id
  from app.task_audiences audience
  join app.teacher_branches assignment
    on audience.audience_type = 'branch'
   and assignment.branch_id = audience.target_id
   and assignment.active_from <= now()
   and (assignment.active_until is null or assignment.active_until > now())
  join app.teachers teacher
    on teacher.id = assignment.teacher_id and teacher.deleted_at is null
  join app.user_crm_links link
    on link.entity_type::text = 'teacher'
   and link.entity_id = teacher.id
   and link.deleted_at is null
  join app.users actor on actor.id = link.user_id and actor.deleted_at is null

  union all

  select audience.task_id, actor.id
  from app.task_audiences audience
  join app.users actor
    on audience.audience_type = 'allBranches'
   and actor.deleted_at is null
   and actor.role::text = any(
     array['teacher', 'manager', 'director', 'system_admin']::text[]
   )

  union all

  select audience.task_id, actor.id
  from app.task_audiences audience
  join app.users actor
    on audience.audience_type = 'branch'
   and actor.deleted_at is null
   and actor.role::text = any(array['director', 'system_admin']::text[])
) resolved
where resolved.user_id is not null;

-- One visibility projection for task list, dashboard counters and linked cards.
-- Recipients remain the delivery source; management additionally sees work in
-- its operational branch scope, while Director/system_admin see the school.
create or replace view app.shared_task_visibility as
with user_branches as (
  select link.user_id, assignment.branch_id
  from app.user_crm_links link
  join app.staff_members staff
    on link.entity_type::text = 'staff'
   and link.entity_id = staff.id
   and link.deleted_at is null
   and staff.deleted_at is null
  join app.staff_branch_assignments assignment
    on assignment.staff_member_id = staff.id
   and assignment.deleted_at is null

  union

  select link.user_id, assignment.branch_id
  from app.user_crm_links link
  join app.teachers teacher
    on link.entity_type::text = 'teacher'
   and link.entity_id = teacher.id
   and link.deleted_at is null
   and teacher.deleted_at is null
  join app.teacher_branches assignment
    on assignment.teacher_id = teacher.id
   and assignment.active_from <= now()
   and (assignment.active_until is null or assignment.active_until > now())
), task_branches as (
  select task.id as task_id, task.branch_id
  from app.shared_tasks task
  where task.branch_id is not null

  union

  select audience.task_id, audience.target_id as branch_id
  from app.task_audiences audience
  where audience.audience_type = 'branch'

  union

  select audience.task_id, recipient.branch_id
  from app.task_audiences audience
  join user_branches recipient on recipient.user_id = audience.target_id
  where audience.audience_type = 'user'

  union

  select task.id, student.branch_id
  from app.shared_tasks task
  join app.students student
    on task.linked_entity_type = 'student'
   and task.linked_entity_id = student.id
   and student.deleted_at is null

  union

  select task.id, lead.branch_id
  from app.shared_tasks task
  join app.leads lead
    on task.linked_entity_type = 'lead'
   and task.linked_entity_id = lead.id
   and lead.deleted_at is null

  union

  select task.id, lesson.branch_id
  from app.shared_tasks task
  join app.lessons lesson
    on task.linked_entity_type = 'lesson'
   and task.linked_entity_id = lesson.id
   and lesson.deleted_at is null

  union

  select task.id, student.branch_id
  from app.shared_tasks task
  join app.students student
    on task.linked_entity_type = 'profile'
   and task.linked_entity_id = student.profile_id
   and student.deleted_at is null
)
select recipient.task_id, recipient.user_id, 'mine'::text as scope_kind
from app.shared_task_recipients recipient

union

select audience.task_id, actor.id, 'school'::text
from app.task_audiences audience
join app.users actor
  on actor.deleted_at is null
 and actor.role::text = any(array['manager', 'director', 'system_admin']::text[])
where audience.audience_type = 'allBranches'

union

select branch.task_id, manager.user_id, 'branch'::text
from task_branches branch
join user_branches manager on manager.branch_id = branch.branch_id
join app.users actor
  on actor.id = manager.user_id
 and actor.deleted_at is null
 and actor.role::text = 'manager'

union

select task.id, actor.id, 'global'::text
from app.shared_tasks task
join app.users actor
  on actor.deleted_at is null
 and actor.role::text = any(array['director', 'system_admin']::text[]);

-- Read-only compatibility shape for internal projections that still need the
-- old column names. Its source of truth is exclusively app.shared_tasks.
create or replace view app.canonical_tasks as
select
  task.id,
  task.linked_entity_type as entity_type,
  task.linked_entity_id as entity_id,
  (
    select audience.target_id
    from app.task_audiences audience
    where audience.task_id = task.id and audience.audience_type = 'user'
    order by audience.id
    limit 1
  ) as assigned_to,
  task.title,
  task.body as description,
  case when task.state = 'closed' then 'completed' else 'open' end as status,
  task.priority,
  task.branch_id,
  task.start_at as due_at,
  task.all_day as due_all_day,
  task.created_by,
  task.created_at,
  task.updated_at,
  task.deleted_at
from app.shared_tasks task;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.shared_task_recipients, app.shared_task_visibility,
      app.canonical_tasks to magiccrm_app;
    revoke insert, update, delete on app.tasks, app.task_history, app.task_reminders
      from magiccrm_app;
  end if;
end $$;
