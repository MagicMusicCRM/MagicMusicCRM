# T4.2.5 — No-attendance domain evidence

**Дата:** 2026-07-26
**Требование:** REQ-LESSON-002
**ADR:** ADR-008
**Результат:** PASS

## Закрытый write-domain

- Удалены `GET/PATCH /crm/lessons/:id/attendance`, `AttendanceService` и `UpsertAttendanceDto`.
- Общий `PATCH /crm/lessons/:id` больше не записывает `status`; direct service call с `status` возвращает `MANUAL_LESSON_LIFECYCLE_FORBIDDEN`.
- DTO принимает только compatibility-значение `scheduled` при создании; `completed/cancelled/missed` не проходят глобальную валидацию.
- Из Flutter удалены attendance API, диалог, ручное завершение пробного/обычного урока и generic status/cancel controls.
- Inventory требует ровно `0` active attendance mutations и теперь является release guard, а не только отчётом о долге.

## Derived metric и migration note

Migration `0086_attendance_read_only_success_metric`:

1. сохраняет `app.lesson_participation` и все исторические строки;
2. оставляет runtime-роли `magiccrm_app` только `SELECT`, отзывая `INSERT/UPDATE/DELETE/TRUNCATE`;
3. создаёт `app.client_lesson_success_metrics`;
4. считает `successfully_completed_lessons` только по `app.lessons.lifecycle_state = 'successfully_completed'`;
5. не использует `status`, `attendance_kind`, `pass_reason` или другие legacy attendance-поля.

Rollback возвращает прежние DML grants и удаляет view; проверка down→up прошла.

## Regression contract

`server/src/crm/schedule/no-attendance-mutations.contract.spec.ts` доказывает:

- attendance route/service/DTO отсутствуют;
- ручной completion отклоняется DTO и service boundary до persistence;
- legacy evidence доступен runtime-роли на чтение и недоступен для mutation;
- view count равен прямому count terminal-success уроков и игнорирует legacy attendance row.

## Quality gates

| Gate | Результат |
|---|---:|
| Exact no-attendance contract | 1/1 suite, 2/2 tests |
| Schedule targeted regression | 1/1 suite, 53/53 tests |
| Migration down→up | PASS |
| Backend typecheck/build | PASS / PASS |
| Full backend | 127/127 suites, 1059/1059 tests |
| Actor Matrix | 254 routes × 6 actors = 1524/1524 decisions |
| Actor decisions | 1234 allow, 290 deny |
| Access coverage | 254/254 private routes, unexplained allow = 0 |
| Current-state inventory | 266 routes, 591 DTO fields, 0 unowned |
| Active attendance mutations | 0 |
| Flutter analyze | No issues found |
| Flutter tests | 398/398 |

## Acceptance

- Direct attendance endpoint: отсутствует.
- Direct manual completion through generic Lesson update: заблокирован.
- Исторические attendance rows: сохранены read-only.
- Client success metric: совпадает с количеством `successfully_completed`.
