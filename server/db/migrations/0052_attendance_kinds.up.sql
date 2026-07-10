-- KVA-237: 5 типов посещения по модели HolliHop + доля списания для
-- «частично оплачиваемого» + фактически списанные часы (charged_hours) —
-- благодаря им смена статуса задним числом пересчитывается идемпотентно
-- по дельте, а не по бинарному «списано/не списано».
alter table app.lesson_participation
  add column if not exists attendance_kind text not null default 'attended'
    check (attendance_kind in ('attended', 'unpaid_miss', 'free_lesson', 'paid_miss', 'partially_paid')),
  add column if not exists charge_share numeric(4, 3) not null default 1
    check (charge_share > 0 and charge_share <= 1),
  add column if not exists charged_hours numeric(6, 2) not null default 0
    check (charged_hours >= 0);

-- Бэкфилл легаси-семантики: absent -> неоплачиваемый пропуск.
update app.lesson_participation
set attendance_kind = 'unpaid_miss'
where status = 'absent';

-- Уже списанные часы (present с привязанным абонементом) фиксируем как
-- duration/60 — ровно столько снял старый reconcile.
update app.lesson_participation lp
set charged_hours = coalesce(l.duration_minutes, 60)::numeric / 60
from app.lessons l
where l.id = lp.lesson_id
  and lp.subscription_id is not null
  and lp.status = 'present';
