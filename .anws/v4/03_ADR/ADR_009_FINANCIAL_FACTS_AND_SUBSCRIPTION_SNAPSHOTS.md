# ADR-009 — Неизменяемые финансовые факты и снимки выданных абонементов

**Status:** Accepted  
**Date:** 2026-07-25  
**Influence scope:** SYS-COMMERCE, SYS-SCHEDULE, SYS-REPORTING, SYS-ACCESS  
**Requirements:** REQ-SUB-001, REQ-SUB-002, REQ-SUB-003, REQ-SUB-004, REQ-SUB-005, REQ-PRIV-001, REQ-REPORT-001

## Context

Шаблон абонемента может измениться после продажи, но уже выданный абонемент должен сохранить цену, скидку, лимит и правила на момент выдачи. Замена обязана создавать долг или переплату, отмена — исчезать из active UI, фиксироваться в действиях пользователя и не удалять/дублировать платежи или финансовую статистику.

## Decision

1. `SubscriptionPackage` — редактируемый каталог; создавать/изменять/архивировать его могут только Director и `system_admin`.
2. `IssuedSubscription` содержит immutable commercial snapshot пакета на момент выдачи.
3. `ActualPayment` является append-only фактом. Исправления оформляются отдельными adjustment/reversal facts, а не UPDATE/DELETE.
4. Выдавать, заменять и отменять абонемент из карточки клиента могут Admin, Manager, Director и `system_admin`.
5. Замена:
   - закрывает предыдущий lifecycle;
   - создаёт новый snapshot;
   - переносит только явно допустимые reservations;
   - вычисляет differential obligation;
   - создаёт долг или переплату;
   - не создаёт новый ActualPayment.
6. Отмена:
   - переводит issued subscription в `cancelled`;
   - снимает будущие reservations;
   - не изменяет ActualPayment и исторические ledger facts;
   - видна в audit/user actions;
   - не отображается как активная и не создаёт отдельную строку дохода/возврата.
7. Discount хранится как `percent` или `fixed` плюс обязательная reason. Installment schedule и payment method входят в snapshot.
8. Финансовая статистика строится из ledger/payment facts, а не из текущего состояния карточки абонемента.

## Options considered

| Option | Плюсы | Минусы | Решение |
|---|---|---|---|
| Копировать пакет без snapshot semantics | Быстро | Невозможно доказать исторические условия | Отклонено |
| Перезаписывать платеж при замене/отмене | Простой UI | Искажает статистику и аудит | Отклонено |
| Immutable snapshot + append-only facts | Проверяемая история и reconciliation | Больше сущностей/миграция | Принято |

## Consequences

- Удаление каталожного пакета становится archive/soft-delete, если есть выдачи.
- Баланс клиента вычисляется из obligations и facts.
- Client видит только собственный snapshot, пополнения, списания и остаток.
- Teacher не получает subscription/payment DTO и связанные realtime payload.
- Нужна миграционная сверка до/после по платежам, долгам и остаткам.

## Verification

- Integration tests подтверждают отсутствие новых payment facts при replace/cancel.
- Reconciliation SQL даёт нулевой drift по историческим платежам.
- Actor tests доказывают заявленные права каталога/выдачи и отсутствие teacher finance fields.
- Export/report totals совпадают с ledger projection.

## Design links

- `04_SYSTEM_DESIGN/commerce.md`
- `04_SYSTEM_DESIGN/reporting.md`
- `04_SYSTEM_DESIGN/access_control.md`
