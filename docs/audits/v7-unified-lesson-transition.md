# v7 — T3.1.3 Unified lesson transition

**Дата:** 2026-08-07

**Статус:** PASS

## Реализовано

- `reschedule`, `cancel` и новый explicit `settle` используют один typed financial decision и один transactional service.
- Preview выполняет тот же Commerce settlement и reservation terminalization внутри PostgreSQL savepoint, возвращает labels/colors/units/amounts/revision IDs и полностью откатывает сухой прогон.
- HMAC preview token с TTL 300 секунд связывает actor, operation, Lesson/version и SHA-256 fingerprint причины, successor, решения, config snapshots, subscription/reservation state и рассчитанных фактов.
- Commit повторно блокирует Lesson, schedule resources и subscriptions, проверяет current capability, создаёт immutable successor, меняет lifecycle, создаёт exact client/teacher facts, terminalizes source reservation, резервирует successor и только затем пишет transition/audit/outbox.
- Любая stale preview, schedule conflict, нехватка часов или исключение Commerce откатывает source lifecycle/version, successor, reservation changes, facts, transition, audit/outbox и idempotency reservation.
- Один `LessonTransition` хранит полное решение, обязательную human-причину переноса/отмены и ссылки на все client facts плюс teacher fact. Причина также доступна в staff audit.
- Group Lesson сохраняет frozen participants/snapshot при переносе; per-client subscription/type overrides проходят через тот же fingerprint и Commerce port.
- Старый boolean financial adapter удалён. Повтор с тем же idempotency key возвращает исходный transition и не создаёт дубликаты.

## Проверки

| Gate | Результат |
|---|---:|
| PostgreSQL reschedule/cancel/settle | PASS |
| Preview/commit calculation equivalence | PASS |
| Schedule conflict | source scheduled, successor/facts = 0 |
| Injected Commerce fault | source scheduled, successor/facts = 0 |
| Capacity exhausted after preview | source scheduled, successor/facts = 0 |
| Stale decision / signed token mismatch | writes = 0 |
| Parallel reschedule race | 1 winner, 1 successor, 1 transition, 1+1 facts |
| Idempotent replay | stable transition/fact IDs, duplicates = 0 |
| Schedule regression | 9/9 suites, 26/26 tests |
| Commerce regression | 8/8 suites, 58/58 tests |
| Full backend | 153/153 suites, 1197/1197 tests |
| Typecheck / build | PASS / PASS |
| v7 reconcile | `issues=[]` |
| Access coverage | 288/288 private routes, unexplained allow = 0 |
| Current-state inventory | routes = 300, DTO fields = 729, unowned = 0 |
| v7 inventory | finance = 244, lesson writes = 13, unowned = 0 |

## Вывод

Критерии T3.1.3 выполнены: календарный lifecycle и immutable Commerce facts имеют одну ACID-границу, а UI сможет безопасно подтверждать только свежий рассчитанный preview. Следующая задача T3.1.4 закрывает оставшиеся обходы — completion worker, protected direct PATCH и bulk transition.
