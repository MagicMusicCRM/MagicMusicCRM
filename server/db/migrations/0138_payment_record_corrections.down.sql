do $$
begin
  if exists (select 1 from app.payment_record_corrections) then
    raise exception '0138 rollback blocked: payment record corrections exist';
  end if;
end $$;

drop trigger if exists payment_record_corrections_immutable
  on app.payment_record_corrections;
drop table app.payment_record_corrections;
