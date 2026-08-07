# v7 — T3.1.5 Unified Flutter LessonDecision flow

**Дата:** 2026-08-07

**Статус:** PASS

## Реализовано

- Один `LessonDecisionController` и одна adaptive form обслуживают перенос, изменение длительности/ресурсов, отмену и явную фиксацию результата.
- Drag/drop и resize не меняют карточку локально до подтверждения. Month/Week/Day открывают тот же flow через details/editor; дата в Client Card tray открывает тот же редактор и controller.
- Форма всегда требует human-причину, тип списания и независимое правило оплаты преподавателю до mutation. Активные варианты читаются из узкой read-only projection effective CRM Configuration для филиала.
- Preview показывает source/successor, client hours/money, teacher amount, conflicts и warnings. Цветовые маркеры дополнены icon/label.
- Commit доступен только после свежего подтверждаемого preview. Ошибка оставляет source без изменения, сохраняет ввод и повторно использует один idempotency identity.
- Старые Flutter `updateLesson`, `updateLessonRaw`, direct delete и optimistic undo удалены. Окно деталей предлагает явные lifecycle-команды вместо безвозвратного удаления.

## Проверки

| Gate | Результат |
|---|---:|
| Flutter targeted schedule/client regression | 20 files, 72/72 tests |
| Preview → commit / retry identity / conflict rollback | PASS |
| Editor and Client Card tray entry points | PASS |
| Adaptive quick view lifecycle actions | PASS |
| Flutter targeted analyze | clean |
| Backend catalog/RBAC integration | 2 suites, 60/60 tests |
| Backend typecheck / build | PASS / PASS |
| Current-state inventory | routes = 303, DTO fields = 739, unowned = 0 |
| v6 UX inventory | routes = 22, reachable = 255, unowned = 0 |
| v7 mutation inventory | finance = 243, lesson mutations = 7, unknown callers = 0 |

## Вывод

Критерии T3.1.5 выполнены: все production entry points используют один reason/settlement/teacher-pay preview до mutation, а старого Flutter-обхода protected Lesson PATCH больше нет. Следующий шаг — `INT-S2`, сквозная проверка Lesson Integrity.
