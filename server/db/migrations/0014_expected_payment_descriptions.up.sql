alter table app.expected_payments
  add column if not exists description text;
