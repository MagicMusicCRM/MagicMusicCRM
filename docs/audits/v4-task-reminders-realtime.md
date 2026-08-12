# T6.2.2 — Shared Task reminders и realtime close

Дата: 2026-07-29

## Результат

- Reminder-конфигурация сохраняется вместе с SharedTask mutation.
- Worker атомарно забирает due rows через `FOR UPDATE SKIP LOCKED`, поддерживает lease/reclaim, bounded exponential backoff и видимый poison-state.
- Dedupe key фиксирует один reminder на `task + dueAt + channel`.
- Recipients вычисляются из актуального user/branch/allBranches audience непосредственно перед отправкой.
- Email/push при синхронной ошибке переходят на in-app; полный отказ оставляет persisted retry и не откатывает CRM-команду.
- Close в одной транзакции отменяет все pending/claimed reminders.
- После commit публикуется body-free `crm.changed` hint для общей CRM-комнаты и user rooms.
- List projection возвращает независимые open/overdue counters.
- Runtime worker включается только явным `TASK_REMINDERS_ENABLED=true`.

## Проверки

- Exact PostgreSQL reminder suite: 1/1.
- Полный provider outage → pending retry.
- Повторный запуск: overlapping workers забирают один reminder; email failure → in-app fallback → delivered.
- Close другим участником: pending reminder → cancelled и realtime hint за время менее 2 секунд.
- SharedTask targeted regression: 2 suites, 3/3 tests.
- Backend typecheck: PASS.
