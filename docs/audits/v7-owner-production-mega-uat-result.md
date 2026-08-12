# V7 owner production mega-UAT — рабочая матрица

Run: `OWNER-20260808-01`
Среда: production
Production candidate: `1.5.1+181`, image `sha256:5fbd5a29…`
Статус: **IN PROGRESS**

Текущий итог `100` уникальных утверждённых строк: `10 PASS`, `90 PARTIAL`,
`0 PENDING`, `0 FAIL`, `0 BLOCKED`. Механическая сверка plan/result подтверждает
одинаковый набор из `100` уникальных ID.

`PARTIAL` и `PENDING` допустимы только во время исполнения. Перед `INT-S6`
каждая строка должна стать `PASS`, `FAIL` или `BLOCKED`. `PASS` требует все
применимые UI/API/DB-доказательства из утверждённого плана.

Индекс уже снятых доказательств:
[`v7-owner-mega-uat-evidence/README.md`](v7-owner-mega-uat-evidence/README.md).

## G0 — безопасность и воспроизводимость

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-000 | Зафиксировать commit, образы, миграции и hashes | PASS | production `+181`: client/server revision `17ce254`, exact image `5fbd5a29…`, schema `0118`, artifact/update/transport hashes: `v7-teacher-compensation-181.md`, `v7-production-rollout-181.md` |
| UAT-001 | Backup, пробный restore, начальные counts | PASS | новый `+181` encrypted backup + off-host SHA, isolated restore, candidate migration `0118`, count/reconciliation и cleanup: `v7-production-rollout-181.md` |
| UAT-002 | Release, production API, тёмная тема, реальные данные | PARTIAL | production API и update channels уже на `+181`; Windows/Android `+181` прошли post-rollout launch smoke, но нужен актуальный owner UI proof с production data |
| UAT-003 | ID-ledger и каталог evidence без секретов | PARTIAL | создан единый machine-readable ledger известных production UUID/version/counts с privacy policy и явным `missingRequiredClasses`; телефоны/email/секреты отсутствуют, бизнес-результаты сохранены; нужен owner-проход для заполнения всех оставшихся fact IDs: `UAT-003.md` |

## G1 — авторизация и навигация пяти ролей

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-010 | Вход `magic1..5`, роли и навигация | PARTIAL | post-rollout production login/profile `5/5` PASS: `v7-production-rollout-181.md`; ожидаются актуальные UI-кадры навигации |
| UAT-011 | Relogin Client↔Director и Teacher↔Admin | PARTIAL | automated secure-session regression есть; нужен текущий Release UI proof |
| UAT-012 | 10 вкладок и связанные маршруты | PARTIAL | локальный Windows production-host tour `1/1`: кликами по ФИО/названиям открыты Student/Teacher/Lesson/Group/Room/Branch/Series/Task/Payment/User, проверены canonical breadcrumb, Back/Forward, сохранность исходной вкладки, обычный restart всех 10 вкладок и очистка logout; regressions `33/33`, analyze PASS; нужен production owner Release UI/API повтор: `UAT-012.md` |
| UAT-013 | Android Back, клавиатура, safe areas | PARTIAL | локальный Android 15/API 35 PASS: реальные ADB Back `1/1`, expandable sheet/keyboard/SafeArea `1/1`, Teacher compact nav `1/1`; исправлены отсутствовавшая mobile workspace navigation и reduced-motion `Duration.zero` crash, widget regressions `8/8 + 12/12`; нужен production owner Android Release/predictive-gesture повтор: `UAT-013.md` |

## G2 — конфигурация CRM

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-020 | Категории: создание, порядок, архив | PARTIAL | локальный UI/contract PASS; production owner proof: `UAT-020-029.md` |
| UAT-021 | Все 16 типов полей Lead/Student | PARTIAL | create + existing card используют единый typed storage; нужен production 16×2 readback: `UAT-020-029.md` |
| UAT-022 | Ширины 1/3, 1/2, 1/1 и размещение | PARTIAL | create/edit/card/table реализованы и точечно проверены; нужен production UI: `UAT-020-029.md` |
| UAT-023 | Одиночные/множественные варианты полей | PARTIAL | stable key/reorder/archive и сохранность истории проверены локально; нужен production readback: `UAT-020-029.md` |
| UAT-024 | Обязательные системные и UAT-поля | PARTIAL | локальная Lead/Student UI+API матрица закрыта: обязательные ФИО/телефон/source/branch/status и required UAT field дают понятные inline ошибки, typed success payload и structured `422 {field,code,message}`; исправлен Student refresh конкурентно архивированного source без потери draft; Flutter `7/7`, PostgreSQL `8/8`, controllers `5/5`, analyze/typecheck PASS; нужен production owner UI/API/DB повтор: `UAT-024.md` |
| UAT-025 | Длительность занятия и настройки расписания | PARTIAL | default lesson duration применяется; `payment_reminder_days` теперь управляет durable payer reminder с Branch override, concurrent dedup и retry (`2/2` PostgreSQL, migration `0131`); нужен production owner UI/API/DB-проход: `UAT-020-029.md` |
| UAT-026 | Этапы/переходы Lead и Student | PARTIAL | локальный Student UI/API/DB flow закрыт: configurable allow/deny, реальный PATCH, refetch и счётчики, exact structured `422`, неизменность после отказа, единственная history row и revision rollback; Flutter `17/17`, PostgreSQL `6/6`, CRM `23/23`, analyze/typecheck PASS; нужен production owner two-session повтор для Lead/Student: `UAT-026.md` |
| UAT-027 | 7 списаний и 5 правил оплаты преподавателю | PARTIAL | конструктор/валидация готовы; нужен production settlement каждого варианта: `UAT-020-029.md` |
| UAT-028 | Draft → preview → publish → realtime → rollback | PARTIAL | PostgreSQL version/rollback и UI-flow проверены локально; нужен owner two-session proof: `UAT-020-029.md` |
| UAT-029 | Branch override и RBAC конфигурации | PARTIAL | effective source map и editor RBAC проверены локально; нужен production negative request trace: `UAT-020-029.md` |

