do $$
begin
  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'app'
       and table_name = 'idempotency_records'
  ) and exists (select 1 from app.idempotency_records) then
    raise exception
      'Refusing destructive rollback: app.idempotency_records contains facts';
  end if;

  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'app'
       and table_name = 'platform_outbox_events'
  ) and exists (select 1 from app.platform_outbox_events) then
    raise exception
      'Refusing destructive rollback: app.platform_outbox_events contains facts';
  end if;

  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'app'
       and table_name = 'aggregate_versions'
  ) and exists (select 1 from app.aggregate_versions) then
    raise exception
      'Refusing destructive rollback: app.aggregate_versions contains facts';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'app'
       and table_name = 'audit_events'
       and column_name = 'request_id'
  ) and exists (
    select 1
      from app.audit_events
     where request_id is not null
        or before_ref is not null
        or after_ref is not null
        or reason is not null
  ) then
    raise exception
      'Refusing destructive rollback: app.audit_events contains v4 references';
  end if;
end $$;

drop table if exists app.idempotency_records;
drop table if exists app.platform_outbox_events;
drop table if exists app.aggregate_versions;

drop index if exists app.audit_events_request_id_idx;
alter table app.audit_events
  drop column if exists request_id,
  drop column if exists before_ref,
  drop column if exists after_ref,
  drop column if exists reason;
