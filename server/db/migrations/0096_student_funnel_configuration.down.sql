do $$
begin
  if exists (
    select 1
    from app.student_funnel_revisions
    where not (branch_id is null and version = 1 and created_by is null)
  ) then
    raise exception 'cannot remove student funnel configuration while published revisions exist';
  end if;
end;
$$;

drop trigger if exists student_funnel_revision_immutable
  on app.student_funnel_revisions;
drop function if exists app.protect_student_funnel_revision();
drop table if exists app.student_funnel_revisions;
