-- ============================================================================
-- Hard-delete the duplicate rooms and lessons that the room-merge soft-deleted
-- on 2026-06-18 ~18:00 UTC. Pre-existing soft-deletes (2026-06-12) are left
-- untouched. A full data backup of rooms/lessons/groups was taken beforehand.
--   psql -v dryrun=1 -f purge_merged_duplicates.sql   (verify + rollback)
--   psql -v dryrun=0 -f purge_merged_duplicates.sql   (commit)
-- ============================================================================

\set ON_ERROR_STOP on
begin;

-- Scope: exactly the merge cluster.
create temp table purge_lessons on commit drop as
  select id from app.lessons
  where deleted_at >= timestamptz '2026-06-18 17:00:00+00'
    and deleted_at <  timestamptz '2026-06-18 19:00:00+00';

create temp table purge_rooms on commit drop as
  select id from app.rooms
  where deleted_at >= timestamptz '2026-06-18 17:00:00+00'
    and deleted_at <  timestamptz '2026-06-18 19:00:00+00';

select 'BEFORE' as phase,
  (select count(*) from purge_lessons) as lessons_to_purge,
  (select count(*) from purge_rooms) as rooms_to_purge;

-- Safety: the rooms we purge must not be referenced by any lesson we are NOT
-- also deleting, nor by any group. (Active rows were already repointed.)
do $$
declare bad int;
begin
  select count(*) into bad
  from app.lessons l
  where l.room_id in (select id from purge_rooms)
    and l.id not in (select id from purge_lessons);
  if bad > 0 then raise exception 'ABORT: % non-purged lessons still reference purge rooms', bad; end if;

  select count(*) into bad
  from app.groups g
  where g.room_id in (select id from purge_rooms);
  if bad > 0 then raise exception 'ABORT: % groups still reference purge rooms', bad; end if;

  select count(*) into bad
  from app.lesson_participation p
  where p.lesson_id in (select id from purge_lessons);
  if bad > 0 then raise exception 'ABORT: % participation rows on purge lessons', bad; end if;
end $$;

-- Delete lessons first, then the now-unreferenced rooms.
delete from app.lessons where id in (select id from purge_lessons);
delete from app.rooms where id in (select id from purge_rooms);

select 'AFTER' as phase,
  (select count(*) from app.lessons where deleted_at is not null) as remaining_deleted_lessons,
  (select count(*) from app.rooms where deleted_at is not null) as remaining_deleted_rooms,
  (select count(*) from app.rooms where deleted_at is null) as active_rooms,
  (select count(*) from app.lessons where deleted_at is null) as active_lessons;

\if :dryrun
  \echo '*** DRY RUN — rolling back ***'
  rollback;
\else
  \echo '*** COMMITTING PURGE ***'
  commit;
\endif