## G3 — филиал, люди, графики и права

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-030 | Создать/изменить филиал и увидеть во всех селекторах | PASS | `windows-release/01-branch-list.png` + `api/uat-030-034-organization-inventory-20260810.json` |
| UAT-031 | 3 аудитории, изменение и удаление свободной | PARTIAL | локальный единый UI/API/schema flow закрыт: создание `1/2/8`, edit/readback, занятая защищена блокерами, свободная архивируется с reason/version и исчезает из рабочих селекторов без удаления истории; Flutter `4/4`, server lifecycle/service/migration `13/13`, analyze PASS; нужен production owner mutation+DB повтор: `UAT-031.md` |
| UAT-032 | Часы филиала и закрытый день | PASS | `windows-release/13`, `17` + API version/readback |
| UAT-033 | 3 преподавателя, дисциплины, ставки, филиалы, графики | PARTIAL | локально закрыта полная цепочка: optional email/password и metadata, linked account/readback, UI сохранение versioned branch assignment + recurring availability для всех трёх Teacher, reason-required unavailability и Manager read-only; Flutter `13/13`, backend auth/person/teacher/availability `46/46`, analyze/typecheck PASS; нужен production owner UI/API/DB повтор графиков 02/03 и self-service credential readback: `UAT-033.md` |
| UAT-034 | Сотрудники, роли и app users | PARTIAL | локальная negative matrix закрыта: роль read-only вне `Настройки → Доступы`, Manager без mutation controls, Director только lower roles/no self/no system_admin, root только emergency surface, `409` refetch без partial state; Flutter `19/19`, backend access/actor matrix `143/143`, analyze/typecheck PASS; нужен production owner UI/API/DB повтор: `UAT-034.md` |
| UAT-035 | Capability Manager и realtime-инвалидация | PARTIAL | realtime/accessVersion и Manager branch-scope проверены локально; нужен production two-session owner proof: `UAT-035-054.md` |
| UAT-036 | Группа с преподавателем/филиалом/аудиторией | PARTIAL | create UI, server validation и membership UI проверены; нужен production readback: `UAT-035-054.md` |

## G4 — Lead до конверсии

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-040 | Создать Lead с обязательными данными | PARTIAL | production Lead создан; нужны все назначенные UAT custom fields |
| UAT-041 | Посимвольный поиск, фильтры и карточка | PARTIAL | локально закрыт полный production UI/API/backend flow: search сохраняется, все secondary facets доступны совместно, период `[from,to)`, `newest/oldest` keyset sort, pagination/counts и canonical responsible/source metadata; финальный gate дополнительно исправил card picker `displayName→name`; focused Flutter `6/6 + 11/11`, backend `34/34`, полный gate `786/786 + 175/175 suites/1401 tests`; нужен production owner UI/API повтор empty/error/retry и всех комбинаций: `UAT-041.md` |
| UAT-042 | Статусы, ответственный, история и причины | PASS | `windows-release/25..32` + production DB/API |
| UAT-043 | Duplicate → merge → undo | PASS | `windows-release/33..37` + DB reconciliation |
| UAT-044 | Подписанный webhook и idempotency | PASS | `windows-release/38..40` + ingestion/outbox DB reconciliation |
| UAT-045 | Пробное занятие из Lead | PARTIAL | локально закрыт полный Lead card → client month/default branch → required teacher/room → visible calculation snapshot → constraint preview → atomic create/DB readback; Flutter `27/27`, PostgreSQL `1/1`, analyze/typecheck PASS; нужен production owner UI/API/DB повтор: `UAT-045.md` |
| UAT-046 | Задача по Lead и закрытие Admin | PASS | `windows-release/48..57` + task DB reconciliation |
| UAT-047 | Конкурентная конверсия Lead → Student | PARTIAL | PostgreSQL double-command создаёт один Student/link; нужен production UI/DB proof: `UAT-035-054.md` |

