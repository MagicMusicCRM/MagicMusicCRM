do $$
begin
  if exists (
    select 1 from app.lesson_snapshots where origin <> 'legacy_backfill'
  ) or exists (
    select 1 from app.lesson_transitions where origin <> 'legacy_backfill'
  ) or exists (
    select 1 from app.lesson_reservations
  ) then
    raise exception
      'Refusing destructive rollback: lesson lifecycle contains runtime facts';
  end if;
end $$;

drop trigger if exists lessons_sync_aggregate_version on app.lessons;
drop function if exists app.sync_lesson_aggregate_version();

delete from app.aggregate_versions
where aggregate_type = 'schedule:lesson';

drop trigger if exists lesson_reservations_guard_lifecycle
  on app.lesson_reservations;
drop function if exists app.guard_lesson_reservation_lifecycle();

drop trigger if exists lessons_sync_lifecycle on app.lessons;
drop function if exists app.sync_lesson_lifecycle();

drop trigger if exists lesson_transitions_immutable on app.lesson_transitions;
drop trigger if exists lesson_snapshots_immutable on app.lesson_snapshots;
drop function if exists app.reject_immutable_lesson_fact();

drop table if exists app.lesson_reservations;
drop table if exists app.lesson_transitions;
drop table if exists app.lesson_snapshots;

drop index if exists app.lessons_lifecycle_due_idx;
drop index if exists app.lessons_successor_reference_unique_idx;
drop index if exists app.lessons_one_successor_per_predecessor_idx;

alter table app.lessons
  drop constraint if exists lessons_successor_not_self,
  drop constraint if exists lessons_predecessor_not_self,
  drop constraint if exists lessons_version_positive,
  drop constraint if exists lessons_lifecycle_state_check,
  drop column if exists successor_id,
  drop column if exists predecessor_id,
  drop column if exists version,
  drop column if exists lifecycle_state;
