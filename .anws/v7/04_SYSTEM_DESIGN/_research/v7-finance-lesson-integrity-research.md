# Исследование v7 — финансовая и lesson integrity

**Дата:** 2026-08-07  
**Область:** Commerce, Schedule, Client Card, access/audit.  
**Ограничение:** используются только существующий runtime и первичные
официальные источники; внешняя платёжная интеграция не проектируется.

## 1. Подзадачи

| Подзадача | Направление |
|---|---|
| Конкурентная покупка/сторно/перенос | PostgreSQL docs + текущие repositories |
| Безопасный повтор POST | официальный API pattern + текущий Platform Integrity |
| Неизменяемая история и ограничения | PostgreSQL constraints + текущие immutable triggers |
| Desktop/mobile Client Card flow | Flutter adaptive guidance + текущий v7 surface policy |
| Минимальная доменная модель | анализ существующих facts/projections, исключение дубликатов |

## 2. Ключевые находки

1. `SELECT ... FOR UPDATE` блокирует конкурирующих writers до конца транзакции;
   при нескольких блокировках PostgreSQL рекомендует единый порядок, иначе
   возможен deadlock. Значит payer, recipient, subscription и lesson locks
   всегда сортируются по стабильному ключу.
2. `Read Committed` подходит для предопределённых account rows при явной
   блокировке и version guards. Глобальный `Serializable` не нужен; он требует
   общего retry для `40001` и добавляет стоимость. Сложные команды остаются
   короткими и повторно проверяют данные после lock.
3. Named `CHECK`, `UNIQUE`, `FOREIGN KEY` и `EXCLUDE` должны защищать локальные
   invariants; cross-row суммы проверяет транзакционная команда/reconciliation,
   поскольку PostgreSQL не поддерживает надёжный cross-row `CHECK`.
4. Идемпотентный POST должен связывать уникальный key с fingerprint payload и
   возвращать прежний результат при точном retry, но отвергать тот же key с
   другим payload. Текущий `PlatformIntegrityService` уже реализует этот seam.
5. Flutter рекомендует различать responsive («помещается») и adaptive
   («удобно в данном пространстве»). Значит одна форма/command model получает
   desktop drawer/card и mobile full-width sheet/route, а не два flow.

## 3. Источники

- [PostgreSQL: Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
  — row locks, transaction lifetime, consistent lock ordering и deadlock retry.
- [PostgreSQL: Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
  — Read Committed/Repeatable Read/Serializable и обязательные retries.
- [PostgreSQL: Constraints](https://www.postgresql.org/docs/current/ddl-constraints.html)
  — named checks/unique/FK и ограничение cross-row checks.
- [Stripe: Idempotent requests](https://docs.stripe.com/api/idempotent_requests)
  — безопасный retry, UUID-like keys и parameter mismatch rejection.
- [Flutter: Adaptive and responsive design](https://docs.flutter.dev/ui/adaptive-responsive)
  — layout by available space и input, единая codebase.

## 4. Проверка вариантов

| Идея | Сложность | Влияние | Решение |
|---|---:|---:|---|
| Новый event-store/CQRS | высокая | низкое для пользователя | отклонить |
| Global Serializable | средняя | ограниченная | отклонить; row locks/version достаточны |
| Новая wallet table с mutable balance | средняя | риск drift | отклонить; вычислять из facts |
| Расширить существующие facts/projections | низкая | высокая | принять |
| Два UI flow для Windows/Android | высокая | отрицательное | отклонить |
| Один controller + adaptive container | низкая | высокая | принять |

## 5. Рекомендации

### P0

- переиспользовать Platform Integrity, preview token, immutable triggers и
  commerce projection;
- ввести payer, payment lifecycle/reversal exclusion и config snapshots
  аддитивной миграцией;
- направить все date/time mutations в один lesson transition;
- добавить PostgreSQL concurrency/fault/role/reconciliation tests.

### P1

- recurring schedule plan поверх существующих effective-dated series;
- одна bounded staff technical history и общая Client note;
- один adaptive form/controller на Windows и Android.

### P2

- оптимизировать проекции/индексы только по измеренному `EXPLAIN` или p95;
  кэш и отдельный read store пока не нужны.

