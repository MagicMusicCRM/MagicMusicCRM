# MagicMusicCRM v4 — Atomic Lesson Reschedule & Cancel

**Task:** T4.2.4
**Requirements:** REQ-LESSON-003, REQ-AUDIT-001
**Result:** PASS
**Date:** 2026-07-26

## Preview/confirm contract

Добавлены четыре capability-protected operation routes:

- `POST /api/crm/lessons/:id/reschedule/preview`;
- `POST /api/crm/lessons/:id/reschedule`;
- `POST /api/crm/lessons/:id/cancel/preview`;
- `POST /api/crm/lessons/:id/cancel`.

Preview требует `expectedVersion`, безопасный `reasonCode` и явный выбор
`chargeClient`/`compensateTeacher`. Reschedule preview собирает effective
successor из immutable snapshot исходного Lesson и частичного successor draft,
затем запускает единый `ScheduleConstraintEngine`. Confirm дополнительно
требует `confirm=true`, `Idempotency-Key` и `X-Request-Id`.

## Atomic transition

Confirm выполняется через `PlatformIntegrityService` в одной PostgreSQL
transaction:

1. idempotency reservation и optimistic aggregate version;
2. `FOR UPDATE` source guard: только актуальный `scheduled` Lesson;
3. resource advisory locks и повторная проверка successor;
4. deterministic successor с `predecessor_id` и immutable snapshot;
5. append-only `LessonTransition` с reason/financial decision;
6. financial transition port и release будущей reservation;
7. terminal source state и `successor_id`;
8. ровно один audit и transactional outbox event.

Cancel использует ту же boundary без successor. Terminal source нельзя
повторно перевести в другое состояние; повтор идентичной команды возвращает
сохранённый result.

## Rollback evidence

PostgreSQL integration test доказывает:

- конфликтующий successor возвращает unified violations, source остаётся
  `scheduled`, version `1`, successors/transitions `0/0`;
- injected commerce failure после domain writes откатывает source, successor,
  transition, version, audit и outbox;
- success создаёт terminal `rescheduled` source version `2`, один scheduled
  successor с `predecessor_id`, один transition и один audit;
- cancel создаёт terminal `cancelled` source version `2`.

## Проверки

| Gate | Result |
|---|---:|
| Exact PostgreSQL integration suite | 1/1 suite, 1/1 test |
| Conflict rollback | source unchanged, successor/transition 0/0 |
| Injected commerce failure rollback | PASS |
| Successful source/successor/transition/audit | 1/1/1/1 |
| Cancel terminal transition | PASS |
| Actor Matrix | 1536/1536 decisions, 1244 allow, 292 deny |
| Access coverage | 256/256 private routes, unexplained allow 0 |
| Current-state inventory | 268 routes, 593 DTO fields, 0 unowned |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 127/127 suites, 1070/1070 tests |

Exact command:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/schedule/reschedule-postgres.integration.spec.ts
```