## G5 — карточка ученика

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-050 | Длинная desktop-карточка и mobile tabs | PARTIAL | постоянный левый rail и compact Windows flow PASS; нужны owner Windows/Android кадры: `UAT-035-054.md` |
| UAT-051 | Основные поля, staff note и комментарии | PARTIAL | staff-only note и shared-comment RBAC/UI PASS; нужен production role repeat: `UAT-035-054.md` |
| UAT-052 | Представитель, плательщик, family и linked user | PARTIAL | payer/link/invite/entity-text UI доведены и проверены; нужен production readback/delivery: `UAT-035-054.md` |
| UAT-053 | Дополнительные поля внутри Overview | PARTIAL | automated/widget proof есть; нужен production Student UI |
| UAT-054 | Ученик и плательщик в группе | PARTIAL | локальный add/remove learner+payer UI и server scope PASS; нужен production DB/API proof: `UAT-035-054.md` |

## G6 — личный счёт, оплаты и абонементы

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-060 | Три статуса оплаты (`Проведён, ожидает подтверждения`) и долг | PARTIAL | локально восстановлена единая каноническая подпись во всех точках UI; widget-проверки подтверждают три статуса, переход `pending → unpaid` с обязательной причиной и техническое сторно, Windows client-workspace device `4/4`; нужны production UI/API/DB evidence и negative transitions |
| UAT-061 | Наличные/безналичные, реквизиты и автор | PARTIAL | локально форма и PostgreSQL подтверждают оба способа, дату/идентификатор/примечание, immutable ActualPayment и targeted realtime; нужен production UI/API/DB и вторая живая сессия |
| UAT-062 | Каталог 12×60/30000 и альтернативный пакет | PARTIAL | локально доказаны school/branch publish, update, archive/filter/restore и immutable snapshot; нужен production owner-проход |
| UAT-063 | Покупка абонемента со своего счёта | PARTIAL | локально exact none/percent/fixed purchases и остаток кошелька сходятся; нужен production UI/API/DB |
| UAT-064 | Покупка со счёта другого клиента | PARTIAL | локально обязательная причина, обе resource scope и безопасный replay доказаны; нужен production UI/API/DB |
| UAT-065 | Рассрочка с полным резервом и частями | PARTIAL | локально точные части, полный reserve, due pending и transition доказаны; нужен production worker/UI/API/DB |
| UAT-066 | Долг/pending/paid/переплата/остатки | PARTIAL | локальная Client-карточка показывает пакет, used/total, paid/debt/pending/overpayment/next payment; нужен Android production-проход |
| UAT-067 | Замена активного абонемента | PARTIAL | локально signed preview/commit, один активный результат, exact difference, concurrency и stable Retry доказаны; нужен production owner-проход |
| UAT-068 | Отмена абонемента и возврат | PARTIAL | локально impact, release reserve, refund original payer, installment cap и replay доказаны; нужен production owner-проход |
| UAT-069 | Сторно unpaid/pending/paid и exclusion | PARTIAL | локально technical void и monetary reversal исключают строки из ordinary projection, сохраняя actor/reason history; нужен production UI/API/DB/analytics |
| UAT-06A | Корректировка/возврат счёта и повтор | PARTIAL | добавлено append-only сторно корректировки с signed preview, version/idempotency/audit/outbox; PostgreSQL и widget доказали opposite fact/exclusion/replay; нужен production owner-проход |

## G7 — предпочтительное и постоянное расписание

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-070 | Предпочтительное расписание | PARTIAL | локально доказаны сохранение `schedule-series`, обязательный read-after-write через повторный GET и отображение сохранённой строки; при полностью пустых предпочтениях/Plan фактическое занятие остаётся видимым, а после добавления предпочтения не исчезает; widget `28/28`, backend schedule `60/60`, тёмный Windows device `1/1` и два UI-кадра PASS; нужны production UI/API/DB evidence |
| UAT-071 | Индивидуальный Plan на несколько дней | PARTIAL | локально доказан один атомарный индивидуальный Plan из трёх series: два дня используют одного преподавателя и аудиторию, третья строка — другого преподавателя и аудиторию; create/read-after-write UI, idempotent PostgreSQL persistence, повторная materialization без дублей, widget `12/12`, тёмный Windows device `1/1` (весь файл `4/4`) и два UI-кадра PASS; нужны production UI/API/DB evidence |
| UAT-072 | Групповой Plan и participant subscriptions | PARTIAL | локально доказаны UI-точка входа из Group, preview/create payload с отдельным абонементом каждого ученика, датированное versioned-изменение состава и fail-closed удаление membership; нужны production UI/API/DB evidence |
| UAT-073 | Полная canonical conflict matrix и редактируемый конфликтный Plan | PARTIAL | локально доказаны create/update preview через единый constraint engine, все 8 категорий, полная матрица строк и участников, отсутствие самоконфликтов заменяемых series при сохранении перенесённых Lesson-блокеров, удержание и повторное редактирование конфликтного черновика без PATCH; нужны production UI/API/DB evidence |
| UAT-074 | Active/ended планы и завершение | PARTIAL | локально доказаны UI-переход той же записи `Active → Ended` после commit/readback, скрытие write-действий, staff-only причина/автор, impact preview, idempotency/stale/rollback, общий lock с materializer, ограничение series последней датой, отмена только будущих unsettled Lesson с release резервов и сохранение terminal/history; Windows device `1/1`; нужны production UI/API/DB evidence |
| UAT-075 | Tray, cursor и authoritative markers | PARTIAL | локально доказаны bounded tray, стабильный keyset cursor `(scheduled_at, lesson.id)` в обе стороны, tie-break одинакового времени, fail-closed invalid cursor/direction, точный retry неуспешной страницы без потери текущей, teacher/date/time/period/room, authoritative settlement/relation markers и свёрнутый ended archive; Flutter model/widget, PostgreSQL integration и Windows device `2/2` PASS; нужны production UI/API/DB evidence |
| UAT-076 | Скрывать чужие и независимо отмечать target | PARTIAL | один production календарный контекст PASS; локально доказаны default-on hide во встроенном календаре, раскрытие чужих без client-scoped matrix refetch, отдельные target/other markers в Month, Week, Day-by-room и Day-by-teacher, state restore и backend deny для Client; маршрут из карточки отдельно открывает основной Branch с выключенным hide, зелёным target/серыми остальными и предзаполняет клиента/Branch в форме создания; targeted Flutter `69/69`, Windows client-calendar `1/1`, полный Flutter `737/737`; нужны production Month/Week/оба Day и route UI/API evidence |

