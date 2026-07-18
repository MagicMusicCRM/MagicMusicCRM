-- A lead represents one conversion lineage. Concurrent conversion paths
-- (lead card and chat promotion) must not create two live students for it.
-- Hold out old API converters between the preflight and index build.
lock table app.students in share mode;

do $$
begin
  if exists (
    select 1
    from app.students
    where lead_id is not null and deleted_at is null
    group by lead_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot enforce students_lead_active_unique_idx: duplicate active students exist for a lead';
  end if;
end
$$;

create unique index if not exists students_lead_active_unique_idx
  on app.students (lead_id)
  where deleted_at is null and lead_id is not null;
