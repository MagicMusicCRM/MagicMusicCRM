# MagicMusicCRM — действующие архитектурные решения

Статус: active. Обновлено 2026-09-05.

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

DECISION (owner, 2026-09-03): Окна действий используют существующий общий
presentation-контур `magic_sheet.dart`: центральный Dialog на desktop,
нижний sheet на Android/iOS. `showMagicDialog` принимает существующий редактор,
`showMagicSheet` — содержимое с заголовком и действиями. Material pickers
проходят тот же контур через `magic_picker.dart`. Боковой modal drawer удалён;
маршруты рабочих вкладок, контроллеры, результаты команд и dirty guards сохранены.
Размер формы задаёт общий `DialogTheme` внутри этого контура: 728 логических px
на desktop с ограничением экраном, полная доступная ширина на телефоне.
Локальные устаревшие `SizedBox(width: ...)` не должны сжимать форму.
`ResponsiveDetailRow` задаёт общий перенос длинных подписей и значений в расчётах
и подробностях занятия; узкие формы учитывают масштаб текста, а не только экран.

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

DECISION (owner, 2026-09-03): Edit, reschedule и cancel используют один
адаптивный редактор и одну versioned command family. Resource/financial-only
изменение обновляет actionable Lesson, дата или время создают successor, cancel
использует тот же financial preview. Любой source ID сначала разрешается по
bounded reschedule chain до текущего Lesson; commit повторяет разрешение под
lock и возвращает typed 409 при гонке.

DECISION (owner, 2026-09-03): Reschedule имеет два разных финансовых решения.
Source zero decision `free_lesson/none` создаёт только сервер и фиксирует
append-only; клиент передаёт редактируемый `successorFinancialDecision`. Для
завершённого source zero correction supersedes effective client/teacher facts,
а consumed reservation остаётся историческим; successor получает отдельный
plan, актуальный rate snapshot выбранного teacher и новый reservation. Оба
решения входят в signed fingerprint и коммитятся одной транзакцией.

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

DECISION (owner, 2026-08-30): Назначение абонемента и фактическая оплата — одна
атомарная purchase-команда, но разные append-only финансовые факты. Полная
стоимость всегда создаёт обязательство, а введённая в том же существующем окне
сумма создаёт каноническую оплату только если она больше нуля. Эта оплата
привязывается к абонементу, отражается в его финансовой проекции и не пополняет
личный счёт плательщика; долг и переплата считаются относительно стоимости
самого абонемента. Student и Lead используют один signed preview/idempotent commit
контур; Flutter выполняет его одним действием `Оплатить`, не показывая preview
как отдельный шаг. Backend связывает append-only payment с payment record через
единственное разрешённое runtime-обновление `payments.payment_record_id`; broad
`UPDATE/DELETE` таблицы остаются запрещены. Отдельный legacy writer удалён, а auto-paid поведение клиента v201
сохранено только внутренним compatibility adapter маршрута
`/crm/leads/:leadId/subscriptions/issue` поверх канонического writer. Adapter
удаляется после release/telemetry evidence, что build `<=201` отсутствует в
поддерживаемом окне клиентов; до этого он не получает отдельный writer или DTO.
  Период действия передаётся в том же подписанном снимке: начало может быть
  задним числом, окончание включительно, а по умолчанию отсутствует и означает
  бессрочный абонемент. Все записи выполняются в
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

DECISION (owner, 2026-09-03): Lesson settlement types и teacher compensation
rules — system-owned catalog. User settings surface скрыта, а backend отклоняет
изменение `403 SYSTEM_SETTLEMENT_POLICY_READ_ONLY`. Policy revision задаёт
duration modes `zero/full/manual`, default teacher rule и контексты. Обычное
занятие/`paid_miss` дают full+standard, `free_lesson`/`unpaid_miss` — zero+none,
partial типы требуют независимые client и teacher minutes. Autofill выполняется
один раз; touched значение получает source `manual` и не перезаписывается.
`penalty_lesson` неактивен для новых решений, исторический read сохраняется.

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

