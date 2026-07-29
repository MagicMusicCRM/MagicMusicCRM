drop view if exists app.client_lesson_success_metrics;

comment on table app.lesson_participation is null;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'magiccrm_app') then
    grant insert, update, delete, truncate
      on app.lesson_participation
      to magiccrm_app;
  end if;
end $$;
