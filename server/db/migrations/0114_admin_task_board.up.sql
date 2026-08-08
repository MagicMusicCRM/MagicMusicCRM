update app.role_package_capabilities entry
set effect = 'allow'
from app.role_packages package
where entry.package_id = package.id
  and package.active
  and package.role = 'admin'
  and entry.capability_key = 'workflow.task.read';

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
     array['teacher', 'admin', 'manager', 'director', 'system_admin']::text[]
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

select branch.task_id, staff.user_id, 'branch'::text
from task_branches branch
join user_branches staff on staff.branch_id = branch.branch_id
join app.users actor
  on actor.id = staff.user_id
 and actor.deleted_at is null
 and actor.role::text = any(array['admin', 'manager']::text[])

union

select task.id, actor.id, 'global'::text
from app.shared_tasks task
join app.users actor
  on actor.deleted_at is null
 and actor.role::text = any(array['director', 'system_admin']::text[]);

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant select on app.shared_task_recipients, app.shared_task_visibility
      to magiccrm_app;
  end if;
end $$;
