do $$ begin
  if exists(select 1 from app.expense_revisions where not baseline) then
    raise exception 'Cannot remove expense history after commands were committed';
  end if;
end $$;
drop table app.expense_revisions;
delete from app.aggregate_versions where aggregate_type='commerce:expense';
drop index app.expenses_occurred_idx;
alter table app.expenses drop column version,drop column occurred_at;
