# MagicMusicCRM — действующие архитектурные решения

Статус: active. Обновлено 2026-08-22.

## Инженерный процесс

DECISION: RepoWise является обязательным основным code-intelligence и
agent-navigation слоем проекта. Он используется для overview, поиска symbols и
контекста, графа зависимостей, оценки риска, health и dead-code анализа.
Generated process framework, обязательные фазовые workflows и вручную
поддерживаемые карты кода не являются источником истины.

Полная запись: `docs/architecture/ADR/ADR_001_REPOWISE_FIRST.md`.

Следствия:

- `AGENTS.md` остаётся коротким и не генерируется RepoWise автоматически;
- решения и продуктовые правила хранятся в обычных текущих документах;
- индекс RepoWise локальный и обновляется из живого checkout;
- low-confidence или mock retrieval проверяется по исходнику;
- documentation ceremony не блокирует небольшую безопасную реализацию.

DECISION (owner, 2026-08-22): Sentrux обязателен как непрерывный инструмент
диагностики структурного качества для выявления и исправления слабых мест
архитектуры приложения и его кода. При выборе следующей code-health,
refactoring или cleanup задачи актуальный scan используется для фиксации
baseline и ранжирования bottlenecks, dependency depth, coupling и нарушений
rules. После каждого structural cut scan повторяется и сравнивается с baseline.
Каждая находка должна привести к ограниченному плану и проверенному исправлению,
быть подтверждена как false positive либо явно принята владельцем в отсрочку с
указанной причиной. Необъяснённое ухудшение quality,
dependency depth или rules блокирует следующий cut. Sentrux дополняет RepoWise,
живой исходник и тесты, но не заменяет их как источники истины.

DECISION (owner, 2026-08-22): Активный production-код именуется по текущей
ответственности, а не по историческому поколению реализации. Версии допустимы
только у живых API, PostgreSQL, migration, rollout, persisted namespace и
release contracts. Compatibility bridges изолируются, имеют потребителей и
условие удаления; механические part-суффиксы `_a/_b/_c` и wide barrels не
используются как постоянные архитектурные границы. Structural cleanup
выполняется атомарными behavior-neutral cuts с тестами, обновлением RepoWise и
Sentrux scan после каждого шага.

Полная запись:
`docs/superpowers/specs/2026-08-22-systematic-codebase-cleanup-design.md`.

## Runtime

DECISION: Production использует один owned runtime:
Flutter → NestJS → PostgreSQL, с Redis/Socket.IO и private file storage.
Supabase и HolliHop не являются клиентскими runtime-зависимостями.

DECISION: Flutter вызывает backend только через существующие API
clients/services/providers. Riverpod владеет разделяемым состоянием; прямой
доступ widget к БД запрещён.

DECISION: Конфигурируемые поля Lead/Student имеют одну каноническую модель
`client_custom_field_definitions/values`. Формы создания, существующая карточка
и table projection используют её напрямую; архивные значения сохраняются, а
legacy `custom_data` не расширяется в параллельный typed storage.

DECISION: Lead и Student — lifecycle-состояния одной канонической сущности
Client со стабильным `client_id`. Одно CRM-поле имеет одно определение и один
набор вариантов; новое поле по умолчанию видно в обеих карточках, а видимость
Lead/Student настраивается независимо. Значения всех справочников, включая
системный рекламный источник, изменяются только в разделе «Варианты для полей».

Полная запись: `docs/architecture/ADR/ADR_002_CANONICAL_CLIENT_AND_FIELDS.md`.

## Доступ и данные

DECISION: Авторизация, capability и resource scope проверяются backend. Роль
задаёт baseline, назначения филиалов и узкие capabilities уточняют scope.

DECISION: Финансовые, lesson settlement и audit facts неизменяемы. Исправления
создаются append-only reversal/correction facts внутри transaction с expected
version, idempotency и outbox.

