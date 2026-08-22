# Системное упорядочивание структуры и имён MagicMusicCRM

Дата: 2026-08-22

Статус: утверждённый дизайн перед implementation-планом.

## 1. Решение

MagicMusicCRM переходит от исторических названий поколений и механических
разбиений файлов к именам, которые описывают актуальную ответственность кода.
Cleanup выполняется последовательными архитектурными cuts, а не массовым
переименованием.

Версия разрешена в имени только тогда, когда она является частью живого
контракта: API route, PostgreSQL function или schema, migration, rollout flag,
release channel либо persisted namespace. Такие элементы сохраняют версию и
получают явное размещение в `api`, `migration`, `rollout` или `release`.

Активный UI, presentation-компоненты, внутренние сервисы и production part-файлы
получают capability-based имена. Слова `legacy`, `old`, `new`, `temporary` и
суффиксы `a`, `b`, `c` не используются как замена точной ответственности.

## 2. Цель и измеримый результат

После cleanup разработчик должен понимать назначение production-файла по пути и
имени, не читая git history и не выясняя, что означают `v4`, `v7` или `tabs_a`.

Исходная точка на commit `63786e90`:

- Sentrux quality: `4892`;
- Sentrux dependency depth: `15`;
- Sentrux rules: `PASS`;
- Sentrux import edges: `4121`;
- 14 активных Flutter-файлов с поколением в пути или имени;
- 10 дублированных определений `_V7Field` и `_V7PrimaryButton`;
- 6 production part-файлов с суффиксами `_a` или `_b`;
- 75 тестовых файлов в исторических buckets `v4`, `v6`, `v7`, `s8`;
- 15 подтверждённых RepoWise cleanup-ready exports на 179 строк;
- 0 production-файлов, подтверждённых как безопасно недостижимые целиком.

Cleanup завершён, когда выполнены все условия:

1. В активном Flutter UI нет поколенческих путей и символов вне проверяемого
   списка контрактных исключений.
2. В production-коде нет part-файлов с семантически пустыми суффиксами
   `_a`, `_b`, `_c`.
3. Каждый compatibility bridge изолирован, имеет потребителей и проверяемое
   условие удаления; слово `legacy` не маскирует обычный production-код.
4. Исторические тестовые buckets заменены capability-based каталогами, а
   release evidence и миграционные fixtures явно отделены от актуальных тестов.
5. Sentrux rules остаются `PASS`, quality выше исходного `4892`, dependency
   depth не превышает `15`, RepoWise index соответствует текущему HEAD.

## 3. Неизменяемые инварианты

Cleanup не изменяет продуктовые правила, API payloads, PostgreSQL schema,
route semantics, RBAC, русские UI-тексты или визуальную тему.

Особенно сохраняются:

- transaction, expected version, idempotency, audit и outbox для lesson и
  денежных команд;
- backend RBAC и resource scope;
- preview/blockers/commit и архивирование исторически связанных сущностей;
- один Flutter/NestJS/PostgreSQL runtime без параллельных моделей;
- существующие versioned строки контрактов, пока их migration или rollout не
  завершён отдельным решением владельца.

Cleanup не выполняет deploy и не изменяет production-данные.

## 4. Политика именования

### 4.1. Разрешённые имена с версиями

Версия остаётся, если изменение имени потребовало бы синхронного изменения
внешнего или persisted контракта. Текущие подтверждённые категории:

| Категория | Примеры | Правило |
| --- | --- | --- |
| HTTP API | `/analytics/v4/*`, связанные `V4ReportExport*` DTO | Версия остаётся у route-bound методов и DTO |
| Migration и DB | `app.backfill_v7_commerce()`, `v3-import-utils.ts` | Размещается под `migration/<domain>/<version>` |
| Rollout | `V4DomainFlagsService`, режимы `legacy/shadow/v4` | Размещается под `rollout/<version>` до закрытия rollout |
| Persisted namespace | `mmcrm.v3.*`, preview token `v1` | Не переименовывается без migration данных |
| Release channel | `latest-v2.json` | Не переименовывается без updater bridge и release-решения |

Само наличие числа в комментарии или имени не доказывает контракт. Для каждого
исключения фиксируются причина, владелец и `remove_when`.

### 4.2. Запрещённые production-имена

Вне контрактных областей запрещаются:

- каталоги и presentation-файлы `v<number>`;
- символы UI вида `V7NavShell`, `StudentCreateDialogV4`, `_V7Field`;
- файлы `*_a`, `*_b`, `*_c`;
- `old`, `new`, `temp`, `legacy` без явно описанного compatibility boundary;
- wide barrel, который скрывает фактические зависимости между подсистемами.

