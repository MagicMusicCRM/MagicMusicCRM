drop trigger if exists entity_comments_initialize_integrity_version
  on app.entity_comments;
drop function if exists app.initialize_comment_integrity_version();

delete from app.aggregate_versions
where aggregate_type = 'crm:comment';

drop index if exists app.entity_comments_teacher_shared_idx;

alter table app.entity_comments
  drop constraint if exists entity_comments_version_positive,
  drop column if exists version,
  drop column if exists shared_with_teacher;
