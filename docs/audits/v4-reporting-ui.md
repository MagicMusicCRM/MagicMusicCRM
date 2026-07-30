# T7.2.2 — Reports, drilldown и export UI

Дата: 2026-07-30

## Результат

- Manager видит branch-scoped Client Status и Lesson Success без School Finance.
- Director/system_admin дополнительно видит school-finance rows и finance export.
- Loading, empty, error и forbidden состояния явные и имеют retry/safe exit.
- Status metric открывает список с исходным server `EntityLink.filter`; возврат
  восстанавливает исходный отчёт, строка клиента открывает actor-safe target.
- Sync export сразу сохраняется; async job показывает queue/processing/error,
  опрашивает owner-only status и открывает private download системным приложением.
- Report surface проверена на mobile и desktop ширине; legacy сводка сохранена
  отдельной вкладкой для Director/system_admin.

## Проверка

- Exact Flutter widget: 4/4 tests.
- Затронутый reports/finance regression: 4/4 tests.
- Targeted Flutter analyze: clean.