DECISION: Post-completion reschedule — одна transaction: zero-effect correction
supersedes исходные client/teacher facts, исходный consumed reservation остаётся
историческим и перестаёт быть effective через superseded fact, successor получает
клонированный settlement plan и новый reservation. UI не предлагает изменить
фиксированный reversal `free_lesson/none`, но показывает причину и последствия.

DECISION: Form reschedule запланированного индивидуального и группового Lesson
использует один successor contract: frozen client/group/participants неизменяемы,
меняются только время, длительность и ресурсы. No-op отклоняется до preview;
реальное изменение проходит reason + settlement + teacher pay, signed preview,
expected version и idempotent commit, после которого UI ждёт authoritative readback.

DECISION: Физическое удаление организационной сущности с историческими ссылками
не используется. Decommission выполняется через preview, blockers/remediation,
commit и archive/tombstone.

DECISION: Branch close — немедленная versioned-команда
`preview → blockers=0 → commit(reason, effectiveDate) → archived`. Она проходит
через transaction, idempotency, expected version, audit/outbox и append-only
history. Future-dated `closing` нельзя имитировать одним флагом: оно допустимо
только вместе с запретом новых branch writes и scheduler завершения.

DECISION: Room archive использует тот же versioned lifecycle:
`preview → blockers=0 → commit(reason, effectiveDate) → archived`, append-only
history, audit/outbox и restore. Активные Group, future Lesson, recurring
series/plan и будущие room conflicts являются блокерами. Database write guards
сериализуют archive с созданием/восстановлением scheduling references, а Room
нельзя восстановить внутри архивного Branch. Старый `DELETE /crm/rooms/:id`
остаётся только как fail-closed compatibility endpoint и не меняет данные.

DECISION: Teacher/Staff имеют два связанных состояния: CRM-карточка существует
всегда, app account может быть выключен. При создании email+пароль необязательны
и принимаются только парой; технические `is_app_account=false`
user/profile/link создаются атомарно вместе с карточкой, назначениями и
необязательными дисциплинами. Дисциплины, категории и уровни — только
информационные метаданные карточки и не зависят от филиалов. Первый доступ и
последующие изменения credentials обновляют ту же identity, не создавая дубль.
Password authentication остаётся на одностороннем `scrypt`-хэше. Для
Teacher/Staff дополнительно сохраняется AES-256-GCM envelope, синхронно
обновляемый admin provision, self-service change и reset-командами. Отдельный
read endpoint расшифровывает его только для Director/system_admin с проверкой
иерархии target и обязательным audit-событием; обычные Teacher/Staff DTO
исключают email и password metadata для прочих ролей. Старые хэши необратимы:
до следующей смены пароль помечается как недоступный. Production требует
отдельный `MANAGED_PASSWORD_ENCRYPTION_KEY`; его потеря или несогласованная
ротация делает старые envelope необратимо недоступными и требует переустановки
паролей.

DECISION: При создании Teacher/Staff Director/system_admin может выбрать
допустимую начальную роль ниже собственной; она записывается атомарно вместе с
единой identity/profile/link. Обычная карточка не создаёт `system_admin`.
Последующая смена роли доступна из Staff/Teacher card, но использует ровно ту же
versioned access-команду, что и `Настройки → Доступ`: в одной транзакции она
синхронизирует projection `staff_members.role`, сбрасывает overrides, повышает
access version и пишет audit/outbox. Старый Profile API роль не меняет.
Teacher/Staff create и update принимают непустой набор филиалов и атомарно
сохраняют несколько назначений.

DECISION: Teacher/Staff offboarding — versioned lifecycle-команда
`preview → blockers=0 → commit(reason) → archived`. Она атомарно закрывает
branch assignments, отключает app account, отзывает sessions и capability
overrides, сохраняет append-only history/audit/outbox. Будущие lessons,
series/groups преподавателя и персональные tasks/leads сотрудника являются
блокерами. Restore возвращает только валидные назначения и не восстанавливает
отозванные персональные overrides.