DECISION (owner, 2026-09-03): Карточка Student читает одну canonical lesson
timeline без фильтра по Plan: manual/generated/one-off, cancelled и каждый узел
reschedule chain возвращаются ровно один раз с authoritative coverage и
actionable ID. Правила отображаются отдельно: active open-ended, finite по
ближайшей границе, dated exceptions, затем expired от новых к старым. Изменение
одной даты является exception, а не новой текущей версией всего Plan.

DECISION (owner, 2026-09-03): Удаление строки Schedule Plan — signed
preview/commit. Под lock строка retire на `effectiveFrom - 1`, отменяются только
её будущие eligible unfinished generated Lesson, освобождаются reservations,
plan version увеличивается и пишутся audit/outbox. Terminal/manual exceptions
не меняются; последняя строка завершает Plan через общий end path.

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
  создаёт один immutable client fact на участника и ровно один teacher fact на
  Lesson с фактически зачтёнными преподавателю минутами;
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
image поверх schema 0143; destructive down после появления snapshot запрещён.

DECISION (owner, 2026-08-29): Право записи любой teacher rate принадлежит только
Director/system_admin и проверяется в общей backend policy на каждом write-path.
Capabilities и скрытие controls в Flutter являются дополнительной проекцией,
а не заменой этой проверки. Старые operational payload Admin/Manager с teacher
compensation совместимы, но поля игнорируются в пользу stored/default значения;
явные rate CRUD/bulk/correction endpoints остаются закрыты. Payroll read/payout
не расширяют rate-write.

DECISION (owner, 2026-08-29): Новый teacher-stats export строится как XLSX
accrual report по effective teacher facts, включая credited minutes и effective
rate, без payout-полей; stateless OOXML builder предоставляется из
neutral common module, чтобы CRM не импортировал Analytics. Payout storage,
audit и compatibility routes остаются до отдельного adoption/telemetry gate.

DECISION (owner, 2026-09-03): Миграции 0148/0149 только добавляют nullable
provenance и immutable system policy revision. Совместимый application rollback
использует предыдущий image поверх schema 0149; destructive down и удаление
policy revision запрещены. Исторические decision/fact payload без новых полей
читаются через legacy fallback и не переписываются массово.

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
другие signed preview/commit-команды остаются явными. Realtime invalidation
передаёт карточке полный event: Lead/Student фильтруются по entity id, а
comment/task/staff-note обновляют принадлежащие им проекции либо выполняют
background reconciliation без общего loading-state и смены editor epoch.

DECISION (owner, 2026-08-29): До завершения перехода выпущенных desktop-клиентов
на build 201 `expectedVersion` для PATCH Lead/Student опционален только на HTTP-
границе. Любая запись всё равно сериализуется row lock и увеличивает version;
переданный stale version отклоняется с `409`. Новый Flutter service требует
version во всех first-party вызовах. Удалить compatibility path можно только
после подтверждённого отсутствия трафика старых клиентов; параллельный endpoint
для этого не создаётся.

DECISION (owner, 2026-08-30): Email Student-карточки отделён от глобально
уникальной `app.users.email` и хранится как неуникальный contact email самого
Student. Сохранение контакта не переименовывает login identity и не создаёт
неявную привязку к совпавшему app-account. Durable email outbox хранит ссылку
на Student и разрешает актуальный contact email при отправке приглашения;
привязка после подтверждения почты требует outbox-факт с SHA-256 именно этого
адреса, поэтому старое приглашение не переносит право доступа на новый contact
email. Явный `clearEmail` очищает contact email без изменения login identity;
пустой contact не имеет fallback на `app.users.email`. Invite сначала flush-ит
карточку, а worker отправляет student-письмо только если текущий contact email
совпадает с сохранённым outbox hash; иначе stale row завершается без отправки.
Остальные email-сценарии продолжают использовать account identity.

## Release

