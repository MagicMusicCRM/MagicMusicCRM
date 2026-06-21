-- P6 · Data-quality cleanup (KVA-201) — DRY-RUN FIRST.
--
-- Operates on REAL production data, so every section is SELECT-first: run the
-- dry-run query, eyeball the rows, THEN run the apply block (kept commented) inside
-- a transaction. ALWAYS take an encrypted backup before any apply:
--   /opt/magicmusiccrm/infra/scripts/backup-staging.sh
-- Run via:  docker compose exec -T db psql -U <user> -d <db> -f - < this file
-- (or paste section-by-section in psql). Applies are guarded + idempotent; re-running
-- after a clean finds nothing.
--
-- STATUS:
--   P6-3 (phone normalization) — ALREADY DONE by migration 0025_phone_normalization
--        (phone_normalized backfill + phone_review_queue, mirror of normalizedPhoneExpr).
--        Re-check open queue:  select reason, count(*) from app.phone_review_queue
--                              where resolved_at is null group by reason;
--   P6-1 / P6-2 / P6-4 — below.  P6-5 (missing comments) needs the HolliHop source
--        export; use server/src/migration/import-hollihop-exports.ts in dry-run mode.

\echo '================= P6-1: room-lesson overlaps ================='
-- DRY-RUN (a): exact-duplicate lessons (same room+time+duration+group/student/teacher).
-- These are the safe-to-remove merge artifacts. Keeps the earliest-created row.
select room_id, scheduled_at, duration_minutes, group_id, student_id, teacher_id,
       count(*) as copies, array_agg(id order by created_at) as lesson_ids
from app.lessons
where deleted_at is null and room_id is not null
group by room_id, scheduled_at, duration_minutes, group_id, student_id, teacher_id
having count(*) > 1
order by copies desc, scheduled_at;

-- DRY-RUN (b): NON-exact time overlaps in the same room (possible real double-bookings
-- — DO NOT auto-delete; review manually).
select a.id as a_id, b.id as b_id, a.room_id, a.scheduled_at as a_start, b.scheduled_at as b_start
from app.lessons a
join app.lessons b
  on a.room_id = b.room_id and a.room_id is not null
 and a.id < b.id and a.deleted_at is null and b.deleted_at is null
 and tstzrange(a.scheduled_at, a.scheduled_at + (a.duration_minutes || ' min')::interval)
     && tstzrange(b.scheduled_at, b.scheduled_at + (b.duration_minutes || ' min')::interval)
 and not (a.scheduled_at = b.scheduled_at and a.duration_minutes = b.duration_minutes
          and coalesce(a.group_id,'00000000-0000-0000-0000-000000000000') = coalesce(b.group_id,'00000000-0000-0000-0000-000000000000')
          and coalesce(a.student_id,'00000000-0000-0000-0000-000000000000') = coalesce(b.student_id,'00000000-0000-0000-0000-000000000000'))
order by a.room_id, a_start
limit 500;

-- APPLY P6-1 (exact dups only — SAFE). Uncomment after reviewing DRY-RUN (a):
-- begin;
-- with dups as (
--   select id, row_number() over (
--     partition by room_id, scheduled_at, duration_minutes,
--       coalesce(group_id::text,''), coalesce(student_id::text,''), coalesce(teacher_id::text,'')
--     order by created_at asc, id asc) as rn
--   from app.lessons where deleted_at is null and room_id is not null
-- )
-- update app.lessons set deleted_at = now(), updated_at = now()
-- where id in (select id from dups where rn > 1) and deleted_at is null;
-- -- verify the count matches DRY-RUN (a) sum(copies-1), then: commit;  (else rollback;)

\echo '================= P6-2: synthetic .invalid emails ================='
-- DRY-RUN: placeholder emails (@*.invalid are never deliverable — synthetic from import).
select 'profile' as kind, id, email from app.profiles
  where deleted_at is null and (email ilike '%.invalid' or email ilike 'holli-hop-error@%')
union all
select 'lead', id, email from app.leads
  where deleted_at is null and (email ilike '%.invalid' or email ilike 'holli-hop-error@%')
order by kind;

-- APPLY P6-2 (null placeholder emails — they carry no real contact). Uncomment after review:
-- begin;
-- update app.profiles set email = null, updated_at = now()
--   where deleted_at is null and (email ilike '%.invalid' or email ilike 'holli-hop-error@%');
-- update app.leads set email = null, updated_at = now()
--   where deleted_at is null and (email ilike '%.invalid' or email ilike 'holli-hop-error@%');
-- commit;

\echo '================= P6-4: split lessons (import duration fragmentation) ================='
-- DRY-RUN: clusters of >=2 back-to-back same-day lessons for the same group/teacher/room
-- that look like one lesson fragmented into hourly rows. REVIEW — merge is data-specific
-- (collapse a contiguous run into one row spanning the full duration). Do NOT auto-merge
-- blind; confirm against the HolliHop source before applying.
select room_id, teacher_id, group_id, scheduled_at::date as day,
       count(*) as fragments, min(scheduled_at) as first_start, max(scheduled_at) as last_start,
       array_agg(id order by scheduled_at) as lesson_ids
from app.lessons
where deleted_at is null
group by room_id, teacher_id, group_id, scheduled_at::date
having count(*) >= 2
order by fragments desc, day
limit 300;
-- Merge approach (manual, per cluster): keep the first row, set its duration_minutes to
-- span first_start..last_start+last.duration, re-point participation/attendance to it,
-- soft-delete the rest. Implement as a reviewed one-off once the fragmentation pattern
-- is confirmed on the dry-run output.
