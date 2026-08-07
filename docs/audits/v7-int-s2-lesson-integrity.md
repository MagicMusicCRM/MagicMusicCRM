# v7 — INT-S2 Lesson Integrity

**Дата:** 2026-08-07

**Статус:** PASS

## Сквозной результат

- Effective school/branch catalogs проецируют только активные settlement и teacher-pay rules; обычные сотрудники не получают configuration-write access.
- Normal lesson, оплачиваемый пропуск, бесплатное занятие, частичная оплата, штраф 200%+fixed, индивидуальное и group settlement создают точные immutable snapshots/facts.
- Reschedule, cancel и explicit settle выполняют одинаковый preview/commit contract; source/successor, reservation и client/teacher facts атомарны.
- Completion worker создаёт только `settlement_pending`; protected PATCH, legacy Flutter update/delete и неизвестные temporal callers отсутствуют.
- Один Flutter LessonDecision flow принят на Windows и Android 15: human reason, settlement, independent teacher compensation, rich preview и commit.

## Проверки

| Gate | Результат |
|---|---:|
| PostgreSQL schedule/commerce/config/RBAC | 18/18 suites, 130/130 tests |
| Paid-miss lifecycle snapshot | key/label/blue/100% + independent standard teacher pay |
| Full backend | 154/154 suites, 1211/1211 tests |
| Backend typecheck / build | PASS / PASS |
| Full Flutter | analyze clean, 626/626 tests |
| Windows LessonDecision interaction | 1/1 PASS |
| Android 15 API 35 LessonDecision interaction | 1/1 PASS |
| v7 reconcile ×2 | `issues=[]` / `issues=[]` |
| Read-only preflight ×2 | 19/19, stable digest `267c1cce...010090` |
| Access coverage | 291/291 private routes, unexplained allow = 0 |
| Shadow compare | access 1746 + schedule 2000, unexplained = 0 |
| Current-state inventory | routes = 303, DTO fields = 739, unowned = 0 |
| v6 UX inventory | routes = 22, reachable = 255, unowned = 0 |
| v7 mutation inventory | finance = 243, lesson mutations = 7, unknown callers = 0 |

## Вывод

S2 принят: все операции Lesson lifecycle используют один конфигурируемый, атомарный и actor-scoped contract от Flutter до PostgreSQL, а прямой обход не обнаружен. Следующая задача — `T4.1.1`, aggregate постоянных расписаний поверх существующих series.
