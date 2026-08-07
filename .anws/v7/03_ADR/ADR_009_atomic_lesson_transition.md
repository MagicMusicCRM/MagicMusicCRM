# ADR-009 — Единый атомарный lesson transition

## Статус

Accepted

## Дата

2026-08-07

## Контекст

Сейчас lifecycle-команды уже поддерживают preview/reason/idempotency, но прямой
PATCH занятия может менять дату/время в обход settlement. v7 требует одинаковый
результат из calendar drag, editor, Client Card tray и bulk operation.

## Факторы влияния

- ни одна точка переноса не может обходить причину и финансовое решение;
- source/successor, subscription hours и teacher accrual должны commit-иться
  вместе;
- конфликт или нехватка часов откатывают весь переход;
- система уже работает в одном NestJS/PostgreSQL deployable.

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

## Последствия

### Положительные

- одинаковое поведение всех UI entry points;
- ошибка в расчёте не оставляет перенесённое без списания;
- типы и ставки сохраняются immutable snapshots.

### Отрицательные

- старый editor/drag path нужно перевести на command API;
- group lessons требуют массив client decisions и один teacher decision.

### Дальнейшие действия

- расширить DTO preview/commit и financial port;
- подключить все Flutter entry points к одному controller;
- regression tests для double charge warning, concurrency и rollback.

## Influence scope

- `SYS-SCHEDULE`
- `SYS-COMMERCE-INTEGRITY`
- `SYS-CRM-WORKSPACE`
- `SYS-PLATFORM-QUALITY`