## G8 — списания и оплата преподавателю

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-080 | Обязательные settlement/pay choices | PARTIAL | локально реальная форма требует и независимо отправляет тип списания, правило оплаты преподавателю и источник средств; пустой каталог и пять неполных/несогласованных команд fail-closed не создают Lesson/Plan, валидный create атомарно сохраняет snapshot, settlement plan и revision в PostgreSQL; widget `11/11`, backend parity `5/5`, тёмный Windows device `1/1` (весь файл `2/2`) и два UI-кадра PASS; нужны production UI/API/DB evidence |
| UAT-081 | Все 5 правил teacher pay | PARTIAL | локально доказана единая матрица `none/standard/percent/fixed/hourly`: UI показывает и выбирает все пять правил, корректно форматирует процент/фиксированную/почасовую величину и блокирует override без причины; реальная PostgreSQL settlement сохраняет label/mode/default/actual/amount/revision для каждого правила, отклонённый override не оставляет client/teacher facts, валидный сохраняет причину; calculation `6/6`, decision widget `3/3`, PostgreSQL `6/6`, тёмный Windows device `1/1` (весь файл `3/3`) и три UI-кадра PASS; нужны production UI/API/DB evidence |
| UAT-082 | Абонемент по умолчанию и личный счёт | PARTIAL | локально активный абонемент автоматически выбирается вместе с конкретным `subscriptionId`, личный счёт остаётся явной альтернативой без reservation, а `Без списания` доступно для нулевого settlement и очищает абонемент; платный/штрафной settlement с `none` fail-closed отклоняется как `CLIENT_FUNDING_SOURCE_REQUIRED` без частичных Lesson/Plan; widget `12/12`, calculation `7/7`, backend parity `5/5`, transition PostgreSQL `4/4`, тёмный Windows device `1/1` (весь файл `4/4`) и два новых UI-кадра PASS; нужны production UI/API/DB evidence |
| UAT-083 | Пробное и бесплатное занятия | PARTIAL | локально trial доказан как независимый immutable marker, а бесплатность — как отдельный `free_lesson/none`: UI покрывает четыре комбинации trial/non-trial × paid/free, тёмный Windows показывает пробное платное занятие с личного счёта, PostgreSQL completion matrix подтверждает trial paid `80000` minor, non-trial paid subscription `1.00` с consumed reservation и оба free-варианта `0/0.00` без списания активного абонемента; widget `14/14`, completion PostgreSQL `10/10`, Windows device `1/1` (весь файл `4/4`), полный gate PASS; нужны production UI/API/DB evidence |
| UAT-084 | Реальное ожидание completion worker | PARTIAL | локально PostgreSQL fixture сначала остаётся не-due без work/facts, затем production `onModuleInit` worker с реальным `1000ms` polling дожидается scheduled end и применяет заранее сохранённый subscription plan ровно один раз: work `completed/attempts=1`, по одному transition/client fact/teacher fact/audit/outbox/idempotency, reservation `consumed`, plan `settled`; дополнительный tick не создаёт дублей; completion PostgreSQL `11/11`, schedule `9/9` suites и `38/38` tests, полный gate PASS; нужны production worker/UI/API/DB evidence |
| UAT-085 | `Конфликт` и `Исправить расчёт` при ошибке worker | PARTIAL | локально poison worker после bounded retry переводит Lesson в `settlement_pending`, а plan — в `review_required` с безопасным failure code; staff schedule получает актуальные `version`/причину, карточка показывает `Конфликт`, безопасный русский текст и единственное действие завершения `Исправить расчёт`, preview отправляет `expectedVersion=2`; Client/Teacher failure code не получают; прямой settle обычного `scheduled` Lesson возвращает `409 LESSON_SETTLEMENT_REVIEW_NOT_REQUIRED`, успешный recovery атомарно ставит plan `settled` и очищает failure, rollback не создаёт facts; backend targeted `71/71`, Flutter targeted `68/68`, тёмный Windows device `1/1`, полный gate PASS; нужны production worker/UI/API/DB evidence |
| UAT-086 | Post-completion correction/reschedule с reversal и successor | PARTIAL | локально completed Lesson переносится только через signed preview/idempotent transaction: UI фиксирует безопасный `free_lesson/none`, объясняет append-only отмену и не показывает raw warning; PostgreSQL fault после создания replacement facts полностью откатывает correction/successor, успешный commit сохраняет исходные facts и consumed reservation как историю, делает их неэффективными через superseding facts, создаёт successor с клонированным `paid_miss` plan и новым reservation; worker завершает successor ровно один раз (`attempts=1`, по одному transition/client/teacher fact), второй tick `0/0`; decision/edit `18/18`, PostgreSQL `4/4`, тёмный Windows device `1/1`, полный gate PASS; нужны production UI/API/DB evidence |
| UAT-087 | Group common + per-client override | PARTIAL | локально закрыт найденный UI-разрыв: schedule matrix отдаёт только активных frozen participants с именами, единая форма показывает общий settlement и отдельный `Как у всей группы`/override для каждого ученика, отправляет только явные `clientDecisions`, а preview подписывает оба client facts именами; реальный PostgreSQL одной транзакцией применил персональный `lesson` к участнику по абонементу (`settled 0→1`, `reserved 1→0`, reservation `reserved→consumed`) и общий `partially_paid_lesson` к участнику с личным счётом (`40000`), сохранил label/color/config revision, ровно 2 effective client facts и 1 teacher fact; 8 повторов не создали дублей; mapper/decision targeted `61/61`, backend group settlement `6/6`, тёмный Windows device `5/5` и два UI-кадра, полный Flutter `712/712`, backend `168/168` suites и `1315/1315` tests, analyze/typecheck/build PASS; нужны production UI/API/DB evidence |

