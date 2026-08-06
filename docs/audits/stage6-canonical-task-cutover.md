# MagicMusicCRM — Этап 6: единая модель задач

**Статус:** ENGINEERING PASS
**Дата:** 2026-08-06
**Канонический источник:** `app.shared_tasks` + `app.task_audiences` + `app.audit_events`

## Результат

Production использует один task workflow: `SharedTasksV4Panel` → `/crm/shared-tasks` → `SharedTaskService`. Исторические `app.tasks` перенесены lossless-миграцией `0101_canonical_shared_tasks`; старые Flutter-виджеты, `/crm/tasks`, legacy service и production read/write paths удалены после проверки parity.

## Матрица consumers

| Consumer | Старый источник/путь | Канонический путь после cutover |
|---|---|---|
| Основной workbench | `TasksWidget`, `MagicCrmService.listTasks`, `/crm/tasks` | `SharedTasksV4Panel`, `/crm/shared-tasks`, единые create/edit/close/history/calendar |
| Dashboard count и detail | прямое чтение `app.tasks` | `app.shared_tasks` + `app.shared_task_visibility`; count и detail используют один predicate |
| Карточка Lead/Student | legacy task adapter/provider | typed `linkedEntity` через `/crm/shared-tasks`; компактная карточная поверхность использует тот же detail/history |
| Student/Lead boards | `app.tasks` для open-count/no-open filter | `app.canonical_tasks` + actor visibility |
| Client card read projection | `app.tasks` | `app.canonical_tasks` + actor visibility |
| Client reference/impact | `app.tasks` | `app.canonical_tasks` + actor visibility |
| Timeline | `app.tasks` | `app.canonical_tasks` + actor visibility |
| Section unseen badge | legacy task rows | `app.canonical_tasks` + `app.shared_task_recipients` (`mine`, намеренно уже management scope) |
| Напоминания и уведомления | duplicate legacy scheduler | только `SharedTaskReminderWorker`; закрытие удаляет pending reminders |
| Archive preview/blocker | `app.tasks` | `app.canonical_tasks` |
| Lead→Student conversion | update `app.tasks.entity_id` | update typed link в `app.shared_tasks` |
| Merge/undo | legacy task update | `app.shared_tasks`; legacy UUID разрешается через `app.shared_task_legacy_links` |
| Reporting/analytics task queue | legacy dashboard query | current canonical queue с тем же actor visibility |
| HolliHop import | запись `app.tasks`/`app.task_history` | `app.shared_tasks`, audiences и immutable `app.audit_events` |
| Demo reset/preflight | destructive/reset checks по `app.tasks` | soft-delete/check `app.shared_tasks`, сохраняя immutable facts |
| Platform v4 preflight/dry-run | чтение legacy source | оставлено намеренно только как migration tooling; production consumer не является |

## Миграция и инварианты

- `priority` и canonical `branch_id` перенесены из legacy row.
- Задачи без аудитории получают прежнюю branch visibility; при неизвестном филиале — school audience.
- История переносится в `app.audit_events` с детерминированным id и `legacyHistoryId`, поэтому повторное применение не дублирует события.
- Каждый legacy UUID сохраняется в `app.shared_task_legacy_links`; ambiguous rows не склеиваются без доказанного общего происхождения.
- Typed Lead/Student link сохраняется и открывается тем же `EntityLink` resolver.
- Visibility централизована: получатель видит `mine`, Manager — свой филиал, Director/system_admin — доступную school/global область.
- Down-миграция fail-closed: откат запрещён, если потеряются runtime priorities или невозможно восстановить исторический FK.
- DML-права runtime-роли на `app.tasks`, `app.task_history`, `app.task_reminders` отозваны.

## Parity UI

Единый workbench поддерживает status/search/priority/scope filters, смену исполнителей и срока, историю, календарь месяц/день, create/edit/close и typed transition. В карточке клиента остаются status filter и task list; полноразмерная search/calendar toolbar показывается только в основном workbench, чтобы не ломать ограниченную высоту вкладки.

## Доказательства

| Gate | Результат |
|---|---:|
| Flutter analyze | clean |
| Full Flutter regression | 600/600 |
| Backend typecheck/build | clean |
| Full backend regression | 151/151 suites, 1155/1155 tests |
| SharedTask migration/API/reminder contracts | 3 suites, 9/9 |
| Dashboard count = canonical detail | PostgreSQL PASS |
| Migration rehearsal | `0101` down → up → idempotent up PASS |
| Access coverage | private 279/279, scopes 279, unexplained allow 0 |
| Inventories | v4 routes 291, unowned 0; v6 routes 22, reachable 253, unowned 0 |
| Windows on-device task audience flow | 1/1 PASS |
| Android 15 API 35 on-device task audience flow | 1/1 PASS |
| Windows debug build | `build/windows/x64/runner/Debug/magic_music_crm.exe` |
| Android debug build | `build/app/outputs/flutter-apk/app-debug.apk` |
| Production legacy task scan | только `v4-preflight`/`v4-migrate-dry-run` migration tooling |
| `git diff --check` | PASS |

## Отложенная граница

Production deployment и owner UAT на реальных аккаунтах `magic1@gmail.com` … `magic5@gmail.com` не выполнялись: по handoff это отдельный финальный этап и требует явной команды владельца. Этап 6 закрыт как ENGINEERING PASS.
