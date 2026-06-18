-- Merge duplicate HolliHop-imported branches into their canonical record.
--
-- Context: the HolliHop import created TWO app.branches rows per physical
-- location ("Сокол", "Спортивная"). The data was split inconsistently between
-- them: the "duplicate" row owns rooms + groups (with enrolled students and
-- lessons happening in those rooms/groups), while most lessons' own branch_id
-- points at the "canonical" row. This breaks the lesson ↔ branch ↔ room linkage
-- the Schedule screen relies on, and surfaces a confusing second branch in the
-- UI. The duplicates are NOT empty and MUST NOT be deleted outright (that would
-- orphan ~1089 students' enrolments and ~12000 lessons).
--
-- This script MERGES each duplicate into its canonical record: it reassigns the
-- duplicate's rooms, groups, lessons and staff links to the canonical branch,
-- aligns the branch_id of lessons that happen in those rooms/groups, and then
-- soft-deletes the now-empty duplicate (reversible — listBranches filters
-- deleted_at is null, so it disappears from the UI but the row is retained).
--
-- SAFETY:
--   * Take a backup first: bash /opt/magicmusiccrm/infra/scripts/backup-staging.sh
--   * Review the BEFORE/AFTER counts. The whole thing runs in one transaction;
--     rollback if anything looks off.
--
-- Mapping (duplicate -> canonical):
--   Сокол:       4f2fdb12-b11b-40f9-b207-e48538aaa130 -> 62f5f8f6-5d03-4138-9189-15064c8f4a72
--   Спортивная:  e5406482-e33d-48c3-8139-f0acffcab32f -> dfc0220f-8f54-4024-bb63-42dabef479b2

\set ON_ERROR_STOP on

-- ── BEFORE ───────────────────────────────────────────────────────────────────
\echo '== BEFORE: per-branch object counts =='
select b.id, b.name, b.deleted_at,
  (select count(*) from app.rooms r where r.branch_id=b.id)   rooms,
  (select count(*) from app.groups g where g.branch_id=b.id)  groups,
  (select count(*) from app.lessons l where l.branch_id=b.id) lessons,
  (select count(*) from app.staff_branch_assignments s where s.branch_id=b.id) staff
from app.branches b
where b.id in (
  '4f2fdb12-b11b-40f9-b207-e48538aaa130','62f5f8f6-5d03-4138-9189-15064c8f4a72',
  'e5406482-e33d-48c3-8139-f0acffcab32f','dfc0220f-8f54-4024-bb63-42dabef479b2'
)
order by b.name, b.id;

begin;

create temp table _branch_merge(dup uuid, keep uuid) on commit drop;
insert into _branch_merge values
  ('4f2fdb12-b11b-40f9-b207-e48538aaa130','62f5f8f6-5d03-4138-9189-15064c8f4a72'),
  ('e5406482-e33d-48c3-8139-f0acffcab32f','dfc0220f-8f54-4024-bb63-42dabef479b2');

-- 1. Align branch_id of lessons that take place in the duplicate's rooms/groups
--    BEFORE the rooms/groups move, so the subqueries still match the duplicate.
update app.lessons l
set branch_id = m.keep, updated_at = now()
from _branch_merge m
where (
        l.room_id  in (select id from app.rooms  where branch_id = m.dup)
     or l.group_id in (select id from app.groups where branch_id = m.dup)
      )
  and l.branch_id is distinct from m.keep;

-- 2. Reassign rooms.
update app.rooms r set branch_id = m.keep, updated_at = now()
from _branch_merge m where r.branch_id = m.dup;

-- 3. Reassign groups.
update app.groups g set branch_id = m.keep, updated_at = now()
from _branch_merge m where g.branch_id = m.dup;

-- 4. Reassign any lessons still pointing directly at the duplicate.
update app.lessons l set branch_id = m.keep, updated_at = now()
from _branch_merge m where l.branch_id = m.dup;

-- 5. Reassign staff branch assignments, avoiding the (staff_member_id, branch_id)
--    unique-constraint collision; drop any leftover duplicate links.
update app.staff_branch_assignments s set branch_id = m.keep
from _branch_merge m
where s.branch_id = m.dup
  and not exists (
    select 1 from app.staff_branch_assignments x
    where x.staff_member_id = s.staff_member_id and x.branch_id = m.keep
  );
delete from app.staff_branch_assignments s using _branch_merge m where s.branch_id = m.dup;

-- 6. Soft-delete the now-empty duplicate branch rows.
update app.branches b set deleted_at = now(), updated_at = now()
from _branch_merge m where b.id = m.dup and b.deleted_at is null;

-- ── VERIFY (inside the transaction) ──────────────────────────────────────────
\echo '== AFTER: duplicates must show 0 live rooms/groups/lessons/staff and a deleted_at =='
select b.id, b.name, b.deleted_at,
  (select count(*) from app.rooms r where r.branch_id=b.id)   rooms,
  (select count(*) from app.groups g where g.branch_id=b.id)  groups,
  (select count(*) from app.lessons l where l.branch_id=b.id) lessons,
  (select count(*) from app.staff_branch_assignments s where s.branch_id=b.id) staff
from app.branches b
where b.id in (
  '4f2fdb12-b11b-40f9-b207-e48538aaa130','62f5f8f6-5d03-4138-9189-15064c8f4a72',
  'e5406482-e33d-48c3-8139-f0acffcab32f','dfc0220f-8f54-4024-bb63-42dabef479b2'
)
order by b.name, b.id;

-- Review the AFTER output above. If correct, COMMIT; otherwise ROLLBACK.
commit;

\echo '== Remaining live branches (no same-name duplicates should remain) =='
select lower(name) name, count(*)
from app.branches where deleted_at is null
group by 1 having count(*) > 1;
