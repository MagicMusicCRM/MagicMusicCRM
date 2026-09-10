-- A published configuration revision cannot be erased or rewritten by rollback.
do $$
begin
  if exists (
    select 1 from app.crm_configuration_revisions
    where impact->>'migration' = '0154_retire_partial_miss'
  ) then
    raise exception 'Retired settlement type revision is immutable; use a new revision to reactivate';
  end if;
end $$;