DECISION: Release-ready означает полный автоматический gate плюс platform smoke
и owner UAT для заявленного кандидата. Старое evidence не переносится на новый
build автоматически.

DECISION: Production mutation/deploy требует явного разрешения владельца,
нового backup, проверенного restore/rollback и post-deploy reconciliation.

DECISION (2026-09-03): Выпуск 210 сначала устанавливает backend bridge с
поддержкой migration 0146, плательщика и снимка цены, затем финальный image
с идентичным backend. После появления новых финансовых фактов или явных
решений об источнике средств откат допускается только на совместимый bridge.
Deploy guard проверяет факты и сохранённые решения после остановки writers;
ошибка проверки или несовместимость запрещает запуск старого runtime.
Restore/reconciliation резервной копии подтверждают восстановимость схемы,
но не совместимость старого worker с новыми решениями. Общий дефект backend
bridge/final требует исправления вперёд; удаление финансовой истории и down
migration для отката не применяются.

DECISION: `assets/release_history.json` является версионируемым источником
пользовательской истории выпусков. Publish-скрипт обязан проверить совпадение
верхней записи с `pubspec.yaml` и публикуемым build, затем атомарно разместить
`release-history.json` до переключения update manifests. Клиент использует
серверную историю с bundled fallback.

## Карточка клиента и координация lesson-команд — 2026-09-05

DECISION: Состояние карточки разделяется по владельцам, а не только по `part`-
файлам. `ClientCardWorkspaceController` владеет секцией, прокруткой и состоянием
вкладки; `ClientCardDataController` — серверными снимками Lead/Student, загрузкой,
ошибками и поколениями запросов; `ClientCardDraftController` — ревизиями локальных
изменений, debounce, очередью записи, конфликтом и flush. Эти контроллеры живут
ровно столько, сколько вкладка. Глобальные зависимости по-прежнему приходят через
существующие Riverpod providers и MagicCrmService. Контроллеры не получают
BuildContext, WidgetRef или прямой доступ к БД.

DECISION: Read-модель и редактируемый снимок не объединяются. Применение серверной
identity остаётся явным и допускается только при неизменившейся ревизии чистого
черновика. Запоздалые ответы и ответы после dispose отбрасывает владелец загрузки.
Commerce читается только после проверки роли; задачи и комментарии ученика
сохраняют своих существующих владельцев и не копируются в ещё один state store.
В UI остаются редакторы, выбор секций, диалоги, сценарии явных команд и применение
черновика. Извлечение контроллеров не меняет бизнес-правило автосохранения.

DECISION: Одиночные terminal-команды `settle`/`cancel` получают shared advisory
lock на прежнем ключе `commerce:multi-lesson-settlement` до aggregate/domain
locks. Они работают с одним уже существующим actionable lesson. Конкурентные
команды этого же занятия сериализуются прежним per-lesson lock; общие кошельки
и абонементы защищаются прежними блокировками ресурсов и проверками ёмкости.

DECISION: Reschedule, bulk, archive, series/plan и изменение planned settlement
сохраняют exclusive gate: их набор занятий или порядок финансовых ресурсов
может расширяться. Повышать shared до exclusive после захвата domain locks
запрещено. Старые серверы используют exclusive на том же ключе, поэтому смешанный
выпуск сохраняет координацию. Безопасный откат приложения возвращает более
консервативную сериализацию; миграции и изменения финансовых фактов для этого
рефакторинга не нужны.

Локальный probe `server/scripts/benchmark-lesson-settlement-gate.ts` измеряет
только ожидание advisory locks с фиксированной искусственной работой. Он не
доказывает производственную пропускную способность. Расширять shared-режим на
новые типы команд можно только после проверки полного порядка захвата ресурсов
и PostgreSQL-тестов пересекающихся операций.


### Client card realtime invalidation — 2026-09-05

DECISION: Realtime карточки объединяется по затронутым разделам. Finance обновляет
только commerce projection через ClientCardDataController с проверкой роли;
полная загрузка ученика поглощает совпадающее финансовое обновление. События
занятий/групп обновляют ученическую read-модель и рабочую историю; изменение
Lead/Student сохраняет полное обновление связей. Задачами управляет SharedTasksPanel.