DECISION: Discipline, Lead loss reason и Branch discipline используют один
reference-catalog lifecycle. Global references поддерживают rename/archive/
restore, branch link — unassign/restore. Каждая mutation проходит через
expected version, idempotency, transaction, audit/outbox и append-only
`reference_catalog_history`; UUID и архивное имя сохраняются. Discipline
archive и Branch discipline unassign не блокируются активными Teacher/Student/
Package references: это информационный справочник, а прошлые связи сохраняются
в impact/history. Database guards запрещают физический delete и новые ссылки на
архивную Discipline/Reason, а восстановление branch link требует активных
Branch и Discipline.

DECISION (owner, 2026-08-15): Оплата не редактируется на месте. Пользовательская
команда «Изменить и пересчитать» выполняет `preview → confirm → commit`: старая
оплата исключается из обычной финансовой проекции, оплаченный факт получает
компенсирующую append-only корректировку, новая payment record создаётся и
связывается с исходной в одной transaction. Команда сохраняет expected version,
idempotency, audit/outbox и подписанный снимок баланса. Активный абонемент
изменяется существующим versioned replacement с переносом использованных и
зарезервированных занятий и пересчётом обязательства; исходный абонемент
закрывается как replaced и не переписывается.

DECISION (owner, 2026-08-29): Назначение абонемента и фактическая оплата — одна
атомарная purchase-команда, но разные финансовые факты. Полная стоимость всегда
создаёт обязательство, а введённая в том же существующем окне сумма создаёт
каноническую оплату только если она больше нуля; долг и переплата вычисляются из
единого баланса. Student и Lead используют один signed preview/idempotent commit
контур; отдельный legacy writer удалён, а auto-paid поведение клиента v201
сохранено только внутренним compatibility adapter маршрута
`/crm/leads/:leadId/subscriptions/issue` поверх канонического writer. Adapter
удаляется после release/telemetry evidence, что build `<=201` отсутствует в
поддерживаемом окне клиентов; до этого он не получает отдельный writer или DTO.
Период действия передаётся в том же
подписанном снимке: начало может быть задним числом, окончание включительно и по
умолчанию равно началу плюс один календарный месяц. Все записи выполняются в
одной transaction с expected version, idempotency, audit/outbox и append-only
историей; UI не создаёт второй экран или параллельную модель оплаты.

DECISION: Жёсткие ограничения расписания — активная привязка преподавателя к
выбранному филиалу, рабочие часы преподавателя и филиала, обязательные Branch и
Room, принадлежность Room филиалу и отсутствие пересечений. Рабочие часы
обязательны уже при создании Branch; филиал без графика не принимает занятия.
Discipline/category/level на расписание не влияют. При выборе клиента новый
Lesson получает default Branch из `Student.branch_id`/`Lead.branch_id`, но Room
всегда выбирается оператором явно.

DECISION: Create Lesson требует независимые `settlementTypeKey` и
`clientChargeType`. `teacherCompensationRuleKey` явно выбирают только
Director/system_admin; для Admin/Manager сервер игнорирует rate-поля старых
клиентов и применяет `standard` с effective teacher rate.
Subscription source дополнительно требует конкретный `subscriptionId`. Backend
fail-closed валидирует весь набор до записи и в одной транзакции создаёт Lesson,
immutable snapshot, settlement plan/revision и применимые reservations; ни UI-
дефолт, ни допустимая связь settlement/source не заменяют отдельную проверку
правила оплаты преподавателю и источника средств. Активный subscription — UI-
дефолт, personal account — явная альтернатива. `clientChargeType=none` разрешён
только для settlement с нулевыми `hourShareBasisPoints` и
`fixedPenaltyMinor`; общий calculation/plan path отклоняет платную или
штрафную комбинацию до commit как `CLIENT_FUNDING_SOURCE_REQUIRED`.

