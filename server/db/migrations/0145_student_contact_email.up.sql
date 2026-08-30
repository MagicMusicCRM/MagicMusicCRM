alter table app.students
  add column if not exists contact_email text;

alter table app.email_outbox
  add column if not exists recipient_student_id uuid
    references app.students(id) on delete set null;

update app.students student
set contact_email = lower(btrim(account.email)),
    updated_at = now()
from app.profiles profile
join app.users account
  on account.id = profile.user_id
 and account.deleted_at is null
where student.profile_id = profile.id
  and student.contact_email is null
  and account.email is not null
  and lower(account.email) not like '%@local.magicmusiccrm.invalid'
  and lower(account.email) not like '%@migration.invalid';

create index if not exists students_contact_email_lower_idx
  on app.students (lower(contact_email))
  where deleted_at is null and contact_email is not null;

create index if not exists email_outbox_recipient_student_idx
  on app.email_outbox (recipient_student_id)
  where recipient_student_id is not null;

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'app'
      and table_name = 'students'
      and column_name = 'contact_email'
      and data_type = 'text'
      and is_nullable = 'YES'
  ) then
    raise exception '0145 contract failed: app.students.contact_email';
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    join pg_class source_table on source_table.oid = constraint_row.conrelid
    join pg_namespace source_schema on source_schema.oid = source_table.relnamespace
    join pg_class target_table on target_table.oid = constraint_row.confrelid
    join pg_namespace target_schema on target_schema.oid = target_table.relnamespace
    where source_schema.nspname = 'app'
      and source_table.relname = 'email_outbox'
      and target_schema.nspname = 'app'
      and target_table.relname = 'students'
      and constraint_row.contype = 'f'
      and constraint_row.confdeltype = 'n'
      and pg_get_constraintdef(constraint_row.oid) like
        'FOREIGN KEY (recipient_student_id) REFERENCES app.students(id) ON DELETE SET NULL%'
  ) then
    raise exception '0145 contract failed: recipient_student_id FK';
  end if;

  if not exists (
    select 1
    from pg_index index_row
    join pg_class index_relation on index_relation.oid = index_row.indexrelid
    join pg_namespace index_schema on index_schema.oid = index_relation.relnamespace
    where index_schema.nspname = 'app'
      and index_relation.relname = 'students_contact_email_lower_idx'
      and index_row.indisvalid
  ) or not exists (
    select 1
    from pg_index index_row
    join pg_class index_relation on index_relation.oid = index_row.indexrelid
    join pg_namespace index_schema on index_schema.oid = index_relation.relnamespace
    where index_schema.nspname = 'app'
      and index_relation.relname = 'email_outbox_recipient_student_idx'
      and index_row.indisvalid
  ) then
    raise exception '0145 contract failed: contact email indexes';
  end if;

  if exists (
    select 1
    from app.students student
    where lower(student.contact_email) like '%@local.magicmusiccrm.invalid'
       or lower(student.contact_email) like '%@migration.invalid'
  ) then
    raise exception '0145 contract failed: placeholder contact email';
  end if;

  if exists (
    select 1
    from app.students student
    join app.profiles profile
      on profile.id = student.profile_id
     and profile.deleted_at is null
    join app.users account
      on account.id = profile.user_id
     and account.deleted_at is null
    where student.contact_email is null
      and account.email is not null
      and lower(account.email) not like '%@local.magicmusiccrm.invalid'
      and lower(account.email) not like '%@migration.invalid'
  ) then
    raise exception '0145 contract failed: contact email backfill';
  end if;
end $$;