DECISION: Один batch запросов выполняется за раз. События, полученные во время
загрузки, объединяются в следующий batch; они не теряются и не запускают
перекрывающиеся realtime-загрузки. Неактивные workspace-вкладки (TickerMode)
накапливают только множество затронутых разделов и обновляются при активации.
Начальная загрузка identity завершается до фоновых запросов. Черновики сохраняют
прежнее откладывание обновления до завершения редактирования.

DECISION: Полная и частичная загрузки commerce согласуют поколения ответов,
чтобы устаревшие финансы не затирали свежую проекцию. Финансовые события остаются
без идентификаторов учеников согласно существующему контракту доступа. Фильтрация
финансовых событий по конкретному ученику этим изменением не вводится; новые
серверные события, миграции и изменение финансовых фактов не требуются.


### Correlated performance measurements — 2026-09-05

DECISION: Наблюдаемость расширяет существующий RequestIdMiddleware и MagicApiClient.
Одна строка HTTP-измерений связывается по requestId с клиентом и по operationId
с группой запросов экрана. AsyncLocalStorage на сервере и Zone на клиенте
изолируют параллельные операции. Идентичность финансовых команд не изменяется.

DECISION: DatabaseService измеряет получение соединения и promise-based SQL
в HTTP-контексте. Транзакция остаётся на одном соединении; экземпляр pooled
client не патчится. SQL/параметры/ответы не сохраняются. Результаты SQL-вызовов
суммируются с учётом возможного параллелизма; это не чистое CPU-время БД.

DECISION: Клиентский диагностический буфер ограничен 200 записями. JSON-вывод
включается PERFORMANCE_LOGS, существующие Sentry breadcrumbs сохраняются.
Автоматическая отправка всех успешных запросов и новые Sentry traces не
включаются. Границы измерений, запуск и сводка p50/p95 описаны в
`docs/engineering/PERFORMANCE-DIAGNOSTICS.md`.


### Measured database access paths — 2026-09-05

DECISION: listLessons вычисляет множество действующих групп выбранного ученика
один раз через ANY(ARRAY(...)), вместо коррелированного EXISTS для каждого занятия.
Индивидуальные занятия, left_at IS NULL, ограничения текущей роли в БД и scope
сохраняются. Эквивалентность проверяется полными результатами на PostgreSQL.

DECISION: Миграция 0153 добавляет только индекс чтения текущего резерва занятия:
lesson_id, приоритет reserved, updated_at DESC, id DESC, с покрытием state.
Порядок выбора резерва и бизнес-факты остаются прежними. Индекс принят по
EXPLAIN ANALYZE на временных клонах и сравнению полных результатов запросов.
Второй испытанный индекс lessons не включён без подтверждённого выигрыша.

DECISION: DATABASE_POOL_MAX — проверяемый бюджет соединений одного процесса
в диапазоне 1–50, с прежним default=10. Он не увеличивается автоматически.
Диагностика SQL выполняется metadata-only/read-only инструментом с явно заданным
адресом БД. Отсутствие pg_stat_statements отмечается явно; настройки сервера и
статистика автоматически не изменяются и не сбрасываются.

DECISION: Обычное транзакционное построение индекса ограничено lock_timeout=5s
и statement_timeout=2min. План выпуска должен учитывать блокировку записей и
проверяемый rollback. Детали: docs/engineering/DATABASE-PERFORMANCE.md.

### Expense API contract — 2026-09-05

DECISION: OpenAPI расходов экспортируется из действующих контроллера и DTO.
Типизированные ответы проверяются TypeScript; общий набор синтетических wire-
примеров проверяется Flutter/Dio, ValidationPipe и HTTP/PostgreSQL. Проверка
расхождения с сохранённым OpenAPI доступна без AppModule, БД и runtime Swagger UI.
Другие домены этим документом не считаются покрытыми. Порядок проверки и изменения:
`docs/engineering/API-CONTRACTS.md`.

