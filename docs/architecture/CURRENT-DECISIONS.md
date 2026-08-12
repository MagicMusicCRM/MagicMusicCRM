# MagicMusicCRM — действующие архитектурные решения

Статус: active. Обновлено 2026-08-12.

## Инженерный процесс

DECISION: RepoWise является единственным активным code-intelligence и
agent-navigation слоем проекта. Он используется для overview, поиска symbols и
контекста, оценки риска, health и dead-code анализа. Generated process
framework, обязательные фазовые workflows и вручную поддерживаемые карты кода
не являются источником истины.

Полная запись: `docs/architecture/ADR/ADR_001_REPOWISE_FIRST.md`.

Следствия:

- `AGENTS.md` остаётся коротким и не генерируется RepoWise автоматически;
- решения и продуктовые правила хранятся в обычных текущих документах;
- индекс RepoWise локальный и обновляется из живого checkout;
- low-confidence или mock retrieval проверяется по исходнику;
- documentation ceremony не блокирует небольшую безопасную реализацию.

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
последующие изменения credentials обновляют ту же
identity, не создавая дубль. Пароль никогда не читается и не показывается:
директор видит наличие и время изменения и может задать новый.

DECISION: Роль app user изменяется только versioned-командой
`Настройки → Доступ`. Staff create всегда создаёт безопасную роль `admin`, а
Staff/Teacher cards и старый Profile API не являются поверхностью повышения
ролей. Каноническая команда роли в одной транзакции синхронизирует projection
`staff_members.role`, сбрасывает overrides, повышает access version и пишет
audit/outbox.

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

DECISION: Жёсткие ограничения расписания — активная привязка преподавателя к
выбранному филиалу, рабочие часы преподавателя и филиала, обязательные Branch и
Room, принадлежность Room филиалу и отсутствие пересечений. Рабочие часы
обязательны уже при создании Branch; филиал без графика не принимает занятия.
Discipline/category/level на расписание не влияют. При выборе клиента новый
Lesson получает default Branch из `Student.branch_id`/`Lead.branch_id`, но Room
всегда выбирается оператором явно.

DECISION: Create Lesson требует три независимых финансовых решения:
`settlementTypeKey`, `teacherCompensationRuleKey` и `clientChargeType`.
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

DECISION: Предпочтительное расписание (`schedule-series`) и фактические Lesson
являются независимыми проекциями. UI подтверждает mutation повторным чтением
series; пустая или только что созданная preference-проекция не может скрыть,
удалить либо подменить уже существующие Lesson в карточке клиента.

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

DECISION: Lead loss reason хранит `reason_name_snapshot` и
`reason_kind_snapshot` в каждой исторической смене статуса. Переименование не
меняет прошлую аналитику. `lead_status_history` append-only; единственное узкое
исключение — контролируемый merge/undo может перепривязать только `lead_id`,
оставляя все остальные поля строки неизменными.

## UX

DECISION: Приложение имеет единственную тёмную тему Deep Charcoal &
Sophisticated Gold. Русский — язык UI; desktop и mobile используют общий
канонический navigation/entity contract.

DECISION: Скрытие forbidden UI не заменяет backend security и не должно
инициировать запрещённый API request.

## Release

DECISION: Release-ready означает полный автоматический gate плюс platform smoke
и owner UAT для заявленного кандидата. Старое evidence не переносится на новый
build автоматически.

DECISION: Production mutation/deploy требует явного разрешения владельца,
нового backup, проверенного restore/rollback и post-deploy reconciliation.
