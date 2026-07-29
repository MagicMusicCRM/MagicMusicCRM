# MagicMusicCRM v4 — Lesson Lifecycle Schema

**Task:** T4.1.1
**Requirements:** REQ-LESSON-001, REQ-LESSON-002, REQ-LESSON-003
**Result:** PASS
**Date:** 2026-07-26

## Реализованный контракт

Миграция `0083_lesson_lifecycle_schema` добавляет к `app.lessons`
монотонную `version`, явный `lifecycle_state` и однозначные
`predecessor_id`/`successor_id`. Разрешены только:

- `scheduled`;
- `successfully_completed`;
- `cancelled`;
- `rescheduled`.

Legacy `status` остаётся compatibility façade: `completed` отображается в
`successfully_completed`, а изменения нового состояния синхронизируются
обратно. Возврат из terminal state в `scheduled` отклоняется PostgreSQL.

## Неизменяемые факты

- `app.lesson_snapshots` хранит один immutable command snapshot на урок:
  typed ClientRef, completion type, client charge, teacher compensation,
  subscription и trial marker.
- Однозначные legacy Lead/Student rows получают
  `origin=legacy_backfill`; неполные данные маркируются
  `validation_state=legacy_incomplete`, а не дополняются догадками.
- `app.lesson_transitions` хранит одну append-only terminal transition.
  Client/teacher financial fact references уникальны глобально.
- Runtime UPDATE/DELETE snapshot и transition отклоняются trigger-ом.

## Reservation lifecycle и версии

`app.lesson_reservations` запрещает duplicate reservation для одной пары
lesson/subscription и больше одного active reservation на lesson. Состояния
`consumed`, `released` и `cancelled` terminal; возврат в `reserved`
невозможен. Terminal update атомарно ставит `terminal_at` и увеличивает
версию.

Версия Lesson синхронизируется с `app.aggregate_versions` под типом
`schedule:lesson`, включая случаи, когда `version` увеличена BEFORE trigger-ом
при compatibility update.

## Repository boundary

`LessonLifecycleRepository` предоставляет typed операции чтения lifecycle,
создания snapshot, append terminal transition и создания reservation через
переданный `PoolClient`, чтобы последующие command services могли включать
их в одну Platform Integrity transaction.

## Проверки

| Gate | Result |
|---|---:|
| Exact PostgreSQL lifecycle scenario | 1/1 |
| Legacy status compatibility | PASS |
| Immutable/duplicate/illegal transition constraints | PASS |
| Reservation terminal version + aggregate version | PASS |
| Migration `0083` down → up | PASS |
| Actor Matrix + payload leak | 2/2 suites, 8/8 tests |
| Route decisions | 1488/1488 |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 120/120 suites, 1054/1054 tests |
| Access coverage | 248/248 private routes |
| Current-state inventory | 260 routes, 564 DTO fields, 0 unowned |

Exact command:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/lesson-schema-postgres.integration.spec.ts
```