DECISION: Production TypeScript build включает только src с явным rootDir.
Добавление инструментов вне src не должно менять dist/main.js и dist/db/migrate.js.

### Payment command response consistency — 2026-09-05

DECISION: Создание и смена статуса записи оплаты покрыты генерируемым OpenAPI,
общими Flutter wire-примерами и HTTP/PostgreSQL-проверками. Экспорт по тегам,
проверка схемы и envelope ошибок общие с расходами; другие commerce-команды
не считаются покрытыми. Запуск: scripts/check-api-contracts.ps1.

DECISION: Idempotency сохраняет единственный эффект команды оплаты. Ответ
PaymentLifecycleService читает текущее состояние записи и возвращает её текущую
версию; версия старой команды не подставляется в новые поля. История ограничена
прочитанной версией записи. Это устраняет ложную смесь paid/version=1 после
повтора создания unpaid, когда запись уже имеет version=3. Финансовые факты,
expectedVersion команды, audit/outbox и правила переходов остаются прежними.

### Payment correction and reversal contracts — 2026-09-05

DECISION: Контракт оплаты расширен предпросмотром и подтверждением коррекции и
отмены: всего шесть операций payment-records. Генерируемый OpenAPI, общие примеры
Flutter/Dio и HTTP/PostgreSQL проверяют подписанный preview, явное подтверждение,
устаревшие условия, повтор без дублей и сохранение исходных финансовых фактов.
Команды абонементов и самостоятельных корректировок счёта остаются вне покрытия.
SQL-проекция корректировки явно согласует id с correction_id, используемым сервисом.

DECISION: Commerce scope требует совпадения identity-роли с актуальной ролью
неудалённого пользователя в БД. Предикат находится в существующем SQL разрешения
scope для клиента, сотрудников и глобальных ролей; отдельный запрос не добавлен.
Смена роли закрывает доступ через устаревшую identity, включая read-only preview.
Семейные/филиальные ограничения и транзакционная проверка capability сохраняются.

### Employee release journeys and recovery drill — 2026-09-05

DECISION: Production-like gate дополнен обязательным Windows UI → реальный HTTP →
PostgreSQL сценарием оформления ученика, оплаты, записи, автоматического расчёта
занятия, отмены и возврата. Потеря ответа после commit, двойное нажатие и два
редактора проверяют сохранённое состояние, единственность эффекта, баланс и историю.
Финансовые ответы не подменяются; недоступная push-доставка задаётся тестовым scope.
Неполный server-only режим отмечается явно и не считается полным release evidence.

DECISION: Синтетический restore сравнивает все строки app по хешам и повторяет
финансовую сверку. Реальные encrypted backup проходят прежний изолированный
candidate/rollback drill через локальную Windows-обёртку; второй механизм
расшифровки или восстановления не вводится. Codex запускает проверку еженедельно,
production cron не изменён. Возраст backup учитывается отдельно от restore PASS.
Запуск и границы покрытия: docs/engineering/RELEASE-JOURNEYS.md.

### Safe transport retries — 2026-09-05

DECISION: Общий Flutter API-клиент повторяет connectionTimeout один раз с прежними
метаданными. connectionError и receiveTimeout автоматически повторяются только
для GET/HEAD/OPTIONS. Обрыв соединения не доказывает, что сервер не сохранил
команду; наличие Idempotency-Key в запросе не доказывает поддержку дедупликации
конкретным endpoint. При неопределённом результате записи UI предлагает обновить
данные и проверить результат перед повтором. Явные повторы финансовых форм
сохраняют существующую identity и серверную защиту; новый механизм не вводится.
Проверки: test/core/api/magic_api_retry_test.dart и потеря ответа после commit
в integration_test/employee_journey_live_test.dart. Это устраняет скрытые сетевые
повторы, но не объявляет все CRM-команды защищёнными от повторной ручной отправки.