DECISION: `Lesson.is_trial` и frozen `lesson_snapshots.trial` — только
независимый immutable marker. Он не изменяет `settlementTypeKey`,
`clientChargeType`, subscription reservation или teacher compensation. Поэтому
trial paid создаёт обычный денежный/часовой fact, а `free_lesson` даёт
`0 minor / 0.00 units` одинаково для trial и non-trial; teacher pay остаётся
отдельным решением.

DECISION: Automatic completion использует реальный polling и durable PostgreSQL
claim после `scheduled_at + duration_minutes`, а не клиентский таймер. Claim
сериализуется `FOR UPDATE SKIP LOCKED` и fenced worker identity/attempt; frozen
settlement plan, client/teacher facts, transition, audit/outbox, idempotency и
terminal reservation коммитятся одной транзакцией. Следующие ticks видят
terminal Lesson и не повторяют финансовый эффект.

DECISION: Пользовательские Lesson change notifications материализуются только
из `schedule.lesson.changed` durable outbox с явным `created/rescheduled/
cancelled` action. Event ID служит notification ID для retry-dedupe. Client и
новый Teacher маршрутизируются в successor, снятый Teacher — в source; Group
audience использует frozen lesson participants и только active app accounts.
Технический state-only refresh не является пользовательским уведомлением.

DECISION: Ошибка automatic completion после bounded retry переводит Lesson в
`settlement_pending`, а frozen settlement plan — в `review_required`. Staff
видит состояние `Конфликт`, безопасную локализованную причину и действие
`Исправить расчёт`; raw exception message не выдаётся, failure code не
проецируется Client/Teacher. Операция settle разрешена только для этой пары
состояний и требует актуальную version/preview; обычный `scheduled` Lesson
нельзя штатно провести вручную. Успешный recovery атомарно завершает Lesson,
facts, reservation и plan, очищая failure code.

DECISION: Teacher compensation вычисляется одной серверной функцией по пяти
mode. `none=0`; `standard` использует frozen legacy fixed/hourly snapshot;
`percent=standardAmount × basisPoints / 10000`; `fixed=value`;
`hourly=value × frozenDuration / 60`. Override для `none/standard` запрещён,
а изменённое значение percent/fixed/hourly требует непустой reason. Fact
неизменно сохраняет rule key/label/mode, configured default, actual value,
amount, reason и configuration revision; ошибка расчёта откатывает все client и
teacher facts одной транзакцией.

DECISION: Schedule Plan завершается одной versioned-командой
`reason → impact preview → confirmed idempotent commit → ended`. End/update
Plan используют те же per-series advisory locks, что horizon materializer,
поэтому worker не может добавить occurrence между impact и commit. Последняя
дата ограничивает series; более поздние unsettled Lesson отменяются с release
резервов, terminal/history не переписываются. End metadata входит в staff
projection, но reason/actor не выдаются Client.

DECISION: Многодневное индивидуальное расписание остаётся одним Schedule Plan,
а не набором независимых Plan. Каждый выбранный weekday разворачивается в
отдельную series; разные наборы дней могут иметь собственные teacher/room, но
создаются одной атомарной idempotent-командой и подтверждаются обязательным
read-after-write всего Plan.

DECISION: Schedule Plan tray — bounded server projection со стабильным keyset
cursor `(scheduled_at, lesson.id)`, а не клиентская выборка всей истории.
Pagination поддерживает оба направления и fail-closed проверяет cursor с
direction. Settlement и predecessor/successor markers вычисляет backend из
authoritative facts; UI сохраняет последнюю успешную страницу при ошибке и
повторяет точный неуспешный запрос.

DECISION (owner, 2026-08-14): Schedule Plan — единственный пользовательский
редактор постоянного расписания. Legacy `schedule-series` и строковое поле
`preferredSchedule` остаются совместимым read/history-контрактом до отдельной
миграции, но новый standalone series через legacy POST запрещён, а Plan-owned
series нельзя менять legacy PATCH/DELETE. Они больше не монтируются и не
изменяются из карточки клиента. Это
устраняет неатомарный цикл частичного создания нескольких series и оставляет
один путь preview → atomic commit → read-after-write. Уже созданные Lesson,
series и audit/history не удаляются и не переписываются.

