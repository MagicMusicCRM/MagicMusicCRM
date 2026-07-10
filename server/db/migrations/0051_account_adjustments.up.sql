-- KVA-235: ручные операции личного счёта клиента. Приход остаётся в
-- app.payments, списания — проведённые занятия; здесь только операции без
-- иного источника: возвраты, корректировки, переносы между клиентами.
-- amount ХРАНИТСЯ СО ЗНАКОМ (возврат/перенос-исход — отрицательные), поэтому
-- баланс = sum(payments) - стоимость занятий + sum(adjustments.amount).
create table if not exists app.account_adjustments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references app.students(id) on delete cascade,
  branch_id uuid references app.branches(id),
  kind text not null check (kind in ('refund', 'adjustment', 'transfer_in', 'transfer_out')),
  amount numeric(12, 2) not null check (amount <> 0),
  description text,
  method text,
  counterparty_student_id uuid references app.students(id) on delete set null,
  occurred_at timestamptz not null default now(),
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists account_adjustments_student_idx
  on app.account_adjustments (student_id, occurred_at desc)
  where deleted_at is null;
