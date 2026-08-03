# ADR-011 — Версии агрегатов, idempotency и transactional outbox

**Status:** Accepted  
**Date:** 2026-07-25  
**Influence scope:** SYS-PLATFORM, все write-системы, SYS-APP  
**Requirements:** REQ-LESSON-002, REQ-LESSON-003, REQ-SUB-002, REQ-SUB-004, REQ-TASK-001, REQ-TASK-002, REQ-NAV-002, REQ-AUDIT-001

## Context

Повтор API-запроса, два worker-процесса или одновременные вкладки могут дважды закрыть задачу, списать занятие или создать финансовый факт. Простая UI-блокировка не защищает сервер и не переживает сетевые retry.

## Decision

1. Изменяемые aggregates имеют monotonic `version`.
2. Mutation command передаёт expected version, если изменяет существующий aggregate.
3. Создание и side-effect операции передают `Idempotency-Key`, scoped по actor + operation.
4. Сервер сохраняет request fingerprint и result reference. Тот же key + тот же fingerprint возвращает прежний результат; другой fingerprint возвращает conflict.
5. Business mutation, audit и outbox event фиксируются в одной PostgreSQL-транзакции.
6. Outbox dispatcher публикует committed invalidation с event id; consumers дедуплицируют по event id.
7. Worker использует `FOR UPDATE SKIP LOCKED`/эквивалентный durable claim и terminal-state guard.
8. Shared task close, lesson completion, payment, subscription issue/replace/cancel и inbound lead ingestion обязательно используют этот протокол.

## Options considered

| Option | Плюсы | Минусы | Решение |
|---|---|---|---|
| UI debounce/disabled button | Дёшево | Не защищает retry, вкладки и worker | Отклонено |
| Distributed lock в Redis | Быстрый lock | Истина отдельно от PostgreSQL, recovery сложнее | Отклонено как primary |
| PostgreSQL version + idempotency + outbox | Одна durable boundary | Нужна уборка ключей/dispatcher | Принято |

## Consequences

- Redis допустим для wake-up/coordination, но не доказывает совершение операции.
- Conflict является штатным API-состоянием, которое UI обязан показать.
- Idempotency retention задаётся по типу операции; финансовые ссылки сохраняются дольше технического payload.
- Realtime может быть доставлен повторно и не несёт полномочия изменить source state.

## Verification

- Parallel integration tests отправляют одинаковые и конфликтующие команды.
- Kill-after-commit test доказывает, что outbox будет доставлен после restart.
- Duplicate realtime event не создаёт второй UI-side effect.
- Audit request id и domain result сопоставимы.

## Design links

- `04_SYSTEM_DESIGN/platform_integrity.md`
- `04_SYSTEM_DESIGN/schedule_lifecycle.md`
- `04_SYSTEM_DESIGN/commerce.md`
- `04_SYSTEM_DESIGN/workflow_tasks.md`
