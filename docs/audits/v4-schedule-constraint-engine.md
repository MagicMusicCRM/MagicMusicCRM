# MagicMusicCRM v4 — Unified Schedule Constraint Engine

**Task:** T4.2.1
**Requirements:** REQ-SCHED-001, REQ-SCHED-002
**Result:** PASS
**Date:** 2026-07-26

## Контракт

`ScheduleConstraintEngine` принимает один complete scheduling draft:

- typed `ClientRef` (`lead|student`);
- Teacher, Branch и Room refs;
- UTC `startAt/endAt`;
- optional `excludeLessonId`.

Результат всегда имеет форму `{ valid, violations[] }`. Нарушения
детерминированно упорядочены по стабильному code order, resource ref и
конфликтующим Lesson refs. Engine возвращает все найденные нарушения одним
ответом, не применяя short-circuit после первого конфликта.

## Pure rules

- интервалы имеют half-open семантику `[startAt, endAt)`;
- `startAt < endAt`, соседние интервалы не пересекаются;
- Lesson должен целиком помещаться в effective BranchHours;
- effective TeacherBranch должен покрывать локальные даты интервала;
- явная unavailability, пересекающая Lesson, блокирует;
- если есть положительные availability rules, одна из них должна целиком
  покрывать Lesson; без положительных rules действует open default;
- бессрочная unavailability поддерживается как interval с `endsAt = null`.

## PostgreSQL conflicts

Repository выполняет отдельные sargable arms для Teacher, ClientRef и Room.
Они используют существующие resource/time indexes:

- `lessons_teacher_active_overlap_idx`;
- `lessons_room_active_overlap_idx`;
- `lessons_student_scheduled_idx`;
- `lessons_lead_scheduled_idx`.

В выборку входят только non-deleted `lifecycle_state = scheduled` Lessons.
Точное пересечение проверяется как `existing.start < draft.end` и
`existing.end > draft.start`. `excludeLessonId` применяется внутри каждого
arm до объединения результатов.

## Проверки

| Gate | Result |
|---|---:|
| Backend typecheck | PASS |
| Backend build | PASS |
| Exact Unit + PostgreSQL suites | 2/2 suites, 6/6 tests |
| Generated half-open boundary cases | PASS |
| Branch hours/availability/assignment rules | PASS |
| Teacher/Client/Room overlap refs | PASS |
| Adjacent interval / `excludeLessonId` | PASS |
| Cross-branch mismatch | PASS |
| Full backend regression | 124/124 suites, 1067/1067 tests |

Exact command:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/constraint-engine.spec.ts src/crm/schedule/constraint-engine-postgres.integration.spec.ts
```
