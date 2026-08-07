do $$
begin
  if exists (select 1 from app.lesson_settlement_plan_revisions) then
    raise exception
      'Refusing destructive rollback: settlement plan revisions exist';
  end if;
end $$;

drop trigger if exists lesson_settlement_plan_revisions_immutable
  on app.lesson_settlement_plan_revisions;
drop table if exists app.lesson_settlement_plan_revisions;
