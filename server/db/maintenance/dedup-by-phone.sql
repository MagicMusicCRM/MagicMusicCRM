-- Dedup same-phone duplicates (KVA-209 P4), preserving ALL history.
-- Winner = the record with the most attached data; losers are re-pointed to the
-- winner across every FK, then soft-deleted. Run inside a transaction you control:
--   BEGIN; \i dedup-by-phone.sql   -> review the NOTICE counts -> COMMIT or ROLLBACK.

-- ── STUDENTS: merge same-phone students (winner = most lessons, else oldest) ──
do $$
declare g record; w uuid; l uuid; merged int := 0;
begin
  for g in (
    select array_agg(s.id order by
             (select count(*) from app.lessons le where le.student_id = s.id) desc,
             s.created_at asc) as ids
    from app.students s
    join app.profiles p on p.id = s.profile_id and p.deleted_at is null
    where s.deleted_at is null and p.phone_normalized is not null
    group by p.phone_normalized
    having count(*) > 1
  ) loop
    w := g.ids[1];
    foreach l in array g.ids[2:array_length(g.ids,1)] loop
      update app.lessons set student_id = w where student_id = l;
      -- unique (lesson_id, student_id): drop loser rows that would collide, move the rest
      delete from app.lesson_participation lp where lp.student_id = l
        and exists (select 1 from app.lesson_participation x where x.lesson_id = lp.lesson_id and x.student_id = w);
      update app.lesson_participation set student_id = w where student_id = l;
      delete from app.group_students gs where gs.student_id = l
        and exists (select 1 from app.group_students x where x.group_id = gs.group_id and x.student_id = w);
      update app.group_students set student_id = w where student_id = l;
      delete from app.student_disciplines sd where sd.student_id = l
        and exists (select 1 from app.student_disciplines x where x.discipline_id = sd.discipline_id and x.student_id = w);
      -- only one primary discipline per student: if the winner already has one,
      -- demote the loser's remaining rows before moving them.
      update app.student_disciplines set is_primary = false where student_id = l
        and exists (select 1 from app.student_disciplines x where x.student_id = w and x.is_primary);
      update app.student_disciplines set student_id = w where student_id = l;
      update app.payments set student_id = w where student_id = l;
      update app.expected_payments set student_id = w where student_id = l;
      update app.subscriptions set student_id = w where student_id = l;
      update app.lesson_homeworks set student_id = w where student_id = l;
      update app.student_status_history set student_id = w where student_id = l;
      update app.chats set student_id = w where student_id = l;
      delete from app.student_balances where student_id = l;  -- recomputed; keep winner's
      update app.entity_comments set entity_id = w where entity_type = 'student' and entity_id = l;
      update app.tasks set entity_id = w where entity_type = 'student' and entity_id = l;
      update app.family_members set entity_id = w where entity_type = 'student' and entity_id = l;
      update app.students set deleted_at = now(), updated_at = now() where id = l;
      insert into app.merge_log (entity_type, loser_id, winner_id, repointed, merged_by)
        values ('student', l, w, '{}'::jsonb, null);
      merged := merged + 1;
    end loop;
  end loop;
  raise notice 'students merged (losers): %', merged;
end $$;

-- ── LEADS: merge same-phone leads (winner = linked to a student, else newest) ──
do $$
declare g record; w uuid; l uuid; merged int := 0;
begin
  for g in (
    select array_agg(id order by
             (exists (select 1 from app.students s where s.lead_id = leads.id and s.deleted_at is null)) desc,
             created_at desc) as ids
    from app.leads
    where deleted_at is null and phone_normalized is not null
    group by phone_normalized
    having count(*) > 1
  ) loop
    w := g.ids[1];
    foreach l in array g.ids[2:array_length(g.ids,1)] loop
      update app.students set lead_id = w, updated_at = now() where lead_id = l and deleted_at is null;
      update app.lessons set lead_id = w where lead_id = l;
      update app.lead_status_history set lead_id = w where lead_id = l;
      update app.lead_comments set lead_id = w where lead_id = l;
      update app.chats set lead_id = w where lead_id = l;
      update app.entity_comments set entity_id = w where entity_type = 'lead' and entity_id = l;
      update app.tasks set entity_id = w where entity_type = 'lead' and entity_id = l;
      update app.family_members set entity_id = w where entity_type = 'lead' and entity_id = l;
      update app.leads set deleted_at = now(), updated_at = now() where id = l;
      insert into app.merge_log (entity_type, loser_id, winner_id, repointed, merged_by)
        values ('lead', l, w, '{}'::jsonb, null);
      merged := merged + 1;
    end loop;
  end loop;
  raise notice 'leads merged (losers): %', merged;
end $$;

-- ── Summary after dedup ──
select 'leads now = '||count(*) from app.leads where deleted_at is null;
select 'students now = '||count(*) from app.students where deleted_at is null;
select 'lead dup-phone groups remaining = '||count(*) from (select 1 from app.leads where deleted_at is null and phone_normalized is not null group by phone_normalized having count(*)>1) x;
select 'student dup-phone groups remaining = '||count(*) from (select 1 from app.students s join app.profiles p on p.id=s.profile_id where s.deleted_at is null and p.deleted_at is null and p.phone_normalized is not null group by p.phone_normalized having count(*)>1) y;
select 'lessons with student still intact = '||count(*) from app.lessons where deleted_at is null and student_id is not null;