DECISION (owner, 2026-08-14): Разовые Lesson и постоянные Schedule Plan
используют общий Schedule Analyzer поверх authoritative constraint engine.
Analyzer объединяет одинаковые нарушения по `code + resource type + resource
id`, сохраняет scope строк/дат/участников и ранжирует только те альтернативы,
которые прошли тот же engine для проверяемого occurrence. Для Plan применение
альтернативы всегда возвращает черновик на полный preview периода; commit по-
прежнему повторяет проверки внутри versioned transaction.

DECISION (owner, 2026-08-14): Advisory locks остаются удобной сериализацией
команд, но последний барьер пересечений принадлежит PostgreSQL. Проекция
`lesson_resource_bookings` резервирует teacher, room, direct/frozen student и
group через полуоткрытый `tstzrange`; GiST `EXCLUDE` отклоняет конкурентное
пересечение. Branch не является эксклюзивным ресурсом и остаётся проверкой
рабочих часов/назначений Analyzer. Backfill fail-closed: обнаруженный legacy-
конфликт блокирует миграцию до явного reconciliation, не переписывая историю.

DECISION: Календарь внутри staff-карточки клиента загружает разрешённую actor-
scope branch matrix, скрывает чужие Lesson локально по умолчанию и не делает
повторный client-scoped запрос при раскрытии. Target/other — отдельный marker,
не часть lesson state palette; Month отмечает день, Week и оба Day-режима —
конкретную карточку. Client role не допускается к staff matrix legacy policy,
даже если capability/UI ошибочно откроют маршрут.

DECISION: Group Lesson settlement не является отдельной финансовой моделью.
Один common decision дополняется sparse `clientDecisions`; UI получает имена
только из active frozen snapshot participants и не вычисляет деньги/часы
самостоятельно. Commerce backend применяет источник средств каждого участника,
создаёт один immutable client fact на участника и один teacher fact на Lesson;
в той же terminalize-команде потреблённый subscription reservation становится
`consumed`, остальные резервы Lesson — `released`. Исключённые участники не
возвращаются в UI и не получают новый факт.

DECISION (owner, 2026-08-29): Плательщик отдельной строки Group Lesson не
создаёт второй settlement-контур. Sparse client decision хранит фактического
участника, optional payer и его subscription; plan/commit проверяют scope обоих,
а immutable client fact остаётся на участнике. Subscription reservation и
остаток принадлежат плательщику, teacher fact по-прежнему один на Lesson. UI
ищет плательщика серверно по всему actor/Branch scope, а не в первой странице
списка учеников; абонементы загружаются только после выбора плательщика.

DECISION (owner, 2026-08-29): Закрытые и исторические периоды развивают текущий
Schedule Plan. Для backdated create/update используется signed history impact
preview, привязанный к client/plan/version/date-range/draft fingerprint; commit
повторяет resource validation под существующими locks. Параллельный legacy-
редактор, отдельная period-таблица и переписывание terminal Lesson запрещены.

DECISION (owner, 2026-08-29): Backdated update расширяет тот же Plan только
идентичным prefix `[new activeFrom, old activeFrom - 1]`; прежние series/Lesson
не retire и не пересоздаются, а prefix указывает на текущую series как lineage.
Изменение внутри prefix fail-closed. Перенос начала вперёд выделен в date-only
режим только для Plan без сложного lineage: удаляются лишь scheduled Lesson до
новой даты с release reservations, а будущие и terminal артефакты сохраняют
identity. До проверки immutable-состояния все Lesson удаляемого префикса
блокируются `FOR UPDATE` в стабильном порядке, поэтому completion worker не
может terminalize строку между проверкой и soft-delete. Обычный row/business
replace не меняет исходный `plan.active_from`.

