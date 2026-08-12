-- Complete the phone-review lifecycle: every resolved row records whether the
-- source value was corrected or explicitly accepted, who decided, and why.
alter table app.phone_review_queue
  add column if not exists resolution_action text,
  add column if not exists resolution_note text,
  add column if not exists resolved_phone text;

-- Preserve already-resolved legacy rows instead of making the new invariant
-- impossible to apply on an upgraded database.
update app.phone_review_queue
set resolution_action = 'accepted_as_is',
    resolution_note = 'Разобрано до введения журнала решений'
where resolved_at is not null
  and resolution_action is null;

alter table app.phone_review_queue
  drop constraint if exists phone_review_queue_resolution_action_check,
  add constraint phone_review_queue_resolution_action_check
    check (resolution_action is null or resolution_action in ('corrected', 'accepted_as_is')),
  drop constraint if exists phone_review_queue_resolution_integrity_check,
  add constraint phone_review_queue_resolution_integrity_check check (
    (resolved_at is null
      and resolved_by is null
      and resolution_action is null
      and resolution_note is null
      and resolved_phone is null)
    or
    (resolved_at is not null
      and resolution_action is not null
      and nullif(btrim(resolution_note), '') is not null
      and (
        (resolution_action = 'corrected' and nullif(btrim(resolved_phone), '') is not null)
        or
        (resolution_action = 'accepted_as_is' and resolved_phone is null)
      ))
  );
