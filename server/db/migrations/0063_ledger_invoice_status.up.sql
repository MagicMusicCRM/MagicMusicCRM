-- server/db/migrations/0063_ledger_invoice_status.up.sql
-- Личный счёт: колонки «№ Счёта» и «Статус» + возможность править и отменять
-- запись (чек-лист §2.7, эталон HolliHop — скриншот «ЛИЧНЫЙ СЧЁТ: операции»:
-- «Филиал, Дата добавления, Сумма, Комментарий, Способ оплаты, Кто добавил,
-- № Счёта, Статус (Оплачен + кто/когда)» + действия возврат/редакт/удалить).
--
-- Филиал уже был (`branch_id` в 0051) — его просто никто не показывал.

alter table app.payments
  add column if not exists invoice_number text;

alter table app.account_adjustments
  add column if not exists invoice_number text,
  -- 'paid'    — проведена (по умолчанию: запись создают уже свершившейся);
  -- 'pending' — выставлена, но не оплачена;
  -- 'void'    — отменена. Деньги НЕ удаляют, их сторнируют: удаление строки
  --             личного счёта задним числом сломало бы уже показанный клиенту
  --             баланс и не оставило бы следа, кто это сделал.
  add column if not exists status text not null default 'paid',
  -- «Статус: Оплачен + кто/когда» — для отмены нужен свой автор: created_by
  -- отвечает на «кто создал», а не «кто отменил».
  add column if not exists voided_by uuid references app.users(id) on delete set null,
  add column if not exists voided_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'account_adjustments_status_check'
  ) then
    alter table app.account_adjustments
      add constraint account_adjustments_status_check
      check (status in ('paid', 'pending', 'void'));
  end if;
end $$;

-- Отменённые записи не участвуют в балансе, но остаются видимыми в ленте:
-- частичный индекс держит быстрым именно расчётный путь.
create index if not exists account_adjustments_student_active_idx
  on app.account_adjustments (student_id, occurred_at desc)
  where deleted_at is null and status <> 'void';
