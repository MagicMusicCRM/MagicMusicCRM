# MagicMusicCRM v4 — Schedule Reference Data

**Task:** T4.1.2
**Requirement:** REQ-SCHED-002
**Result:** PASS
**Date:** 2026-07-26

## Schema и timezone contract

Миграция `0084_schedule_reference_data` добавляет:

- IANA `timezone_name` и optimistic `schedule_reference_version` филиала;
- регулярные `branch_hours` и date-specific
  `branch_hour_exceptions`;
- recurring/interval `teacher_availability_rules`, включая разовую и
  бессрочную недоступность;
- effective dates/version для существующих `teacher_branches`;
- отдельную reference version преподавателя.

Timezone принимается только из PostgreSQL `pg_timezone_names`. Local dates и
wall-clock times хранятся отдельно от UTC instants; read projection переводит
их в `timestamptz` через IANA timezone. Поэтому DST gap/offset и границы дат
разрешаются базой однозначно, без фиксированного offset-предположения.
Legacy `utc_offset_minutes` сохранён для старого façade.

## Reference API

- `GET /api/crm/schedule-reference` — branch windows, teacher rules,
  effective branch assignment и версии на bounded UTC interval.
- `PUT /api/crm/schedule-reference/branches/:branchId/hours` — атомарная
  замена weekly hours/exceptions/timezone.
- `PUT /api/crm/schedule-reference/teachers/:teacherId/branches` — атомарная
  замена одной/нескольких effective-dated branch assignments.
- `PUT /api/crm/schedule-reference/teachers/:teacherId/availability` —
  атомарная замена recurring/interval rules.

Все write contracts требуют `expectedVersion`; stale update возвращает
conflict и не меняет reference rows. Teacher читает только собственную
проекцию. Операционные записи проходят `schedule.lesson.write` и
`CrmPolicy.assertManagerOnly`, то есть approved staff package; client/teacher
write закрыт.

## Preflight

Read-only preflight учитывает `active_from`/`active_until` при проверке
будущего урока и добавляет отдельный blocker
`schedule.active-teacher-branch-missing`. Повторный scan стабилен и отклоняет
write probe с SQLSTATE `25006`. На текущем production-shaped fixture найден
один адресуемый active Teacher без действующего филиала; данные не исправлялись
автоматически.

## Проверки

| Gate | Result |
|---|---:|
| Unit + exact PostgreSQL availability | 2/2 suites, 5/5 tests |
| Europe/Berlin DST local→UTC fixture | PASS |
| Date exception + two branches + indefinite unavailable | PASS |
| Optimistic version conflict / invalid timezone | PASS |
| Migration `0084` down → up | PASS |
| Read-only preflight | 16 checks, stable, 1 teacher-branch blocker |
| Actor Matrix + payload leak | 2/2 suites, 8/8 tests |
| Route decisions | 1512/1512 (1228 allow, 284 deny) |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 122/122 suites, 1061/1061 tests |
| Access coverage | 252/252 private routes |
| Current-state inventory | 264 routes, 566 DTO fields, 0 unowned |

Exact command:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/availability.spec.ts src/crm/schedule/availability-postgres.integration.spec.ts
```
