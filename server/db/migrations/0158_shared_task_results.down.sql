do $$
begin
  if exists (
    select 1 from app.task_closes
    where result_code is not null
       or result_label is not null
       or comment is not null
       or planned_start_at is not null
       or planned_all_day is not null
       or was_overdue is not null
  ) then
    raise exception 'Refusing destructive rollback: task completion results exist';
  end if;
end $$;

drop index if exists app.task_closes_results_idx;
alter table app.task_closes
  drop constraint if exists task_closes_result_check,
  drop column if exists result_code,
  drop column if exists result_label,
  drop column if exists comment,
  drop column if exists planned_start_at,
  drop column if exists planned_all_day,
  drop column if exists was_overdue;
