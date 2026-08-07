# v7 — T4.1.2 Schedule plan end and bounded tray

**Дата:** 2026-08-07

**Статус:** PASS

## Реализовано

- `POST /crm/schedule-plans/:id/end/preview` возвращает actor-bound HMAC preview token на 5 минут и точный impact по active series, будущим unsettled Lessons, reservations и уже terminal Lessons.
- `POST /crm/schedule-plans/:id/end` требует version, тот же last date/reason, подтверждение и idempotency metadata. Один `schedule:plan` commit заканчивает Plan/Series, переводит только Lessons после last date из `scheduled|settlement_pending` в `cancelled`, пишет `schedule.plan.end` transition с zero-financial decision и освобождает reservations.
- Preview fingerprint включает версии и состав Plan/Series/Lessons/reservations. Любое изменение после preview даёт stale reject; injected fault откатывает Plan, Series, Lessons, transitions, reservations, audit и outbox целиком.
- `GET /crm/schedule-plans/:id/tray` использует actor-scoped projection и opaque cursor `(scheduled_at,id)`, возвращает не более 40 элементов, local date/time, lifecycle, settlement/relation markers, преподавателя и аудиторию. История доступна после завершения.
- Список планов возвращает все активные и не более 20 последних завершённых в рамках уже применённого actor/client/group scope. Использованы существующие `schedule_series_plan_idx`, `lessons_series_idx` и scheduled indexes; новая дублирующая схема/индекс не понадобились.

## Проверки

| Gate | Результат |
|---|---:|
| PostgreSQL create/edit/end/stale/fault/tray | 1 suite, 6/6 tests |
| Mid-week end | прошлое byte-stable; later unsettled cancelled; terminal retained |
| Atomic fault injection | Plan/Series/Lessons/reservations/transitions rollback |
| Cursor tray | page ≤ 40, stable order, duplicates = 0, actor leak = 0 |
| Full backend | 155/155 suites, 1223/1223 tests |
| Backend typecheck / build | PASS / PASS |
| v7 reconcile | `issues=[]` |
| Access coverage | 297/297 private routes, unexplained allow = 0 |
| Shadow compare | access = 1782, schedule = 2000, unexplained = 0 |
| Current-state inventory | routes = 309, DTO fields = 776, unowned = 0 |
| v6 UX inventory | routes = 22, reachable = 255, unowned = 0 |
| v7 mutation inventory | finance = 246, lesson mutations = 7, unknown callers = 0 |

## Вывод

Критерии T4.1.2 выполнены: завершение Plan защищено preview/confirm/version/idempotency и одной транзакцией, история не переписывается, а bounded tray стабильно листается и не раскрывает чужие данные. Следующий шаг — `T4.1.3`, production Client Card plan section.
