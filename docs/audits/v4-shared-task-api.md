# T6.2.1 — Shared Task API

Дата: 2026-07-29

## Результат

- Добавлены versioned/idempotent create и update для одной общей задачи.
- All-day/interval, audience и EntityLink валидируются до записи.
- Видимость вычисляется из текущего explicit user / branch / allBranches audience.
- Для branch audience учитываются действующие teacher/staff assignments; потеря membership немедленно закрывает list/close.
- Первое закрытие атомарно создаёт один `TaskClose`, audit и outbox event.
- Конкурентный проигравший получает тот же сохранённый close result.
- Matched selector и membership version записываются в append-only resolution audit.

## Контракт

- `GET /crm/shared-tasks`
- `POST /crm/shared-tasks`
- `PATCH /crm/shared-tasks/:taskId`
- `POST /crm/shared-tasks/:taskId/close`

Закрытие использует `workflow.task.read` плюс актуальный audience scope; create/update используют `workflow.task.write`.

## Проверки

- PostgreSQL exact suite: 1/1 suite, 2/2 tests.
- Create replay возвращает тот же task.
- Удаление staff branch assignment убирает branch task из выдачи.
- Два одновременных close: state=closed, TaskClose=1, close audit=1, outbox=1, результаты идентичны.
- Backend typecheck: PASS.
