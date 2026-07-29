# MagicMusicCRM v4 — Atomic LessonSeries

**Task:** T4.2.3
**Requirements:** REQ-SCHED-003, REQ-SCHED-001
**Result:** PASS
**Date:** 2026-07-26

## Command boundary

`POST /api/crm/schedule-series` теперь направлен в
`LessonSeriesCommandService` и требует `Idempotency-Key`/`X-Request-Id`.
Команда принимает один typed `ClientRef` (`lead|student`), complete Lesson
template, weekly recurrence и конечный локальный период. UUID серии и каждого
occurrence детерминированы actor-scoped idempotency key и локальной датой.

`LessonSeries` сохраняет:

- recurrence period, weekday, local time и occurrence count;
- IANA timezone филиала, в которой интерпретируется recurrence;
- ClientRef и resources;
- immutable completion/client-charge/teacher-compensation template;
- trial/subscription refs и aggregate version.

List API возвращает typed `clientRef`, timezone, version, occurrence count и
финансовый template; фильтр поддерживает `clientType + clientId`.

## Atomic planning

Внутри одной Platform Integrity transaction команда:

1. резервирует idempotency key и aggregate version;
2. разворачивает все локальные даты через PostgreSQL `AT TIME ZONE` филиала;
3. собирает complete drafts общим `LessonRequiredFieldValidator`;
4. захватывает те же Branch/Client/Room/Teacher advisory locks;
5. проверяет каждый occurrence единым `ScheduleConstraintEngine`;
6. только после успешной проверки всего набора записывает Series;
7. записывает все Lessons и по одному immutable `LessonSnapshot`;
8. фиксирует audit/outbox и replay result.

При нарушении команда возвращает
`LESSON_SERIES_CONSTRAINT_VIOLATIONS`, zero-based `failedIndex`, локальную
дату/UTC interval/timezone и structured violations. Transaction rollback
удаляет idempotency/version/Series/Lesson/snapshot/audit/outbox partial state.

## DST и rollback evidence

PostgreSQL fixture использует `America/New_York` и три понедельника вокруг
окончания DST 2026. Локальные `11:00` корректно развернулись в:

- `2026-10-26T15:00:00.000Z`;
- `2026-11-02T16:00:00.000Z`;
- `2026-11-09T16:00:00.000Z`.

Конфликт во втором occurrence (`failedIndex = 1`) вернул все
Teacher/Client/Room refs; после rollback persisted Series/Lessons = `0/0`.
Валидный вызов создал `3/3` Lessons/Snapshots, а повтор с тем же
idempotency key оставил ровно три Lesson.

## Проверки

| Gate | Result |
|---|---:|
| Migration `0085` down→up | PASS |
| Exact PostgreSQL integration suite | 1/1 suite, 1/1 test |
| Nth conflict / persisted Series+Lessons | index 1 / 0+0 |
| Valid DST series / immutable snapshots | 3/3 |
| Idempotent replay / duplicate Lessons | PASS / 0 |
| Actor Matrix | 1512/1512 decisions |
| Access coverage | 252/252 private routes, unexplained allow 0 |
| Current-state inventory | 264 routes, 584 DTO fields, 0 unowned |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 126/126 suites, 1069/1069 tests |

Exact command:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/lesson-series-postgres.integration.spec.ts
```
