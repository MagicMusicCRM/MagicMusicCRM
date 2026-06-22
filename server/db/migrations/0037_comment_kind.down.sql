-- server/db/migrations/0037_comment_kind.down.sql
-- Restore the legacy [PROGRESS] prefix for progress comments, then drop kind.
update app.entity_comments
set body = '[PROGRESS] ' || body
where kind = 'progress' and body not like '[PROGRESS]%';

drop index if exists app.entity_comments_kind_idx;
alter table app.entity_comments drop column if exists kind;