### 4.3. Автоматическая защита

В `tool/` создаётся cross-platform naming check и machine-readable реестр
исключений. Проверка анализирует production paths и публичные символы, запрещает
новые исторические buckets в тестах и валидирует, что каждый exception указывает
на существующий target и содержит `category`, `reason`, `owner`, `remove_when`.

Строковые значения API, SQL и persisted namespaces проверка не переименовывает.
Их изменение возможно только отдельной contract migration.

## 5. Целевая структура UI foundation

Текущий `lib/core/widgets/v7/` является активной production-библиотекой, а не
dead code. Он расформировывается по ответственности:

| Текущий элемент | Целевой элемент |
| --- | --- |
| `v7_nav_shell.dart`, `V7NavShell`, `V7NavDestination` | `core/navigation/responsive_navigation_shell.dart`, `ResponsiveNavigationShell`, `ResponsiveNavDestination` |
| `crmV7DestinationForTab` | `crmDestinationForTab` |
| generic часть `dirty_form_exit.dart` | `core/forms/dirty_form_exit.dart` |
| `requestWorkspaceDirtyExit` | `core/workspace/workspace_dirty_form_exit.dart` |
| `adaptive_surface`, `magic_*` primitives | прямые semantic imports из `core/widgets/` |
| `v7.dart` | удаляется после перевода всех 35 importers на точечные imports |

Перемещение не меняет визуальные tokens или поведение компонентов. Исторические
ссылки на прототип сохраняются только в документации о происхождении темы.

Auth-компоненты из шести экранов объединяются в
`features/auth/presentation/widgets/auth_form_controls.dart` с именами
`AuthField` и `AuthPrimaryButton`. Внешний вид и параметры сохраняются, а
characterization tests фиксируют варианты field, validator, disabled, suffix и
submit state до удаления десяти локальных копий.

## 6. Активные поколенческие presentation-компоненты

### 6.1. Client card API и создание клиента

`ClientCardV4Api` и `clientCardV4ApiProvider` обращаются к неверсированным
`/crm/clients/*` routes. Они становятся `ClientCardApi` и
`clientCardApiProvider`.

`StudentCreateDialogV4` становится `StudentCreateDialog`. Rename выполняется
после проверки отсутствия параллельной canonical реализации и не затрагивает
payload формы.

### 6.2. Shared tasks

`shared_tasks_v4_panel.dart` не переименовывается монолитно. Текущий файл имеет
около 2024 NLOC, 110 исходящих зависимостей, RepoWise health `1.2` и шесть
недавних bug fixes. Сначала он разделяется на независимые единицы:

- `shared_tasks_data_source.dart` — интерфейс и service adapter;
- `shared_tasks_controller.dart` — загрузка, фильтры, realtime и команды;
- `shared_task_editor.dart` — создание и изменение;
- `shared_task_details.dart` — details, history и linked entity actions;
- `shared_tasks_panel.dart` — composition и presentation.

`SharedTasksPanel` зависит от controller state, но не выполняет прямую service
orchestration. Существующие audience preview, expected version, mutation
identity, realtime refresh и resource-scoped options сохраняются.

### 6.3. Reporting

`ReportingV4Panel` становится `ReportingPanel`, но route-bound методы и DTO
`getV4*`, `requestV4ReportExport`, `V4ReportExportJob` сохраняют версию, потому
что обращаются к `/analytics/v4/*`.

Текущий state-класс на 715 строк разделяется на:

- `reporting_controller.dart` — параллельная загрузка sections и фильтры;
- `report_export_coordinator.dart` — polling, валидация, сохранение и открытие;
- `reporting_drilldown_view.dart` — entity links и drilldown state;
- `reporting_summary_view.dart` — summary sections;
- `reporting_panel.dart` — RBAC-aware composition.

Недоступный UI не запускает запрос. Ошибка одной section не очищает остальные
данные. Export polling сохраняет текущие retry и format validation semantics.

## 7. Семантический split part-файлов

Part-файл допустим только когда его имя описывает одну ответственность и
связь с owner library остаётся очевидной.

| Текущие файлы | Целевые границы |
| --- | --- |
| `schedule_widget_views_a/b.dart` | toolbar, week view, room day view, teacher day view и navigation/lesson actions |
| `client_card_tabs_a/b.dart` | overview, tasks, comments, family, access и blacklist responsibilities |
| `messenger_screen_builders_a/b.dart` | shell, chat list, conversation view и profile panel |
| `client_card_data.dart` | card loader, counterpart resolver, history merge и client-access loader |
| generic `*_widgets.dart` больше 500 NLOC | переименование или split по реальной surface, если в файле более одной ответственности |

