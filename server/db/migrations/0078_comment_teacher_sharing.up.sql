alter table app.entity_comments
  add column if not exists shared_with_teacher boolean not null default false,
  add column if not exists version bigint not null default 1;

update app.entity_comments
set shared_with_teacher = true
where kind = 'teacher_note'
  and shared_with_teacher = false;

alter table app.entity_comments
  drop constraint if exists entity_comments_version_positive;

alter table app.entity_comments
  add constraint entity_comments_version_positive check (version > 0);

create index if not exists entity_comments_teacher_shared_idx
  on app.entity_comments (entity_type, entity_id, created_at desc, id desc)
  where deleted_at is null and shared_with_teacher;

insert into app.aggregate_versions (
  aggregate_type,
  aggregate_id,
  version
)
select
  'crm:comment',
  comment.id::text,
  comment.version
from app.entity_comments comment
on conflict (aggregate_type, aggregate_id) do update
set version = excluded.version,
    updated_at = now();

create or replace function app.initialize_comment_integrity_version()
returns trigger
language plpgsql
as $$
begin
  insert into app.aggregate_versions (
    aggregate_type,
    aggregate_id,
    version
  )
  values ('crm:comment', new.id::text, new.version)
  on conflict (aggregate_type, aggregate_id) do nothing;

  return new;
end;
$$;

drop trigger if exists entity_comments_initialize_integrity_version
  on app.entity_comments;

create trigger entity_comments_initialize_integrity_version
after insert on app.entity_comments
for each row
execute function app.initialize_comment_integrity_version();
