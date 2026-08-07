# ADR-009 — Единый атомарный lesson transition

## Статус

Accepted

## Дата

2026-08-07

## Контекст

Lifecycle-команды поддерживают preview/reason/idempotency, но lesson create ещё
хранит legacy расчёт, а worker только ставит `settlement_pending`. Владелец
уточнил: обе независимые настройки выбираются до назначения, затем worker
применяет их автоматически; исключения исправляются append-only correction.

## Факторы влияния

- ни одна точка переноса не может обходить причину и финансовое решение;
- source/successor, subscription hours и teacher accrual должны commit-иться
  вместе;
- конфликт или нехватка часов откатывают весь переход;
- система уже работает в одном NestJS/PostgreSQL deployable.
- выбранное решение должно переживать изменение/архивацию каталога;
- ошибка worker не может оставлять частичные client/teacher facts;
- post-terminal correction не переписывает исторические факты.

## Варианты

### A. Оставить несколько PATCH и добавить UI-подсказки

- Плюс: малый первоначальный diff.
- Минус: backend invariant отсутствует; новый caller снова обойдёт расчёт.

### B. Schedule transition вызывает один Commerce port в общей транзакции

- Плюсы: единый invariant и ACID rollback без нового runtime.
- Минус: нужен строгий односторонний port и миграция всех callsites.

### C. Асинхронная saga между отдельными сервисами

- Плюс: deploy independence.
- Минусы: временная финансовая несогласованность и компенсационные операции без
  существующей потребности в отдельном deploy.

## Решение

Выбран B. Все date/time mutations используют один preview/commit transition.
Schedule владеет временной частью и конфликтами; Commerce через существующий
financial-decision port валидирует client settlement и рассчитывает выбранную
вручную teacher compensation. Source/successor, reservation/settlement/accrual,
audit/outbox фиксируются в одной PostgreSQL-транзакции.

Teacher/room-only change использует ту же reason-command, но не создаёт client
settlement. Bulk transition содержит одну причину и один aggregate preview.
Прямой date/time PATCH запрещается contract/inventory test.

Create/plan row обязаны содержать `PlannedLessonSettlement`, проверенный Commerce
port и привязанный к immutable configuration revisions. До начала versioned edit
атомарно заменяет decision и reservations. После конца worker вызывает тот же
settlement port внутри общей transaction; transient errors retry, domain/poison
переводят lesson в `settlement_pending` без финансовых фактов.

Post-terminal correction — отдельный preview/commit: reversal/exclusion старого
effective settlement и optional replacement создаются одной транзакцией. Lesson
history и исходные facts остаются неизменяемыми.

## Последствия

### Положительные

- одинаковое поведение всех UI entry points;
- ошибка в расчёте не оставляет перенесённое без списания;
- типы и ставки сохраняются immutable snapshots.
- штатный путь больше не требует ручной очереди после каждого занятия;
- исправления после проведения не искажают audit или ordinary reporting.

### Отрицательные

- старый editor/drag path нужно перевести на command API;
- group lessons требуют массив client decisions и один teacher decision.

### Дальнейшие действия

- расширить create/plan/correction DTO, worker и financial port;
- подключить все Flutter entry points к одному controller;
- regression tests для double charge warning, concurrency и rollback.

## Influence scope

- `SYS-SCHEDULE`
- `SYS-COMMERCE-INTEGRITY`
- `SYS-CRM-WORKSPACE`
- `SYS-PLATFORM-QUALITY`
