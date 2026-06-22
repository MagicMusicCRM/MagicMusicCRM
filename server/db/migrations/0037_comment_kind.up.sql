-- server/db/migrations/0037_comment_kind.up.sql
-- Separate the comment streams on app.entity_comments by KIND with role-based
-- visibility, replacing the ad-hoc "[PROGRESS]" body prefix:
--   admin_comment — administrator comments (incl. the HolliHop Day.Description
--                   notes imported chronologically); visible to manager/admin/
--                   system_admin only — teachers and clients never see them.
--   teacher_note  — «Заметки преподавателя»: a teacher's notes about a student;
--                   visible to the assigned teacher + staff, written by teachers.
--   progress      — progress notes shown to the client (the old [PROGRESS] ones).
alter table app.entity_comments
  add column if not exists kind text not null default 'admin_comment';

-- Migrate the legacy prefix encoding to the new column, stripping the marker.
update app.entity_comments
set kind = 'progress',
    body = regexp_replace(body, '^\[PROGRESS\]\s*', '')
where body like '[PROGRESS]%';

create index if not exists entity_comments_kind_idx
  on app.entity_comments (entity_type, entity_id, kind)
  where deleted_at is null;
