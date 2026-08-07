# ADR-007 — Финансово-учебный runtime v7

- **Статус:** Accepted
- **Дата:** 2026-08-07
- **Решение:** расширить существующий модульный монолит NestJS/PostgreSQL и
  существующий Flutter-клиент без нового runtime, брокера или зависимости.

## Контекст и ограничения

v7 добавляет денежно-критичные команды: покупку/отмену абонемента с отдельным
плательщиком, рассрочку, сторно оплат, расчёт занятия и постоянные расписания.
Нужны атомарность, идемпотентность, неизменяемая история, RBAC/resource scope,
reconciliation с нулевым расхождением и прежние Windows/Android-клиенты.

Проект уже использует Flutter/Riverpod/GoRouter, NestJS, `pg` и PostgreSQL; в
backend существуют транзакционные commerce-команды, version guards,
idempotency, audit/outbox, capability registry и PostgreSQL integration tests.
Штатная нагрузка CRM не обосновывает отдельный сервис или event-store. Новая
инфраструктура увеличила бы срок, TCO и число распределённых отказов без
пользовательской ценности.

## Сравнение вариантов

Оценка 1–5; соответствие, безопасность, навыки и скорость имеют наибольший
вес для этой версии.

| Измерение | Вес | A: текущий монолит | B: CQRS/event store | C: commerce microservice |
|---|---:|---:|---:|---:|
| Соответствие требованиям | 5 | 5 | 4 | 4 |
| Масштабируемость | 3 | 4 | 5 | 5 |
| Производительность | 3 | 5 | 4 | 4 |
| Безопасность | 5 | 5 | 4 | 3 |
| Навыки команды | 5 | 5 | 2 | 2 |
| Рынок талантов | 2 | 5 | 3 | 4 |
| Скорость разработки | 5 | 5 | 2 | 2 |
| TCO | 4 | 5 | 2 | 2 |
| Экосистема | 2 | 5 | 4 | 5 |
| Долгосрочная поддержка | 3 | 5 | 3 | 3 |
| Интеграции | 2 | 5 | 4 | 4 |
| AI-интеграции | 1 | 4 | 4 | 4 |
| **Взвешенный итог / 200** |  | **194** | **126** | **128** |

## Решение

1. Денежные и lesson-команды остаются в существующих NestJS commerce/schedule
   модулях и выполняются одной PostgreSQL-транзакцией.
2. История реализуется append-only доменными фактами, reversal/exclusion links
   и существующим audit/outbox, а не новым event-sourcing framework.
3. `SELECT ... FOR UPDATE`, aggregate version и idempotency key защищают
   конкурентные операции; PostgreSQL constraints защищают суммы и lifecycle.
4. Существующий capability registry получает только необходимые client-finance
   действия; resource scope проверяет и получателя, и плательщика.
5. Flutter переиспользует текущие service/provider/navigation seams. Все точки
   переноса вызывают один preview/commit API, а не прямые date/time PATCH.
6. Новые npm/pub зависимости не добавляются.

## Стратегия проверки

- Unit/contract tests фиксируют lifecycle, pure calculations и отсутствие
  прямых обходных callsites.
- PostgreSQL integration tests являются главным gate для денег, часов,
  concurrency, rollback, idempotency и actor scope.
- Flutter widget tests проверяют формы, role projection, причины и responsive
  states; Windows/Android smoke проходят реальные API-пути.
- После каждой рискованной волны запускаются targeted suites, затем full backend
  и Flutter regression. Перед релизом обязательны migration down→up,
  reconciliation дважды без drift, Actor Matrix и пятиаккаунтный UAT.

## Influence scope

- `SYS-COMMERCE-INTEGRITY`
- `SYS-SCHEDULE`
- `SYS-CRM-WORKSPACE`
- `SYS-ACCESS-SCOPE`
- `SYS-OPERATIONS`
- `SYS-PLATFORM-QUALITY`

## ATAM-сценарии

- Два сотрудника покупают абонемент с одного счёта: ровно одна команда может
  потратить доступный остаток; вторая получает version/funds conflict.
- Сбой между списанием и выдачей часов: транзакция откатывает оба факта.
- Повтор запроса после timeout: idempotency возвращает прежний результат.
- Изменение каталога: уже рассчитанное занятие читает snapshot, не новый rule.
- Admin сторнирует оплату: balance/reports пересчитываются, исходный факт и
  причина остаются staff-visible, Teacher/Client не получают поля аудита.
- Роль отозвана в открытой форме: commit повторно проверяет current capability
  и scope; скрытый frontend state не даёт права.

## Последствия

Положительные: минимальная поверхность изменений, одна ACID-граница, повторное
использование проверенного RBAC/audit/reconciliation и отсутствие операционного
развёртывания нового сервиса.

Отрицательные: commerce и schedule остаются связаны внутри монолита; миграции и
команды нужно держать небольшими, а отчётные проекции — индексированными. Если
измеренная нагрузка когда-либо перестанет помещаться в один PostgreSQL runtime,
границей выделения станет append-only ledger/outbox, но v7 этого не требует.
