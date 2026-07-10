-- KVA-238: зарплатный модуль педагогов. Ставки храним ИСТОРИЕЙ
-- (teacher_rates): эффективная ставка на дату занятия = последняя запись с
-- effective_from <= даты занятия, поэтому смена ставки задним числом
-- автоматически пересчитывает начисления. rate = 0 означает «входит в оклад»
-- (занятия не оплачиваются поштучно). Сами начисления НЕ материализуются —
-- считаются проекцией по проведённым занятиям (паттерн ledger из KVA-235).
create table if not exists app.teacher_rates (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.teachers(id) on delete cascade,
  rate numeric(10, 2) not null check (rate >= 0),
  effective_from date not null default current_date,
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists teacher_rates_teacher_idx
  on app.teacher_rates (teacher_id, effective_from desc, created_at desc);

-- Выплаты преподавателю. amount всегда положительный, смысл задаёт kind:
--   payout    — выплата (гасит задолженность),
--   bonus     — доплата (увеличивает начисленное),
--   deduction — вычет (уменьшает начисленное).
-- Задолженность = начислено_по_занятиям + bonus - deduction - payout.
create table if not exists app.teacher_payouts (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references app.teachers(id) on delete cascade,
  amount numeric(12, 2) not null check (amount > 0),
  kind text not null check (kind in ('payout', 'bonus', 'deduction')),
  comment text,
  paid_at timestamptz not null default now(),
  created_by uuid references app.users(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists teacher_payouts_teacher_idx
  on app.teacher_payouts (teacher_id, paid_at desc)
  where deleted_at is null;

-- Переопределение ставки на уровне группы: NULL = брать ставку педагога,
-- 0 = «входит в оклад». Процесс заказчика: в конце месяца пробные группы без
-- покупки вручную переводят в 0 через drill-down отчёта.
alter table app.groups
  add column if not exists teacher_rate numeric(10, 2)
    check (teacher_rate is null or teacher_rate >= 0);

-- Оклад педагога (фиксированная часть, ₽/мес). Поштучные ставки — выше.
alter table app.teachers
  add column if not exists salary numeric(12, 2);
