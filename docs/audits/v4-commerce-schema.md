# V4 catalog/snapshot/ledger schema — T5.1.2

**Дата:** 2026-07-29

**Требования:** REQ-SUB-001, REQ-SUB-002, REQ-SUB-003

**Результат:** PASS

## Что реализовано

- Migration `0089` расширяет существующий каталог
  `app.subscription_packages`: цена хранится как `base_price_minor`,
  добавлены `currency_code` и monotonic `version`. Legacy `price` остаётся
  совместимым и синхронизируется trigger-ом.
- `app.subscriptions` остаётся lifecycle aggregate, но получает immutable
  commercial snapshot: JSON + snapshot/package versions, базовую и финальную
  цену в minor units, currency и взаимоисключающие percent/fixed discount
  поля.
- Snapshot защищён PostgreSQL trigger-ом: lifecycle status, usage и aggregate
  version можно менять, commercial terms и саму выданную запись —
  `UPDATE/DELETE` нельзя.
- Добавлены `subscription_installments`,
  `subscription_obligation_facts` и `subscription_lifecycle_events` с
  constraints/indexes и явными ссылками на issued subscription.
- Существующие `app.payments` стали append-only ActualPayment facts:
  `amount_minor`, issued-subscription link и idempotency
  key/fingerprint; destructive writes отклоняются БД.
- Obligation и lifecycle facts также append-only. Существующие Lesson charge
  и teacher compensation facts остаются защищены immutable trigger-ами.
- Добавлены typed entities и `CommerceSchemaRepository` для последующих
  catalog/issue/replace/cancel задач без изменения текущих HTTP API.

## Скидки и teacher compensation

- Процентная скидка хранится в basis points и проверяется от указанной базовой
  суммы: `8000 ₽ − 20% = 6400 ₽`.
- Фиксированная скидка хранится в minor units; percent и fixed
  взаимоисключающие, причина обязательна, `final_price_minor ≥ 0`.
- В teacher compensation ничего не добавлялось: остаются только
  `fixed/hourly/none`, процентной оплаты преподавателя нет.

## Верификация

- exact PostgreSQL schema suite — **1/1 suite, 2/2 tests PASS**;
- mutable catalog → immutable percent/fixed snapshots — **PASS**;
- payment/obligation/lifecycle/Lesson fact `UPDATE/DELETE` rejection —
  **PASS**;
- installments и minor-unit totals fixture — **PASS**;
- migration `0089` down→up — **PASS**;
- targeted commerce/lesson/client regression —
  **5/5 suites, 16/16 tests PASS**;
- backend full Jest/PostgreSQL —
  **130/130 suites, 1073/1073 tests PASS**;
- backend typecheck — **PASS**;
- backend build — **PASS**;
- v4 inventory — **266 routes, 591 DTO fields, 5 tracked schema inventories,
  unowned=0, PASS**.

API routes и Flutter-код в задаче не менялись. Тестовый cleanup Client archive
использует `session_replication_role=replica`, чтобы удалять fixture payment,
не ослабляя production immutable trigger.
