-- server/db/migrations/0032_lead_board_cleanup.down.sql
-- NOTE: data cleanup is largely irreversible — the per-lead original status_id and the
-- deleted legacy statuses (Контакт/Переговоры/Договор) cannot be reconstructed. We only
-- revert the flag/color changes that are mechanically safe; renumbering and the
-- delete/remap are left as-is by design.
update app.lead_statuses set requires_reason = false where name = 'Отказ';
update app.lead_statuses set is_terminal = false where name in ('Успешный', 'Отказ');
