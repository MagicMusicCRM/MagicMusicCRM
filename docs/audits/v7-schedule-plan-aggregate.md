# v7 — T4.1.1 Schedule plan aggregate

**Дата:** 2026-08-07

**Статус:** PASS

## Реализовано

- `GET/POST /crm/schedule-plans` и `PATCH /crm/schedule-plans/:id` используют один versioned/idempotent `schedule:plan` aggregate с текущей `schedule.lesson.*` capability policy.
- Именованный individual/group plan атомарно создаёт `1 plan + N schedule_series + unique lessons`; open-ended plan сохраняет `activeUntil = null` и материализуется существующим bounded series worker.
- Individual plan хранит один явный абонемент. Group plan хранит effective-dated participant → subscription assignments; каждый урок получает immutable group snapshot, participant snapshots и отдельные reservations.
- Effective edit закрывает старые rows накануне даты, переносит exception/tombstone lineage в continuation, освобождает только будущие нетронутые reservations и начинает новые series ровно с `effectiveFrom`. Ранние Lesson snapshots не меняются.
- Concurrent create даёт один commit + один replay; concurrent edit с одинаковой expected version даёт один commit + один stale reject.
- Общий constraint path теперь видит участие ученика в group lesson как client overlap. Reservation проверяет active subscription, owner, capacity и effective date в локальной timezone занятия.

## Проверки

| Gate | Результат |
|---|---:|
| PostgreSQL individual/group/open-ended/edit/concurrency/generation | 1 suite, 3/3 tests |
| Repeat materialization / unique `(series_id, series_date)` | PASS / duplicates = 0 |
| Group participant snapshots/reservations | 2 assignments, N×2 immutable snapshots/reservations |
| Past snapshots across effective edit | byte-equivalent |
| Full backend | 155/155 suites, 1217/1217 tests |
| Backend typecheck / build | PASS / PASS |
| v7 reconcile | `issues=[]` |
| Access coverage | 294/294 private routes, unexplained allow = 0 |
| Shadow compare | access = 1764, schedule = 2000, unexplained = 0 |
| Current-state inventory | routes = 306, DTO fields = 768, unowned = 0 |
| v6 UX inventory | routes = 22, reachable = 255, unowned = 0 |
| v7 mutation inventory | finance = 244, lesson mutations = 7, unknown callers = 0 |

## Вывод

Критерии T4.1.1 выполнены: recurring plan является тонким атомарным агрегатом над существующими series/generator/reservation boundaries; individual и group subscriptions явны, а effective edit сохраняет историю. Следующий шаг — `T4.1.2`, end preview/commit и bounded plan tray.
