# MagicMusicCRM — Этап 7: аналитика

**Статус:** ENGINEERING PASS
**Дата:** 2026-08-06
**Канонические источники:** операционные CRM/lesson/payment/task домены

## Результат

Production-аналитика больше не повторяет историческую структуру из шести несвязанных отчётных вкладок. `ReportsWidget` разделён на обзорные показатели и операционные журналы; один `DashboardFilter` хранит период и филиал, переживает workspace/direct-link state и передаёт один нормализованный полуоткрытый UTC-интервал всем consumers.

Каталог абонементов сохранён отдельной неаналитической поверхностью, чтобы этап не потерял его production-home до консолидации «Настроек системы».

## Predicate и переходы к источнику

| Показатель/журнал | Источник | Reconciliation / переход |
|---|---|---|
| Статусы клиентов | `/analytics/v4/client-status/summary` | detail `/clients` получает тот же typed filter; count обязан совпасть с `total` |
| Успешные занятия | `/analytics/v4/lesson-success` | новый `/lessons` использует общий SQL predicate actor + branch + `[from,to)`; каждая строка открывает `lesson` |
| Текущие задачи | `/crm/shared-tasks` | только каноническая очередь; переход в task workbench со `state=open` |
| Финансы школы | `/analytics/v4/school-finance` | месяц открывает финансовый журнал с теми же branch/from/to |
| Действия | `/crm/activity` | общий period/branch, без собственного селектора периода |
| Платежи и расходы | `/crm/payments`, `/crm/expenses` | общий period/branch; последний выбранный день включён через exclusive `to` |
| Расчёты преподавателей | существующий teacher stats API | общий period/branch; локальные селекторы скрыты внутри Analytics |

Параллельный `ManagementDashboardWidget` снят с production mount. Задачи не получают period/branch, потому что это явно обозначенная текущая очередь, а не историческая метрика.

## Capability projection

- Dashboard и весь `ReportsWidget` fail-closed без `report.status.read`.
- School finance provider, chart, export и финансовый журнал не создаются без `commerce.school_finance.read`.
- Manager видит разрешённые operational показатели без school-finance request.
- Новый lesson detail endpoint покрыт общей capability route policy и тем же actor/branch SQL scope, что KPI.

## Excel reconciliation

PostgreSQL fixture сформировал `stage7-school-finance.xlsx` из той же `ReportingReadService.schoolFinance`, которая питает экран. ExcelJS и artifact-tool подтвердили один лист «Финансы», строку `8000 / 0 / 8000`, формулу `D2-E2` и отсутствие formula errors. Файл затем открыт установленным Microsoft Excel 16 через COM read-only: `01.07.2026`, `8 000,00 ₽`, `0,00 ₽`, `=D2-E2`, used range `A1:F2`.

Проверочный файл: `outputs/stage7-analytics-20260806/stage7-school-finance.xlsx`.

## Доказательства

| Gate | Результат |
|---|---:|
| Flutter analyze | clean |
| Targeted analytics/roles/IA | 15/15 PASS + reports IA 2/2 PASS |
| Full Flutter regression | 601/601 PASS |
| Backend typecheck/build | clean |
| Targeted reporting/finance/dashboard | 3 suites, 24/24 PASS |
| Full backend regression | 151/151 suites, 1155/1155 tests |
| KPI ↔ lesson detail PostgreSQL reconciliation | PASS |
| Screen ↔ XLSX PostgreSQL reconciliation | PASS |
| Access coverage | private 280/280, scopes 280, unexplained allow 0 |
| Shadow compare | 1680 decisions, explained 6/6, unexplained 0 |
| Inventories | v4 routes 292, DTO fields 683, unowned 0; v6 routes 22, reachable 251, unowned 0 |
| Windows on-device analytics flow | 1/1 PASS |
| Android 15 API 35 on-device analytics flow | 1/1 PASS |
| Windows debug build | PASS |
| Android debug APK | PASS |
| Microsoft Excel real open | PASS |

## Отложенная граница

Owner UAT на реальных аккаунтах `magic1@gmail.com` … `magic5@gmail.com` и production deployment не выполнялись: это отдельный финальный этап и требует явной команды владельца.
