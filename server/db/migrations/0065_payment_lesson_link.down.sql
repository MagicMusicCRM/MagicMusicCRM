drop index if exists app.payments_lesson_idx;

alter table app.payments
  drop column if exists lesson_id;
