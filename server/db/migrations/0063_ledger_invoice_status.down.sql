-- server/db/migrations/0063_ledger_invoice_status.down.sql
drop index if exists app.account_adjustments_student_active_idx;

alter table app.account_adjustments
  drop constraint if exists account_adjustments_status_check;

alter table app.account_adjustments
  drop column if exists voided_at,
  drop column if exists voided_by,
  drop column if exists status,
  drop column if exists invoice_number;

alter table app.payments
  drop column if exists invoice_number;
