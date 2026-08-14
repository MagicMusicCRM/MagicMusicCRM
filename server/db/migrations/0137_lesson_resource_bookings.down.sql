drop trigger if exists lesson_participants_refresh_resource_bookings
  on app.lesson_snapshot_participants;
drop function if exists app.lesson_participants_refresh_resource_bookings_trigger();

drop trigger if exists lessons_refresh_resource_bookings on app.lessons;
drop function if exists app.lessons_refresh_resource_bookings_trigger();
drop function if exists app.refresh_lesson_resource_bookings(uuid);

drop table if exists app.lesson_resource_bookings;