## G9 — переносы, отмены и конфликты

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-090 | Перенос через форму без drag-and-drop | PARTIAL | локально рабочий путь quick view → реальная форма → обязательные reason/settlement/teacher pay → signed preview → idempotent commit действительно меняет дату без drag-and-drop и перечитывает расписание; форма поддерживает индивидуальные и групповые Lesson с сохранением frozen subject/participants и блокирует фиктивный перенос без изменения времени или ресурсов; widget `35/35`, PostgreSQL reschedule `5/5` (включая group/replay/cardinality), тёмный Windows device `1/1` и два UI-кадра, полный Flutter `714/714`, backend `168/168` suites и `1316/1316` tests, analyze/typecheck/build PASS; нужны production UI/API/DB evidence |
| UAT-091 | Подмена преподавателя и аудитории | PARTIAL | локально форма показывает только active преподавателей, назначенных в выбранный филиал, и только его active аудитории; отдельно объясняет, что занятость проверяется перед сохранением, а signed preview выводит русские причины teacher/room overlap и branch mismatch; финансовый каталог берётся для successor branch; реальный PostgreSQL отказал занятой паре без токена, принял свободную подмену, сохранил новые `teacher_id`/`room_id` и одну transition при idempotent replay; targeted widget `25/25`, PostgreSQL reschedule `6/6`, тёмный Windows device `1/1` и два UI-кадра, полный Flutter `718/718`, backend `168/168` suites и `1317/1317` tests, analyze/typecheck/build PASS; нужны production UI/API/DB evidence |
| UAT-092 | Все one-time/recurring conflict entry points | PARTIAL | локально все write-path сведены к каноническому constraint engine: one-time create повторно валидирует draft под общими resource/client locks, reschedule использует signed preview/version/idempotent commit, Plan preview/create/update проверяют каждую строку/occurrence/участника, а horizon materializer больше не имеет отдельного teacher/room-only SQL-обхода; закрыты branch-timezone selection/materialization, несовпадающие Plan/client lock keys, SQL NULL self-exclusion standalone Lesson и group overlap по immutable snapshot participant; room availability подтверждён как read-only occupancy projection и подписан `Без занятий/С занятиями`, dashboard/week/day открывают полную форму, drag-and-drop отсутствует; PostgreSQL отказ оставляет `0` частичных Lesson; targeted backend `7/7` suites и `88/88`, targeted Flutter `40/40`, тёмный Windows device `1/1` и `lesson-constraint-blocked-preview.png` со всеми 8 русскими причинами и `commit=0`; полный Flutter `719/719`, backend `168/168` suites и `1319/1319` tests, analyze/typecheck/build PASS; нужны production owner UI/API/DB evidence |
| UAT-093 | Два Manager бронируют один слот | PARTIAL | локально два независимых Manager actor/session identity с разными idempotency/request IDs одновременно отправили одинаковый draft: PostgreSQL дал ровно `1` winner и `1` structured `422` с teacher/client/room overlap; сохранились ровно по одному Lesson, snapshot, settlement plan/revision, aggregate version, audit, outbox и idempotency record, у loser нет частичных фактов; Flutter сохраняет весь черновик после authoritative commit conflict; targeted backend `5/5`, widget `19/19`, тёмный Windows device `1/1` и два UI-кадра, полный Flutter `719/719`, backend `168/168` suites и `1319/1319` tests, analyze/typecheck/build PASS; нужны production owner UI/API/DB evidence двух реальных Manager-сеансов |
| UAT-094 | Отмена применимыми типами | PARTIAL | локально один canonical preview/confirm/version/idempotency path проверен для всех пяти cancel-типов: free/paid/partial/unpaid/penalty; PostgreSQL фиксирует точные hours, balance, consumed/released reservation, независимую teacher pay, labels/colors, configuration revisions, reason history, один fact/transition/audit/outbox/idempotency и exact replay; settle-only типы дают `422` без side effects; общий Flutter flow после `STALE_LESSON_VERSION` сохраняет ввод, принимает `currentVersion`, сбрасывает устаревшие preview/identity и предлагает понятный новый расчёт без `Bad state`; targeted backend `7/7`, Flutter `7/7`, тёмный Windows device `1/1` и три UI-кадра, полный Flutter `720/720`, backend `168/168` suites и `1320/1320` tests, analyze/typecheck/build PASS; нужны production owner UI/API/DB evidence реальных branch catalog типов |
| UAT-095 | Единая Lesson во всех представлениях | PARTIAL | локально Month/Week/оба Day и календарь карточки клиента сведены к `_showLessonDetails → CreateLessonDialog.show`; исправлен тупиковый paged/Group tray: bounded item вне fallback теперь гидратирует полную Lesson точным actor-scoped `GET /crm/lessons?lessonId=...` и открывает тот же editor, terminal state доступен только exact-ID запросу, обычный список не расширен; Windows подтверждает canonical editor и Back в тот же Day с точной датой, раскрытым client-filter и тем же vertical scroll, widget — точный tray request и сохранённый horizontal scroll; protected reason/signed-preview/confirm/version/idempotency flow не обходится; targeted widget `13/13`, backend schedule `58/58`, тёмный Windows device `1/1` и два UI-кадра, полный Flutter `721/721`, backend `168/168` suites и `1321/1321` tests, analyze/typecheck/build PASS; нужны production owner UI/API/DB evidence календаря, client card и paged/ended tray |

