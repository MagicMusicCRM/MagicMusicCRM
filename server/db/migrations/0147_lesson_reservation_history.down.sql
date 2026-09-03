-- Never discard reservation history to recreate the legacy unique index.
do $$ begin
  if exists (
    select 1 from app.lesson_reservations
    group by lesson_id, subscription_id having count(*) > 1
  ) then
    raise exception 'Cannot restore the legacy reservation index while rebooking history exists';
  end if;
end $$;

drop index if exists app.lesson_reservations_lesson_subscription_idx;
create unique index lesson_reservations_lesson_subscription_idx
  on app.lesson_reservations (lesson_id, subscription_id);
drop index if exists app.lesson_reservations_history_idx;
