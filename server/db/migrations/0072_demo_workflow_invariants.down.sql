drop index if exists app.notification_devices_enabled_token_unique_idx;

drop index if exists app.subscriptions_conversion_lead_unique_idx;

alter table app.subscriptions
  drop column if exists conversion_lead_id;

drop index if exists app.lesson_homeworks_lead_idx;

alter table app.lesson_homeworks
  drop constraint if exists lesson_homeworks_student_or_lead_check;

-- Refuse a destructive rollback if unconverted lead homework still exists.
do $$
begin
  if exists (
    select 1 from app.lesson_homeworks where student_id is null
  ) then
    raise exception
      'Cannot roll back 0072: lead-bound homework must be converted first';
  end if;
end
$$;

alter table app.lesson_homeworks
  alter column student_id set not null,
  drop column if exists lead_id;
