# ADR-008 — Серверный жизненный цикл занятия и единый constraint engine

**Status:** Accepted  
**Date:** 2026-07-25  
**Influence scope:** SYS-SCHEDULE, SYS-COMMERCE, SYS-CRM, SYS-PLATFORM, SYS-APP  
**Requirements:** REQ-LESSON-001, REQ-LESSON-002, REQ-LESSON-003, REQ-SCHED-001, REQ-SCHED-002, REQ-SCHED-003, REQ-TEACHER-001

## Context

Посещаемость больше не является вводимым статусом. Занятие должно завершаться автоматически после своего конца, применяя заранее выбранные тип завершения, клиентское списание и оплату преподавателя. Создание/перенос должно учитывать клиента любого типа, часы филиала, доступность преподавателя, кабинет, филиалы преподавателя и остаток абонемента.

Размещение этих правил только во Flutter создаёт обход через API, гонки между вкладками и расхождение денег с расписанием.

## Decision

1. SYS-SCHEDULE владеет явной state machine: `scheduled → successfully_completed | cancelled | rescheduled`.
2. Attendance write-model и endpoint mutations выводятся из active domain. Клиентская метрика посещений вычисляется из количества `successfully_completed`.
3. При создании сохраняется immutable financial/completion snapshot: тип успешного завершения, способ списания, стоимость, teacher compensation type/value, trial flag и выбранный ClientRef (`lead|student`).
4. Background worker claim-ит просроченное `scheduled` занятие по версии и в одной PostgreSQL-транзакции:
   - переводит его в terminal success;
   - применяет ровно одно списание/долг;
   - применяет ровно одно начисление преподавателю;
   - освобождает reservation;
   - пишет audit/outbox.
5. Создание, редактирование, series-create, drag/drop и перенос проходят один серверный constraint engine.
6. Constraint engine возвращает структурированные violations: branch hours, teacher availability, teacher branch, teacher/client/room overlap, client reference, required financial fields, subscription capacity.
7. Создание/перенос при конфликте запрещено. Только `system_admin` может применить явный audited override с причиной; UI обычных бизнес-ролей не предлагает обход.
8. Перенос терминализирует исходное занятие с reason/write-off/teacher-pay decision и атомарно создаёт successor с `predecessorId`.
9. UI-цвет является projection состояния, а не редактируемым типом.

## Options considered

| Option | Плюсы | Минусы | Решение |
|---|---|---|---|
| Cron обновляет только статус | Просто | Деньги и reservations могут разойтись | Отклонено |
| Клиент завершает по таймеру | Нет backend worker | Не работает без открытого клиента, гонки | Отклонено |
| Durable server worker + единая transaction | Повторяемость и финансовая целостность | Требует claim/idempotency | Принято |

## Consequences

- Старые attendance-данные сохраняются для миграции/аудита, но не редактируются.
- Все schedule write-paths используют один service contract.
- Required teacher branches должны быть заполнены до включения strict constraint.
- Successor после переноса — отдельная запись; история не перезаписывается.
- Уведомления публикуются только после commit.

## Verification

- Unit property tests проверяют interval overlaps и границы рабочих часов.
- Integration tests запускают два worker claim и получают одно списание/начисление.
- Contract tests доказывают одинаковые violations для create/edit/series/drag/reschedule.
- E2E подтверждает read-only teacher calendar и отсутствие attendance controls/API access.

## Design links

- `04_SYSTEM_DESIGN/schedule_lifecycle.md`
- `04_SYSTEM_DESIGN/commerce.md`
- `04_SYSTEM_DESIGN/platform_integrity.md`
