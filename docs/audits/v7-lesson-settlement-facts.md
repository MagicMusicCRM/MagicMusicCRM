# v7 — T3.1.2 Lesson settlement and teacher accrual facts

**Дата:** 2026-08-07

**Статус:** PASS

## Реализовано

- Commerce settlement port принимает типизированное решение: context, общий тип списания, optional per-client overrides для группы, выбранное независимо правило преподавателя и optional minor-unit override.
- HTTP-ready DTO проверяет stable keys, UUID, уникальность client decisions и денежный override строкой без потери точности. Старый no-input вызов сохранён только как compatibility path до отключения completion worker в T3.1.4.
- Расчёты выполняются целочисленно: 0–20000 basis points, часы с точностью 0.01, personal-account amount, fixed penalty и teacher fixed/hourly/percent/standard без binary-float money.
- Для каждого frozen участника создаётся ровно один immutable client fact; для занятия — ровно один независимый teacher fact.
- Fact сохраняет применённые stable key, label, color, share, penalty, units/amount/currency и revision. Teacher fact сохраняет key/label/mode/default/actual/override reason/amount и собственную revision.
- School/branch source revision выбирается отдельно для settlement и teacher catalog, поэтому sparse branch override не скрывает более свежую school revision второго каталога.
- Subscription capacity проверяется под lock точным PostgreSQL numeric-сравнением. 200% расширяет текущий резерв только при достаточном остатке; сбой откатывает резерв и оба вида фактов.
- Нулевой subscription settlement остаётся явным историческим фактом, но резерв освобождается и часы не потребляются.
- Повтор того же решения возвращает прежние факты; решение с другими keys/subscription/override после settlement отклоняется.
- Reconciliation fingerprint дополнен причиной ручного teacher override.

## Проверки

| Gate | Результат |
|---|---:|
| Calculation matrix | 0/50/100/200% + penalty PASS |
| Teacher modes / override reason | PASS |
| Configured PostgreSQL settlement | individual/group/subscription PASS |
| Exact facts | N client + 1 teacher PASS |
| Insufficient subscription capacity | writes = 0, original reserve unchanged |
| Concurrent replay | 8 callers, one stable fact set |
| Catalog changed after settlement | historical label/color/rule/amount unchanged |
| Zero-unit reservation | released, not consumed |
| Commerce regression | 8/8 suites, 58/58 tests |
| Schedule transition/completion regression | 3/3 suites, 8/8 tests |
| Full backend | 153/153 suites, 1197/1197 tests |
| Typecheck / build | PASS / PASS |
| v7 reconcile | `issues=[]` |
| v7 inventory | finance = 243, lesson writes = 13, unowned = 0 |

## Вывод

Критерии T3.1.2 выполнены. Историческая финансовая семантика больше не зависит от текущих названий, цветов или ставок конфигурации; client settlement и teacher accrual готовы к единому атомарному transition T3.1.3.