## G10 — заметки, комментарии, задачи, ДЗ и история

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-100 | Staff note и скрытие от Client/Teacher | PARTIAL | backend/widget gates есть; нужен production role proof |
| UAT-101 | Hidden/share-with-teacher комментарии | PARTIAL | локально Manager создаёт скрытый комментарий и versioned-публикует Teacher; исправлен реальный async `setState` дефект успешного refresh; PostgreSQL доказывает exact Teacher/Client projections, 4 staff-роли, deny/stale/replay, один audit/outbox без private body; тёмный Windows `1/1` и три UI-кадра, targeted backend `9/9`, Flutter `6/6`, полный Flutter `721/721`, backend `168/168` suites и `1321/1321` tests, analyze/typecheck/build PASS; нужны production owner UI/API/DB role evidence |
| UAT-102 | All-day/interval задачи и reminder | PARTIAL | локально закрыты all-day/interval, person/branch/school exact preview→recipients, явное время reminder, retry-dedupe и Windows route/read-state: Flutter `724/724`, backend `168/168` suites и `1324/1324` tests, Windows `3/3`, analyze/typecheck/build PASS; нужны production owner UI/API/DB evidence |
| UAT-103 | Admin board: Мои+Сегодня, scopes, close | PASS | `windows-release/52..57` + DB reconciliation |
| UAT-104 | ДЗ с файлом из Прогресса | PARTIAL | локальные backend/service/widget gates PASS: assignment/submission, private download, orphan rollback и lesson binding; нужен production role UI/API/DB proof |
| UAT-105 | Operational history авторов/причин | PARTIAL | локально bounded audit-проекция теперь связывает conversion, payment/reversal, reschedule/cancel/settle, note, comment sharing и linked shared task; добавлены безопасные русские причины, автор/время и regression отсутствия private comment body; targeted PostgreSQL `9/9`, Flutter context `6/6`, полные gate PASS; нужен единый production owner UI/API/DB маршрут всех семейств |

