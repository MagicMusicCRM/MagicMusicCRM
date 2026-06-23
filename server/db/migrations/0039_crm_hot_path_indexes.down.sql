-- server/db/migrations/0039_crm_hot_path_indexes.down.sql
drop index if exists app.group_students_student_idx;
drop index if exists app.groups_room_idx;
drop index if exists app.groups_branch_idx;
drop index if exists app.groups_teacher_idx;
