-- migrate:no-transaction
drop index concurrently if exists app.teachers_profile_active_idx;
drop index concurrently if exists app.students_profile_active_idx;
