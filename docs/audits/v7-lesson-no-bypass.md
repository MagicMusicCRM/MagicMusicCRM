# v7 — T3.1.4 Lesson no-bypass boundary

**Дата:** 2026-08-07

**Статус:** PASS

## Реализовано

- Completion worker после истечения времени переводит Lesson из `scheduled` в `settlement_pending`, создаёт один audit/outbox и не создаёт transition, client charge, teacher compensation или reservation terminalization.
- Только явный подписанный `settle` сотрудника переводит `settlement_pending` в `successfully_completed` и создаёт финансовые факты один раз.
- Migration `0110` добавляет промежуточное состояние в DB lifecycle и разрешает terminal transition как из `scheduled`, так и из `settlement_pending`; down fail-closed при наличии новых фактов.
- Общий fail-closed guard разрешает прямому `PATCH /crm/lessons/:id` менять только заметку. Время, длительность, преподаватель, филиал, аудитория, клиент, тип занятия и финансовые поля требуют transition API независимо от legacy/v4 feature path.
- Добавлены `POST /crm/lessons/transitions/bulk/preview` и `POST /crm/lessons/transitions/bulk`: одна причина, один HMAC preview, один idempotency/audit/outbox aggregate и до 500 typed операций.
- Bulk блокирует Lesson в стабильном UUID-порядке и выполняется в одной PostgreSQL-транзакции. Stale version, conflict, insufficient capacity или любой fault откатывает все source/successor/facts/transitions.
- Inventory распознаёт только фактическую запись `scheduled_at`/`duration_minutes` и падает при появлении temporal caller вне явного allowlist. Защищённые production callsites сведены к create/series/transition boundary.
- Flutter отображает промежуточное состояние как `Ожидает расчёта`; старый несуществующий import в device smoke исправлен.

## Проверки

| Gate | Результат |
|---|---:|
| Completion worker concurrency/restart/retry | PASS; pending, finance facts = 0 |
| Explicit settle after pending | 1 transition, exact client/teacher facts |
| Protected PATCH contract | 11/11 protected/empty/notes cases |
| Bulk success/replay | 2 lessons, 2 transitions, no duplicates |
| Bulk stale rollback | first/second writes = 0 |
| Migration `0110` down→up | PASS |
| Schedule regression | 9/9 suites, 27/27 tests |
| Full backend | 154/154 suites, 1209/1209 tests |
| Backend typecheck / build | PASS / PASS |
| Flutter analyze / state palette | clean / 7/7 |
| Access coverage | 290/290 private routes, unexplained allow = 0 |
| Shadow compare | 1740 access + 2000 schedule decisions, unexplained = 0 |
| Current-state inventory | routes = 302, DTO fields = 739, unowned = 0 |
| v7 mutation inventory | finance = 243, lesson mutations = 7, unknown callers = 0 |

## Вывод

Критерии T3.1.4 выполнены: время само по себе больше не создаёт финансовый факт, прямой PATCH не обходит decision flow, а массовый переход имеет одну signed-preview и ACID-границу. Следующая задача T3.1.5 подключает этот контракт ко всем Flutter entry points и удаляет protected `updateLesson` callsites.

