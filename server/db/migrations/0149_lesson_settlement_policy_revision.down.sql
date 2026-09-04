do $$
begin
  if exists (
    select 1
    from app.crm_configuration_revisions revision
    where revision.impact->>'migration' =
      '0149_lesson_settlement_policy_revision'
  ) then
    raise exception
      'lesson settlement policy revision is immutable and cannot be rolled back';
  end if;
end $$;
