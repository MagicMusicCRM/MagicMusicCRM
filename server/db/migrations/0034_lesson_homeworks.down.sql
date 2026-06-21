-- P5c (KVA-200) rollback.

drop table if exists app.homework_attachments;
drop table if exists app.lesson_homeworks;

-- PostgreSQL enum values are intentionally not removed here.
-- app.file_purpose keeps 'homework_attachment'.
