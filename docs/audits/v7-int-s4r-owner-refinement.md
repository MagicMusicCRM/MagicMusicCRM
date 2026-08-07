# v7 INT-S4R — Owner Refinement

**Дата:** 2026-08-07

**Статус:** PASS

**Ветка проверки:** `codex/client-card-desktop-canvas`

## Принятые потоки

- Related entity открывается по тексту: desktop создаёт выбранную workspace-tab и сохраняет source state; compact использует canonical route.
- Календарь Client Card по умолчанию скрывает чужие занятия; после отключения фильтра занятие клиента зелёное, остальные нейтральные в Month/Week/Day.
- Постоянное расписание поддерживает несколько строк с обязательными преподавателем, аудиторией и финансовым решением. Preview и commit используют один authoritative constraint engine и возвращают ссылки на конфликтующие занятия.
- Каждое занятие имеет versioned planned settlement. Completion worker проводит его exactly once; ошибка оставляет `review_required` без частичных фактов.
- До старта signed preview/commit атомарно меняет решение и reservation. После завершения correction сохраняет исходные факты, добавляет append-only replacement и показывает staff причину/автора/effective revision.

## Доказательства

| Контур | Результат |
|---|---|
| Flutter targeted navigation/calendar/plan/settlement | 31/31 PASS |
| Backend targeted schedule/commerce/RBAC/reporting | 119/119 PASS |
| PostgreSQL fault/concurrency/replay cleanup pack | 30/30 PASS |
| Actor Matrix + payload leak | 9/9 PASS |
| Windows stories | calendar 1/1, recurring plan 1/1, settlement/correction 1/1 |
| Android 15 API 35 stories | calendar 1/1, recurring plan 1/1, settlement/correction 1/1 |
| Реальные роли | `magic1..5` на Windows и Android: login/shell 5/5, restart/logout/account switch 2/2 |
| Миграции | `0111→0113` down/up PASS; rollback guards и immutable history PASS |
| Inventories | finance=255, lessonWrites=7, routes=22, reachable=261, unowned=0 |

## Целостность

- Source lesson facts после correction не изменяются.
- Effective views возвращают одну актуальную client charge и одну teacher compensation; payroll/client/reporting читают только effective facts.
- Fault между client и teacher fact полностью откатывает correction, facts и lesson version.
- Повтор с тем же idempotency key возвращает исходный результат; competing writer получает conflict.
- Test cleanup после каждого correction оставляет audit/idempotency residue `0/0`.

**Решение:** `INT-S4R PASS`.
