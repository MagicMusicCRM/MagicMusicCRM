# T7.1.1 — Client Status reporting

Дата: 2026-07-30

## Результат

- Добавлена versioned filter schema `v1` для type/status/branch/date/search.
- Summary и drilldown выполняются из одного actor-scoped SQL CTE.
- Manager ограничен текущими назначениями филиалов на уровне query.
- Director и system_admin получают business-wide projection.
- Admin и Manager с персональным deny `report.status.read` получают `403`.
- Summary возвращает typed drilldown EntityLink с тем же filter spec; строки списка содержат безопасный ClientRef.

## Проверка

- PostgreSQL integration: 1/1 suite, 2/2 tests.
- TypeScript typecheck: clean.
