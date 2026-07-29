# MagicMusicCRM v4 — System Design Index

**Статус:** Active  
**Дата:** 2026-07-25

## Дизайны v4

| Система | Документ | Ключевой инвариант |
|---|---|---|
| SYS-APP | [`app_workspace.md`](app_workspace.md) | Вкладка изолирует навигацию/форму, но не auth/cache |
| SYS-ACCESS | [`access_control.md`](access_control.md) | Hard invariant сильнее любой персональной галочки |
| SYS-CRM | [`client_crm.md`](client_crm.md) | Связи сохраняются, destructive cascade запрещён |
| SYS-SCHEDULE | [`schedule_lifecycle.md`](schedule_lifecycle.md) | Статус и деньги меняются одной транзакцией |
| SYS-COMMERCE | [`commerce.md`](commerce.md) | Платёж — append-only fact |
| SYS-WORKFLOW | [`workflow_tasks.md`](workflow_tasks.md) | Одна общая задача, первое закрытие завершает её для всех |
| SYS-REPORTING | [`reporting.md`](reporting.md) | Read model не изменяет source data и соблюдает actor scope |
| SYS-PLATFORM | [`platform_integrity.md`](platform_integrity.md) | Commit предшествует audit/outbox delivery |

## Наследованные runtime-дизайны v3

`files.md`, `legal.md`, `messenger.md`, `notifications.md`, `profile_crm.md`, `security_gates.md` и `_research/` сохранены как принятый baseline тех частей v3, которые v4 не перепроектирует. При конфликте по областям v4 приоритет имеет новый дизайн из таблицы выше.

Детали реализации должны уточняться в `{system}.detail.md` только если соответствующий L0 превысит 200 строк или потребуется более 30 строк псевдокода.