## G11 — чат, уведомления и остальные разделы

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-110 | Direct chat: text/image/file/voice | PARTIAL | локально закрыты Client→Administration и Teacher↔Manager message contract: text/image/file/voice persistence, edit/delete/reaction/pin/read, voice duration reload, upload ownership/rollback, reply/forward scope и media tombstone; PostgreSQL + Windows + полный gate Flutter `729/729`, backend `170/170` suites/`1342/1342`; нужны production owner UI/API/DB evidence обоих ролевых диалогов |
| UAT-111 | Group/channel permissions/lifecycle | PARTIAL | локально закрыты Group create/add/remove/leave и Channel create/edit role+user ACL, separate write/manage, authoritative `canWrite`, realtime lifecycle; support assign/unassign/archive/unarchive доказан на PostgreSQL; миграция `0126`, Windows `2/2`, Flutter `735/735`, backend `171/171` suites/`1352/1352`; нужны production owner UI/API/DB evidence |
| UAT-112 | Lead/task/lesson notifications | PARTIAL | inbound Lead production PASS; Task и Lesson локально закрыты durable materialization, exact routes/role audience, retry-dedupe, persisted read-state и тёмным Windows device; Lesson использует frozen group snapshot, successor для Client/new Teacher и source для снятого Teacher; полный gate Flutter `725/725`, backend `168/168` suites и `1330/1330` tests; нужны production owner Task/Lesson UI/API/DB evidence |
| UAT-113 | Teacher rates, accrual, payout, stats, CSV | PARTIAL | локально Director/system_admin изменяет и audited-void удаляет ставки/выплаты с reason/version/idempotency/audit/outbox, а Admin/Manager на этих item routes получают deny; строки остаются в БД, но исключаются из рабочих проекций. Массовая директорская ставка исправляет и settled Lesson через superseding compensation fact без переписывания старого. CSV использует ту же projection/filters, UTF-8 BOM, escaping/formula protection и UI file opener; Windows device `2/2` включает Export→BOM/кириллица/filters без внешнего приложения, widget/report `16/16`, PostgreSQL `4/4`; полный pre-change gate Flutter `737/737`, backend `172/172` suites и `1374/1374` tests; нужен production owner UI/API/DB/CSV-повтор: `UAT-113.md` |
| UAT-114 | Expenses и finance RBAC | PARTIAL | Локально Director прошёл create/edit/confirm delete/readback в фильтре Branch и управляет любой из `50` загруженных строк, не только тремя последними; PostgreSQL сверил `1250→1750→delete` с list/Analytics, soft-delete, audit/realtime и Manager deny для всех четырёх операций. Widget `6/6`, PostgreSQL `3/3`, тёмный Windows `1/1`; полный gate Flutter `742/742`, backend `172/172` suites/`1376/1376`. См. `UAT-114.md`. Нужен production owner UI/API/DB-повтор. |
| UAT-115 | Data quality и deletion request | PARTIAL | Локально phone-review стал действующей очередью: исправление канонического RU-телефона или принятие как есть требуют причину, row lock, атомарный source/queue update и audit без raw phone. Deletion lifecycle: Client отменяет только pending; Admin/Director/system_admin ведёт `pending→processing→completed/rejected`, Manager read-only. Completion в одной транзакции анонимизирует точный target и отзывает login/session, но сохраняет legal/business history; PostgreSQL sentinel доказал неизменность соседнего owner. Тёмный Windows device покрыл все три сценария за прогоны `2+1`; полный gate Flutter `747/747`, backend `174/174` suites/`1387/1387`, analyze/build PASS. См. `UAT-115.md`. Production и реальный `magic1` не изменялись; нужен owner UI/API/DB-повтор на disposable UAT-client. |
| UAT-116 | Loading/empty/error/forbidden/retry UI | PARTIAL | Локально основные Client/Teacher/Admin/Manager/Director поверхности перестали маскировать сбой как пустой список и показывать raw exception. Client занятия/абонемент/оплаты/ДЗ, Messenger chats/messages, профиль, legal gate, overview, teacher report и System Settings получили постоянное безопасное error-состояние с повтором того же запроса; ошибка проверки capability отделена от реального forbidden. Настроечные списки Branch/Group/Package/Staff/Teacher используют общий `MagicPageState`. Widget recovery matrix `9/9`, полный Flutter `756/756`, analyze PASS; найденный тестом 1px overflow KPI-карточек исправлен. См. `UAT-116.md`. Нужен production owner UI-проход loading/empty/error/forbidden/retry на основных ролях. |

## G12 — аналитика, поиск и экспорт

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-120 | Общие period/branch filters | PARTIAL | Локальный Windows device подтвердил один period/branch filter для status, lesson-success, school-finance и обоих export-запросов, включая readback после смены Branch; см. `UAT-120-122.md`. Нужен production owner UI/API-повтор. |
| UAT-121 | Manager без school finance | PARTIAL | Локальный Manager UI не показывает finance KPI/export/journal и не отправляет `/school-finance`; PostgreSQL подтвердил backend `403`, а Director — корректную проекцию. Нужен production owner UI/API-повтор. |
| UAT-122 | XLSX OOXML и сверка строк/сумм | PARTIAL | Локально ExcelJS повторно открыл XLSX, сверил колонки/строки/кириллицу с CSV, finance-суммы и формулу `revenue-expenses`; клиент fail-closed отклоняет повреждённый XLSX/CSV до сохранения и честно различает open/save. Нужен production owner export-повтор. |
| UAT-123 | Поиск Lead/Student/teacher/room/lesson | PARTIAL | production Lead search PASS; локальный canonical Schedule посимвольно находит Lead/Student/Teacher/Room через exact actor-scoped matrix filters, занятие — по точной дате, сохраняя focus/text/view/date/vertical scroll; widget `7/7`; нужен production owner UI/API-повтор всех пяти сущностей: `UAT-120-122.md` |