DECISION (owner, 2026-08-29): `schedule_series.subscription_id` является
optional immutable snapshot индивидуальной Plan-series. Legacy `NULL` остаётся
rolling-compatible; перед сменой Plan subscription только текущие active
`NULL` series фиксируют прежний subscription, после чего continuation получает
новый. Исторический mass backfill запрещён, потому что текущее значение Plan не
доказывает старый источник списания. Application rollback выполняется старым
image поверх schema 0142; destructive down после появления snapshot запрещён.

DECISION (owner, 2026-08-29): Право записи любой teacher rate принадлежит только
Director/system_admin и проверяется в общей backend policy на каждом write-path.
Capabilities и скрытие controls в Flutter являются дополнительной проекцией,
а не заменой этой проверки. Старые operational payload Admin/Manager с teacher
compensation совместимы, но поля игнорируются в пользу stored/default значения;
явные rate CRUD/bulk/correction endpoints остаются закрыты. Payroll read/payout
не расширяют rate-write.

DECISION: Lead loss reason хранит `reason_name_snapshot` и
`reason_kind_snapshot` в каждой исторической смене статуса. Переименование не
меняет прошлую аналитику. `lead_status_history` append-only; единственное узкое
исключение — контролируемый merge/undo может перепривязать только `lead_id`,
оставляя все остальные поля строки неизменными.

## UX

DECISION: Приложение имеет единственную светлую тему Warm Ivory &
Sophisticated Gold. Базовый reskin меняет только семантические токены и
общие primitives; маршруты, компоновка, providers/services, API и RBAC остаются
без изменений. Русский — язык UI; desktop и mobile используют общий
канонический navigation/entity contract.

DECISION: Desktop workspace держит subtree каждой открытой вкладки смонтированным
под стабильным `tabId`. Переключение только меняет видимую вкладку и не запускает
dirty-exit; Save/Discard применяется при закрытии вкладки, Back или переходе с
её текущего экрана. Поэтому локальные контроллеры формы, фильтры и вложенное
состояние принадлежат вкладке, а не активному viewport.

DECISION: Скрытие forbidden UI не заменяет backend security и не должно
инициировать запрещённый API request.

DECISION (owner, 2026-08-29): Автосохранение применяется к безопасным полям
канонической карточки Lead/Student и versioned staff note: debounce, один
in-flight write, coalescing, row-locked expected version, flush-before-close и
retry без потери ввода. Конфликт не выполняет silent merge: UI сохраняет draft,
загружает актуальную версию и требует явного применения только локально
изменённых полей. Поздний realtime response не заменяет грязный draft. Финансовые, schedule и
другие signed preview/commit-команды остаются явными.

DECISION (owner, 2026-08-29): До завершения перехода выпущенных desktop-клиентов
на build 201 `expectedVersion` для PATCH Lead/Student опционален только на HTTP-
границе. Любая запись всё равно сериализуется row lock и увеличивает version;
переданный stale version отклоняется с `409`. Новый Flutter service требует
version во всех first-party вызовах. Удалить compatibility path можно только
после подтверждённого отсутствия трафика старых клиентов; параллельный endpoint
для этого не создаётся.

## Release

DECISION: Release-ready означает полный автоматический gate плюс platform smoke
и owner UAT для заявленного кандидата. Старое evidence не переносится на новый
build автоматически.

DECISION: Production mutation/deploy требует явного разрешения владельца,
нового backup, проверенного restore/rollback и post-deploy reconciliation.

DECISION: `assets/release_history.json` является версионируемым источником
пользовательской истории выпусков. Publish-скрипт обязан проверить совпадение
верхней записи с `pubspec.yaml` и публикуемым build, затем атомарно разместить
`release-history.json` до переключения update manifests. Клиент использует
серверную историю с bundled fallback.