Перед каждым split фиксируются публичное поведение и текущая method inventory.
Extension не используется как способ скрыть god state: orchestration выносится
в controller/service, а чистые builders — в самостоятельные widgets.

## 8. Compatibility boundaries

Слово `legacy` сейчас чаще всего означает живой переход от исторических
`Map<String, dynamic>` shapes к typed-моделям. Это не dead code.

Cleanup использует последовательность:

1. Зарегистрировать bridge, его источник, потребителей и `remove_when`.
2. Переместить преобразование в явно названный adapter рядом с контрактом.
3. Перевести потребителей на typed model без изменения backend payload.
4. Удалить adapter только после `0` live consumers и зелёных regression tests.
5. Отдельно закрыть запись в exception registry.

Первыми обрабатываются `magic_crm_service_mappers.dart`, legacy messenger
chat/message/channel conversions, profile admin legacy candidates и commerce
projection `toLegacy*`. Persisted enum value `funding_mode = 'legacy'`, real DB
columns и rollout modes не переименовываются этим cleanup.

## 9. Migration, rollout и тесты

`server/src/platform/v7-commerce-data.ts` является executable migration и
reconciliation CLI: он вызывает versioned PostgreSQL functions и может менять
данные только с `--apply`. Он перемещается в явную migration-область, сохраняя
SQL function names и CLI semantics.

`v4-domain-flags`, preflight, reconcile, shadow compare и backfill остаются
versioned до формального закрытия V4 rollout. Их размещение должно показывать,
что это временная operational surface, а не очередная production-архитектура.

Тестовые каталоги `v4`, `v6`, `v7`, `s8` разбираются по capability. Тест
переезжает вместе с production-кластером, который он защищает. Название версии
остаётся только у migration fixture, release evidence или contract test, где
проверяется именно версия протокола.

## 10. Milestones

1. Guardrail: naming policy, exception registry, автоматическая проверка и
   baseline evidence.
2. Foundation: DirtyForm boundary, semantic UI imports, responsive navigation
   shell, удаление `v7.dart`, общие auth controls.
3. High-impact surfaces: Shared Tasks и Reporting splits с semantic rename.
4. Cohesion: semantic split Schedule, Client Card и Messenger part-файлов;
   постепенная типизация compatibility adapters.
5. Closure: capability-based tests, cleanup-ready exports, нулевой exception
   debt вне живых контрактов и итоговые Sentrux/RepoWise gates.

Milestone не объединяется в один commit. Каждый cut — отдельный behavior-neutral
commit, после которого проект остаётся собираемым и тестируемым.

## 11. Проверка каждого cut

Для каждого структурного изменения обязательны:

1. Characterization или regression test для переносимого поведения.
2. `dart format` и минимальный релевантный Flutter/NestJS test set; analyzer для
   затронутого пакета.
3. `repowise update --index-only` после успешного изменения структуры.
4. RepoWise `get_health`/`get_risk` для затронутого boundary и Sentrux scan.
5. Проверка clean diff: rename/split не содержит случайных продуктовых или
   форматирующих изменений вне scope.

Для milestone дополнительно запускается полный соответствующий Flutter или
backend gate. Перед merge используется RepoWise `get_change_risk`.

Sentrux regression блокирует следующий cut: rules должны быть `PASS`, quality
не должен снижаться относительно предыдущего commit, а dependency depth не
должна расти без отдельного объяснения и решения владельца.

## 12. Ошибки и откат

Каждый cut сохраняет старый public behavior до переключения всех consumers.
Если characterization test выявляет расхождение, cut останавливается, а не
маскируется compatibility alias без срока удаления.

Откат выполняется отдельным `git revert` атомарного commit либо исправляющим
commit. `git reset --hard`, переписывание истории и удаление пользовательских
изменений не используются.

Compatibility adapter удаляется только после подтверждённого нулевого usage.
Migration и rollout код не удаляется по возрасту файла: требуется отдельное
решение о завершении контракта, проверка production state и rollback plan.

## 13. Не входит в cleanup

- изменение бизнес-логики, прав, API payload или PostgreSQL schema;
- визуальный редизайн и новые UI-компоненты ради внешнего вида;
- физическое удаление production-истории или legacy persisted values;
- одновременный rename всех тестов без связи с production cut;
- deploy, migration production DB или закрытие rollout без прямой команды.

## 14. Результат

Production-код организован по возможностям системы, а не по истории релизов.
Настоящие versioned contracts остаются видимыми и объяснимыми. Временные
compatibility bridges имеют владельца и конец жизненного цикла. Новые
непонятные поколения, `A/B`-части и wide barrels блокируются автоматически, а
каждый этап cleanup подтверждается тестами, RepoWise и Sentrux.