## G13 — нагрузка и аварийные проверки

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-130 | Double-submit/idempotency mutations | PARTIAL | локальный единый gate покрывает Lead conversion, ActualPayment, Subscription purchase, Shared Task close и Lesson transition: PostgreSQL `4/4` suites, `35/35`, Flutter double-click/stable Retry `54/54`; каждая команда даёт один business fact/audit/outbox либо stable replay, changed fingerprint fail-closed; нужен production owner UI/API/DB cardinality-повтор: `UAT-130.md` |
| UAT-131 | Обрыв сети, сохранение формы и Retry | PARTIAL | локально payment draft и stable identity сохраняются, issue/replace/cancel безопасно повторяются; 401 использует single/shared refresh, stale session не разлогинивает новый login; нужен Release network/expired-session owner-проход |
| UAT-132 | Stale expectedVersion и recovery | PARTIAL | automated contracts есть; нужен production UI scenario |
| UAT-133 | Полная actor matrix private routes | PARTIAL | текущий candidate run PASS: private route coverage `344/344`, scopes `344`, unexplained allows `0`; actor/payload leak `9/9`, route policy/evaluator/guard `132/132`; unknown capability/resource mismatch fail-closed, Client/Teacher PII/finance leak `0`; нужен production owner negative-request trace: `UAT-133.md` |
| UAT-134 | Full tests/build/migrations/clean schema | PARTIAL | полный gate текущего checkout обнаружил и закрыл несовместимость responsible `name/displayName`; итог Flutter `786/786`, backend `175/175` suites и `1401/1401` tests, analyze/typecheck/build/diff-check PASS; нужны clean-schema/exact-image runtime/security, Windows/Android smoke и hashes; production `+181` остаётся историческим; evidence `UAT-134-final-local-gate.md` |
| UAT-135 | Health, constraints, reconcile, workers, logs | PASS | `+181` internal/public ready, migration `0118`, worker/outbox, reconciliation twice, restart/log/5xx и latency: `v7-production-rollout-181.md` |

## G14 — пять персон и итоговое доказательство

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-140 | Client Android persona | PARTIAL | локальный полный ClientDashboard tour прошёл Android 15/API 35 `1/1` и mobile viewport: chat, lessons/history/homework, subscription/payments/profile; trace не содержит foreign/staff-finance запросов; нужен production owner Android/API evidence |
| UAT-141 | Teacher Android persona | PARTIAL | локальный mobile tour проходит Chat/assigned Schedule/assigned Students без create/commerce/contacts/internal-note; исправлена отсутствовавшая compact workspace navigation, widget `12/12`, Android 15/API 35 Teacher `1/1`, общий Windows device `5/5`; нужен production owner Android/API/scope evidence: `UAT-140-143.md` |
| UAT-142 | Admin Windows persona | PARTIAL | локальный Windows tour проходит Chat/Schedule/Clients/Tasks, подтверждает `Мои + Сегодня` и отсутствие Overview/Analytics/Settings/school-finance; общий device `5/5`; нужен production owner Windows/API/scope evidence: `UAT-140-143.md` |
| UAT-143 | Manager Windows persona | PARTIAL | локальный Windows production-workspace tour прошёл overview/schedule/clients/tasks/analytics/settings; нет school-finance/global payments/expenses и package/access mutations; нужны production owner Windows/API/scope evidence |
| UAT-144 | Director Windows persona | PARTIAL | локальный Windows tour проходит все семь workspace-разделов, Finance XLSX, school-finance и управляемый каталог абонементов; общий device `5/5`; нужен production owner Windows/API/scope evidence: `UAT-140-143.md` |
| UAT-145 | Архивация завершает recurring work и сохраняет историю | PARTIAL | локально: PostgreSQL lifecycle `1/1`, Flutter role/widget `4/4`, Windows preview+commit `1/1`; recurring work завершён, one-time/finance/task/history сохранены; production owner-проверка не выполнялась; evidence `UAT-145.md` |
| UAT-146 | Итоговый DOCX и подпись владельца | PARTIAL | pre-final DOCX со всеми 100 строками и полями PASS/FAIL/BLOCKED подготовлен; production owner-UAT и итоговая подпись отсутствуют; evidence `UAT-146.md` |

## Решение кандидата

**NOT YET APPROVED** — `T7.1.2` продолжается. `INT-S6` нельзя закрывать, пока
остаются `PARTIAL`/`PENDING`, открытый P0, необъяснённый drift/error либо
отсутствующее ролевое доказательство.
