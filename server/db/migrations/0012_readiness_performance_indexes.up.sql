create index if not exists payments_payment_date_idx
  on app.payments (payment_date desc, id desc)
  where deleted_at is null;

create index if not exists lessons_status_scheduled_idx
  on app.lessons (status, scheduled_at desc, id desc)
  where deleted_at is null;

create index if not exists students_created_idx
  on app.students (created_at desc, id desc)
  where deleted_at is null;

create index if not exists tasks_status_due_created_idx
  on app.tasks (status, due_at, created_at desc, id desc)
  where deleted_at is null;

create index if not exists entity_comments_entity_created_idx
  on app.entity_comments (entity_type, entity_id, created_at desc, id desc)
  where deleted_at is null;

create index if not exists expected_payments_student_due_idx
  on app.expected_payments (student_id, due_date desc, created_at desc, id desc);

create index if not exists subscriptions_student_expires_idx
  on app.subscriptions (student_id, expires_at desc, created_at desc, id desc);

create index if not exists chats_updated_idx
  on app.chats (updated_at desc, id desc)
  where deleted_at is null;
