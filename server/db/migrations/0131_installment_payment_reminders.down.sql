drop trigger if exists installment_payment_reminders_protect
  on app.installment_payment_reminders;
drop function if exists app.protect_installment_payment_reminder_identity();
drop table if exists app.installment_payment_reminders;
