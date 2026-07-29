# T6.4.1 — Task audience/concurrency/device regression

Дата: 2026-07-29

## Матрица

- `user` / несколько `user`: видимость только указанным участникам; concurrent close возвращает один stable result.
- `branch`: current staff membership разрешает list/close; удаление assignment до close даёт safe 404.
- `allBranches`: доступен текущим ролям с `workflow.task.read`; client denied.
- Matched selector и membership version проверены в append-only resolution audit.
- Provider outage не блокирует source action: reminder retry/fallback сохраняется.
- Overlapping workers забирают один reminder.
- Desktop/mobile UI сохраняет явный close, retry и non-modal reminder.
- Mobile collapsed filter: ровно 56 px; advanced panel scrollable.

## Gate

- `test:tasks-v4`: 3/3 suites, 5/5 tests.
- Flutter SharedTask UI: 4/4 tests.
- Duplicate close/audit/outbox: 0.
- Unauthorized close после permission loss: 0.
- Reminder blocking failures: 0.

## Full batch regression

- Backend: 140/140 suites, 1126/1126 tests.
- Flutter: 434/434 tests.
- Backend typecheck/build: clean.
- Flutter analyze: clean.
- Review-проход устранил N+1 в audience/reminder projection и сохранил существующий reminder при edit.
- Regression-проход исправил только две устаревшие совместимости тестов/UI: rollback gate теперь допускает более новые migrations, компактный legacy task layout не переполняется.
