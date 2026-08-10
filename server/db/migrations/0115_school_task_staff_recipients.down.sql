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
