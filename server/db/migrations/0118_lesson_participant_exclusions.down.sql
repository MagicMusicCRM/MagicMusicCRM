do $$
begin
  if exists (select 1 from app.lesson_participant_exclusions) then
    raise exception 'cannot remove lesson participant exclusions while facts exist';
  end if;
end $$;

drop trigger if exists lesson_participant_exclusions_immutable
  on app.lesson_participant_exclusions;
drop table if exists app.lesson_participant_exclusions;
