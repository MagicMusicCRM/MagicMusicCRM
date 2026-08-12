alter table app.phone_review_queue
  drop constraint if exists phone_review_queue_resolution_integrity_check,
  drop constraint if exists phone_review_queue_resolution_action_check,
  drop column if exists resolved_phone,
  drop column if exists resolution_note,
  drop column if exists resolution_action;
