-- ============================================================================
-- Merge duplicate rooms and their duplicate lessons.
--
-- Context: each (branch, room name) exists 3x due to repeated HolliHop imports
-- on 2026-03-14 / 06-14 / 06-15. Canonical room = the oldest copy. All lessons
-- and groups are repointed to the canonical room; lessons that become exact
-- duplicates after the repoint (same canonical room + same group/student +
-- same scheduled_at) are soft-deleted, keeping the richest one. Duplicate
-- (non-canonical) rooms are then soft-deleted.
--
-- Run with :dryrun set to 1 to verify and ROLLBACK, or 0 to COMMIT.
--   psql -v dryrun=1 -f merge_duplicate_rooms.sql
-- ============================================================================

\set ON_ERROR_STOP on
begin;

-- 1. Canonical room per (branch_id, name): the earliest-created copy.
create temp table room_canon on commit drop as
select r.id as room_id,
       first_value(r.id) over (
         partition by r.branch_id, r.name
         order by r.created_at asc, r.id asc
       ) as canonical_room_id
from app.rooms r
where r.deleted_at is null;

-- 2. Loser (duplicate) lessons: after mapping every lesson onto its canonical
--    room, any second+ lesson sharing (canonical_room, party, scheduled_at).
--    Winner = has teacher, not cancelled, oldest, then id for stability.
create temp table lesson_losers on commit drop as
select id as lesson_id
from (
  select l.id,
         row_number() over (
           partition by c.canonical_room_id,
                        coalesce(l.group_id::text, l.student_id::text, 'none'),
                        l.scheduled_at
           order by (l.teacher_id is not null) desc,
                    (l.status <> 'cancelled') desc,
                    l.created_at asc,
                    l.id asc
         ) as rn
  from app.lessons l
  join room_canon c on c.room_id = l.room_id
  where l.deleted_at is null
) ranked
where rn > 1;

-- ---- Pre-change snapshot --------------------------------------------------
select 'BEFORE' as phase,
  (select count(*) from app.rooms where deleted_at is null) as rooms_active,
  (select count(*) from app.lessons where deleted_at is null) as lessons_active,
  (select count(*) from lesson_losers) as lessons_to_soft_delete,
  (select count(distinct canonical_room_id) from room_canon) as canonical_rooms,
  (select count(*) from room_canon where room_id <> canonical_room_id) as rooms_to_soft_delete;

-- Safety assertions: losers must carry no dependent data.
do $$
declare
  bad int;
begin
  select count(*) into bad from app.lesson_participation p
    where p.lesson_id in (select lesson_id from lesson_losers);
  if bad > 0 then raise exception 'ABORT: % loser lessons have participation rows', bad; end if;

  select count(*) into bad from app.tasks t
    where t.entity_type = 'lesson' and t.deleted_at is null
      and t.entity_id in (select lesson_id from lesson_losers);
  if bad > 0 then raise exception 'ABORT: % loser lessons have tasks', bad; end if;

  select count(*) into bad from app.entity_comments ec
    where ec.entity_type = 'lesson' and ec.deleted_at is null
      and ec.entity_id in (select lesson_id from lesson_losers);
  if bad > 0 then raise exception 'ABORT: % loser lessons have comments', bad; end if;

  select count(*) into bad from app.file_objects f
    where f.owner_type = 'lesson' and f.deleted_at is null
      and f.owner_id in (select lesson_id from lesson_losers);
  if bad > 0 then raise exception 'ABORT: % loser lessons have files', bad; end if;
end $$;

-- 3. Soft-delete duplicate lessons.
update app.lessons
set deleted_at = now(), updated_at = now()
where id in (select lesson_id from lesson_losers)
  and deleted_at is null;

-- 4. Repoint surviving lessons to the canonical room.
update app.lessons l
set room_id = c.canonical_room_id, updated_at = now()
from room_canon c
where l.room_id = c.room_id
  and c.room_id <> c.canonical_room_id
  and l.deleted_at is null;

-- 5. Repoint surviving groups to the canonical room (defensive; currently 0).
update app.groups g
set room_id = c.canonical_room_id, updated_at = now()
from room_canon c
where g.room_id = c.room_id
  and c.room_id <> c.canonical_room_id
  and g.deleted_at is null;

-- 6. Soft-delete the duplicate (non-canonical) rooms.
update app.rooms r
set deleted_at = now(), updated_at = now()
from room_canon c
where r.id = c.room_id
  and c.room_id <> c.canonical_room_id
  and r.deleted_at is null;

-- ---- Post-change verification ---------------------------------------------
select 'AFTER' as phase,
  (select count(*) from app.rooms where deleted_at is null) as rooms_active,
  (select count(*) from app.lessons where deleted_at is null) as lessons_active,
  -- every active lesson with a room must now point to a canonical (active) room
  (select count(*) from app.lessons l
     where l.deleted_at is null and l.room_id is not null
       and not exists (select 1 from app.rooms r where r.id = l.room_id and r.deleted_at is null)) as orphan_lessons,
  -- no remaining duplicate (branch,name) among active rooms
  (select count(*) from (
     select 1 from app.rooms where deleted_at is null
     group by branch_id, name having count(*) > 1) d) as remaining_dup_room_groups,
  -- no remaining duplicate lessons within a room
  (select count(*) - count(distinct (room_id, coalesce(group_id::text,student_id::text,'none'), scheduled_at))
     from app.lessons where deleted_at is null and room_id is not null) as remaining_dup_lessons;

\if :dryrun
  \echo '*** DRY RUN — rolling back ***'
  rollback;
\else
  \echo '*** COMMITTING ***'
  commit;
\endif
