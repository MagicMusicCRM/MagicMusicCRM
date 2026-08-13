# MagicMusicCRM — актуальная передача

> Обновлено: 2026-08-14
> Production: client `1.5.7+187`, server `23688482`,
> image `sha256:5b2f5c3b…`, migration `0135`
> Рабочая ветка: `codex/v7-production-readiness`
> Статус: production/client rollout `1.5.7+187` PASS;
> owner mega-UAT не завершён

Server hardening `23688482` закрыл найденные backend/infra источники 500 и
невидимых фоновых сбоев: UUID валидируются до PostgreSQL, readiness деградирует
в `503`, async exports восстанавливаются после рестарта, OTP не создаёт
неиспользуемый challenge при недоставленном письме, а ошибки notification /
analytics workers журналируются. Production теперь работает с
`NODE_ENV=production`, все обязательные workers fail-closed включены, Caddy
пишет JSON access log и минутный monitor установлен в deploy-user cron.
Backend `182/182` suites и `1439/1439` tests, exact image, Semgrep, Gitleaks,
Trivy, encrypted off-host backup, alert/recovery drill, readiness и
reconciliation PASS. Первый cutover безопасно откатился только из-за неверного
имени таблицы в deploy-only проверке; после исправления повторный cutover PASS.
Evidence: `docs/audits/v7-production-backend-error-hardening-23688482.md`.

Server hotfix `2d1c6255` восстановил единый справочник уровней и категорий в
карточке и форме создания преподавателя. Новый unified CRM snapshot больше не
содержит старый `entityType`, а после clean-start отсутствуют отдельные
teacher-поля; read-adapter теперь принимает unified shape и формирует
неpersisted teacher projection из тех же option sets. Production readback
вернул уровни `Без опыта / Начальный / Средний` и категории `Взрослые / Дети`.
Backend `1426/1426`, Flutter targeted `2/2`, exact image/security gates,
encrypted off-host backup, readiness `10/10` и reconciliation PASS. Клиентские
manifests не менялись; build `187` получает исправление с сервера. Evidence:
`docs/audits/v7-production-teacher-options-hotfix-2d1c6255.md`.

Server hotfix `5f7bce2b` исправил production OTP-loop привилегированных ролей:
`login()` требовал forced OTP, но `verifyOtp()` без персонального 2FA-флага не
выдавал session даже после валидного кода. Теперь оба этапа используют одно
правило; клиент дополнительно не уходит с OTP-экрана без session. Backend
`1425/1425`, Flutter auth `16/16`, exact image/security gates, encrypted
off-host backup, readiness `5/5` и reconciliation PASS. Клиентские manifests
не менялись; build `187` получает исправление с сервера. Evidence:
`docs/audits/v7-production-otp-hotfix-5f7bce2b.md`.

Release `1.5.7+187` опубликован в обоих update channels и GitHub Release.
Закрыты Staff/Teacher save `500`, выбор роли и нескольких филиалов при
создании/редактировании, legacy-совместимость unified CRM publish и потеря
состояния desktop-вкладок. Дополнительно platform outbox теперь обрабатывает
organization lifecycle events; `0135` безопасно переиграла ранее
dead-lettered branch event без изменения append-only факта. Flutter `796/796`,
backend `180/180` suites и `1424/1424` tests; exact image, Windows
portable/Setup, Android API 35 update, backup/off-host copy, rollback drill,
двойной reconciliation и public download verification PASS. Production
outbox `0 pending / 0 dead`, API restart `0`. Evidence:
`docs/audits/v7-release-candidate-187.md` и
`docs/audits/v7-production-rollout-187.md`.

Release `1.5.3+183` опубликован в обоих update channels и GitHub Release.
Production очищен до двух сохраняемых аккаунтов, системного чата, источника
`Приложение`, `10` системных и `40` полезных пользовательских полей; все
`hollihopId` удалены. Клиенты, остальные люди, организация, расписание,
коммерция, сообщения, задачи и uploads равны нулю. Full gate: Flutter
`789/789`, backend `177/177` suites и `1415/1415` tests; exact image,
backup/off-host restore, rollback compatibility, Windows/Android smoke,
post-reset DB/runtime gate и reconciliation PASS. Evidence:
`docs/audits/v7-production-rollout-183-clean-start.md`.

Release `1.5.2+182` доставил в production текущий checkout и миграции
`0119..0131`, включая Branch/Room/Group lifecycle, optional linked accounts,
schedule/finance/messenger/task/reporting волны. Технический rollout PASS;
предметная owner-UAT для этих сценариев ещё не выполнена. Фразы ниже
«Production не изменялся» относятся к моменту снятия конкретного локального
evidence; теперь соответствующий код production-reachable в build `182`.

`UAT-003` получил единый machine-readable ID-ledger известных production
branch/ingestion/Lead/outbox/Lesson/Task фактов, privacy policy и явный список
не собранных классов. Он остаётся `PARTIAL` до заполнения ledger во время
owner-UAT; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-003.md`. Production не изменялся.

Локальный кандидат G3–G5 закрывает технические части UAT-035/036/047/050–052/
054: Manager branch scope доведён до student/group collection и membership
mutation, desktop ClientCard получил постоянный левый rail, а family card —
primary payer, app-user link, invite и typed entity navigation. Точечные
Flutter/Windows/PostgreSQL/Jest проверки PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-035-054.md`. Рабочая матрица теперь
`10 PASS / 90 PARTIAL / 0 PENDING`. После всех последующих изменений выполнен
полный gate текущего checkout: Flutter `786/786`, backend `175/175` suites и
`1401/1401` tests, analyze/typecheck/build/diff-check PASS.

`UAT-061–06A` и `UAT-131` локально переведены из `PENDING` в `PARTIAL`.
Закрыт обнаруженный разрыв UAT-06A: ручная корректировка/возврат личного счёта
теперь имеет append-only сторно через signed preview/commit,
expected-version/idempotency/audit/outbox и equal-opposite fact; migration
`0130` включена в migration dry-run. Дополнительно доказаны package archive /
restore, exact own/third-party/discount/installment purchase, replace/cancel,
payment technical/monetary reversal, Client finance projection, сохранение
формы при network error и single/shared refresh без re-login loop. Flutter
finance `28/28`, auth/retry `28/28`, PostgreSQL commerce `32/32`, route /
projection/migration contracts `110/110`, analyze/typecheck PASS. Evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-061-06A.md`. Production не
изменялся; полный gate остаётся отложен до закрытия технических Pending.

`UAT-140–UAT-144` имеют полные локальные ролевые tours. Новый
`integration_test/v7_role_personas_device_test.dart` проходит настоящий
ClientDashboard по chat/lessons/history/homework/subscription/payments/profile
и production workspaces Teacher/Admin/Manager/Director, одновременно проверяя
role-specific negative UI/API границы. Первый Teacher-прогон обнаружил
отсутствие compact navigation в `ProductionWorkspaceHost`; общий host исправлен
и покрыт регрессией. Client Android 15/API 35 `1/1`, общий Windows runner
`5/5`, workspace widget `12/12`, targeted analyze PASS; девять тёмных кадров и
точный остаток до production owner-UAT описаны в
`docs/audits/v7-owner-mega-uat-evidence/UAT-140-143.md`.

`UAT-013` локальный Android 15/API 35 gate PASS: реальные ADB Back `1/1`,
sheet/keyboard/SafeArea `1/1`, Teacher compact navigation `1/1`. Исправлены две
корневые ошибки: отсутствие mobile navigation у workspace-owned поверхностей и
assertion `DraggableScrollableController.animateTo(Duration.zero)` при
отключённых анимациях. Widget regressions `8/8 + 12/12`; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-013.md`.

`UAT-012` теперь имеет единый локальный Windows production-host tour `1/1`:
десять разных сущностей открываются через реальные linked labels, после чего
проходятся canonical breadcrumb, Back/Forward, возврат в исходную вкладку,
обычный restart с восстановлением всех десяти вкладок и global logout с
очисткой storage. Связанные controller/UI/persistence regressions `33/33`,
targeted analyze PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-012.md`. Production не изменялся.

`UAT-024` локально имеет полную Lead/Student mandatory matrix. Найден и закрыт
несимметричный Student-сценарий: после `422 SOURCE_INACTIVE` форма теперь
обновляет справочник, сбрасывает только архивированный source и сохраняет весь
draft. Required system/custom fields дают inline UI и exact structured
`422 {field,code,message}`; Flutter `7/7`, PostgreSQL `8/8`, controllers `5/5`,
analyze/typecheck PASS. Evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-024.md`. Production не изменялся.

`UAT-026` локально имеет полный Student UI/API/DB flow. Production-доска
применяет published `allowedTransitions`: запрещённый drop не отправляет
mutation, разрешённый PATCH после refetch меняет колонку и счётчики. Реальный
`CrmService.updateStudent` внутри PostgreSQL-теста повторно запрещает неверный
переход exact structured `422`, не меняет агрегаты, пишет ровно одну history
row для разрешённого перехода и сохраняет revision rollback. Flutter `17/17`,
PostgreSQL `6/6`, CRM `23/23`, analyze/typecheck PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-026.md`. Production не изменялся.

`UAT-031` локально имеет единый пользовательский room-management flow:
создание аудиторий `1/2/8`, edit/readback, preview занятой с недоступным commit
и archive только свободной с reason/version. Прямой hard delete остаётся
fail-closed; lifecycle сохраняет Lesson/series/plan history и append-only
journal. Flutter `4/4`, server lifecycle/service/migration `13/13`, analyze
PASS; evidence: `docs/audits/v7-owner-mega-uat-evidence/UAT-031.md`.
Production не изменялся.

`UAT-033` локально имеет полный актуальный Teacher flow. Карточка создаётся без
email/password и необязательных discipline/category/level; при наличии пары
реквизитов создаётся реально входящий linked app account. Director-card читает
тот же `app.users`, включая timestamps смены реквизитов. В Schedule settings
для всех трёх Teacher сохранены versioned branch assignments и recurring
availability; недоступность требует причину, Manager остаётся read-only.
Flutter `13/13`, backend auth/person/teacher/availability `46/46`,
analyze/typecheck PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-033.md`. Production не изменялся.

`UAT-034` локально имеет полную role-assignment negative matrix. Создание и
staff-card не меняют роль; единственный mutation UI находится в
`Настройки -> Доступы`. Manager не получает controls, Director видит только
lower roles и не может менять себя/root, system_admin требует emergency
surface; `409` делает refetch без partial state. Flutter `19/19`, backend
access/actor matrix `143/143`, analyze/typecheck PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-034.md`. Production не изменялся.

`UAT-041` локально имеет полный Lead-board filter/sort flow. Закрыт реальный
UI-разрыв: source/responsible/period/request type/goal/gender/preferred schedule
и `newest/oldest` раньше были недоступны либо отсутствовали в состоянии.
Desktop/mobile используют один фильтр; поиск не теряется, source и responsible
читаются канонически, oldest cursor меняет comparator вместе с SQL order.
Flutter `6/6`, backend `34/34`, analyze/typecheck PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-041.md`. Production не изменялся.

`UAT-045` локально имеет полный Lead trial create flow. Карточка открывает
месяц клиента в дефолтном филиале вместе с остальными занятиями; create dialog
сохраняет Lead/branch preset, требует teacher/room и теперь показывает точный
calculation snapshot до constraint preview и atomic commit. PostgreSQL
readback подтверждает `lesson + valid immutable snapshot + settlement plan`.
Flutter `27/27`, PostgreSQL `1/1`, analyze/typecheck PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-045.md`. Production не изменялся.

`UAT-145` локально переведён из `PENDING` в `PARTIAL`. PostgreSQL-сценарий
подтверждает Director-only versioned confirmation, идемпотентный archive,
завершение recurring plan/series/membership и сохранность one-time lesson,
task, subscription, payment, expected payment, adjustment и CRM links.
Flutter role/widget `4/4`, Windows device preview+commit `1/1`, targeted analyze
PASS; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-145.md`. Production не изменялся.
`UAT-146` локально переведён из `PENDING` в `PARTIAL`: подготовлен pre-final
DOCX со всеми 100 сценариями и отдельными полями owner-решения
`PASS/FAIL/BLOCKED`, инициалов и даты. Финальная owner-подпись отсутствует;
evidence: `docs/audits/v7-owner-mega-uat-evidence/UAT-146.md`. Технических
`PENDING` в матрице больше нет, но `90 PARTIAL` требуют production owner-UAT.

Финальный локальный UAT-134 gate сначала обнаружил четыре backend-регрессии:
ClientCard typed fields нарушили bounded read model (`4` запроса вместо `3`),
а две Lead fixtures отстали от typed-value/audit контракта. Typed value map
перенесён внутрь существующего composition SQL, fixtures синхронизированы;
точечный повтор `41/41`, полный повтор Flutter `770/770`, backend `174/174`
suites / `1397/1397`, analyze/typecheck/build PASS. Evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-134-final-local-gate.md`.
Текущий повтор после UAT-003/041/045 обнаружил ещё одну UI-регрессию:
канонический responsible `name` читался карточкой как старый `displayName`.
После исправления ClientCard `11/11`, полный Flutter `786/786`, backend
`175/175` suites / `1401/1401`, analyze/typecheck/build/diff-check PASS.

Teacher/Staff optional account, credential management и атомарный person
lifecycle локально реализованы миграциями `0122`/`0123`. Старый Profile role
endpoint удалён; повышение роли осталось только в `Настройки → Доступ`, а
каноническая access-команда синхронизирует Staff projection. Эти изменения ещё
не выпускались и не проходили owner-UAT.

Reference catalog lifecycle локально реализован миграцией `0124`: Discipline и
Lead loss reason получили rename/archive/restore, Branch discipline — явные
unassign/restore, usage impact, immutable history, version/idempotency,
audit/outbox и DB race/write guards. По последнему решению владельца usage
показывается как impact, но не блокирует архивирование информационных
Discipline/Branch discipline. UI доступен в
`Настройки → Организация → Справочники` и в карточке Branch. Миграция ещё не
выпускалась и не проходила owner-UAT.

Файлы домашних заданий локально доведены до сквозного UI-flow: Staff/Teacher
выбирают занятие и прикрепляют материал, Client видит файлы и может
прикрепить решение. Приватные File API/RBAC сохранены; при ошибке
привязки только что загруженный файл мягко удаляется, чтобы не оставлять
сирот. Для Lead и Teacher привязка ДЗ к занятию обязательна. Production owner-UAT ещё
не выполнялся.

Групповые постоянные расписания локально доведены до сквозного сценария из
карточки Group: участники выбираются с собственными активными абонементами,
preview/create используют канонический group Plan, а изменение состава создаёт
датированный versioned-срез без переписывания истории. Удаление ученика из
группы теперь fail-closed блокируется, пока ученик остаётся в активном или
будущем Plan; membership и schedule writes сериализуются общим group-lock.
Production owner-UAT ещё не выполнялся.

Canonical conflict matrix локально доведена и для изменения существующего
Plan. Новый update-preview использует тот же серверный constraint engine,
проверяет все строки и каждого участника до versioned update, исключает только
обычные будущие занятия заменяемых series и не скрывает перенесённые занятия.
Flutter сохраняет конфликтный черновик, показывает все 8 категорий, имя
конфликтующего ученика группы и открывает нужный набор строк для исправления;
при невалидном preview PATCH не отправляется. Production owner-UAT ещё не
выполнялся.

Завершение постоянного Plan локально доведено до полного lifecycle:
`reason → impact preview → confirmed idempotent commit → ended → readback`.
End и update сериализуются с horizon materializer общими per-series locks;
последняя дата ограничивает series, более поздние unsettled Lesson отменяются с
release резервов, terminal Lesson и tray сохраняются. Ended-карточка показывает
управляющей роли дату, автора и причину, не предлагает write-действия; Client
эти внутренние поля через API не получает. Исправлена коллизия PageStorage у
вложенной tray, которая падала при раскрытии завершённого Plan. Production
owner-UAT ещё не выполнялся.

Tray постоянного Plan локально доведена по `UAT-075`: backend использует
bounded keyset pagination по `(scheduled_at, lesson.id)`, возвращает
authoritative settlement/relation markers и fail-closed отклоняет неверный
cursor/direction. UI показывает дату и время, teacher/period/room, листает в
обе стороны, сохраняет текущую страницу при ошибке и повторяет именно
неуспешный cursor; ended archive по умолчанию свёрнут. Production owner-UAT ещё
не выполнялся.

Календарь карточки клиента локально доведён по `UAT-076`: фильтр «Скрывать
чужие занятия» включён по умолчанию и раскрывает branch matrix локально, без
client-scoped refetch. Month отмечает дни, Week, Day по аудиториям и Day по
преподавателям показывают отдельные target/other markers, не меняя красный,
зелёный и синий lesson state. Исправлен пропущенный marker teacher timeline и
подпись Month `Август 2026`; Back сохраняет выбранный режим. Client не может
читать staff matrix по backend policy. Тёмный Windows device `1/1` PASS;
production Month/Week/оба Day evidence ещё нужны.

Отдельный маршрут `Карточка клиента → Открыть в расписании` локально приведён
к решению владельца: открывается основной Branch из карточки, фильтр «Скрывать
чужие занятия» сразу выключен, target-занятия остаются зелёными, а остальные —
серыми. Кнопка создания в этом контексте передаёт в каноническую форму уже
выбранных клиента и Branch; Room по-прежнему выбирает сотрудник. Исправлена
гонка начальной загрузки, при которой schedule успевал запросить прежний Branch
до применения route context. Production owner-UAT ещё не выполнялся.

`UAT-113` локально переведён из `PENDING` в `PARTIAL`. Только
Director/system_admin может изменять и удалять из рабочего расчёта строки
истории ставок и выплат: удаление реализовано как audited void, поэтому строка
сохраняется в БД, но исключается из текущих проекций. Команды требуют reason,
expected version и idempotency metadata, записывают audit/outbox. Директорская
массовая ставка теперь включает уже рассчитанные занятия и создаёт новый
superseding compensation fact вместо переписывания старого; Admin/Manager
остаются ограничены незакрытыми расчётами. Миграции `0127`/`0128`, PostgreSQL
`4/4`, Windows device `2/2`, Flutter `737/737`, backend `172/172` suites и
`1374/1374` tests, access `344/344`, actor matrix `9/9`, analyze/typecheck/build
PASS. CSV подтверждён каноническим server projection/export: Windows device
перехватывает Export без запуска LibreOffice и сверяет BOM, кириллицу, имя и
period filters; widget/report `16/16`. Production rollout и owner-UAT не
выполнялись.

G2 `UAT-020–029` локально доведена до технического кандидата. Категории,
16 typed-типов, stable options, ширины и размещения `create/edit/card/table`
работают через одну canonical definition/value модель в формах создания,
существующей карточке и досках Lead/Student. Архивные значения сохраняются;
`default_lesson_duration_minutes` применяется в новой форме занятия. Восемь
строк переведены `PENDING → PARTIAL`. Runtime-разрыв
`payment_reminder_days` закрыт локально migration `0131`: effective school/
Branch-окно создаёт durable reminder только активным Client app-аккаунтам
плательщика, concurrent tick/retry использует стабильный notification ID.
PostgreSQL `2/2`, совместный commerce repeat `19/19`, typecheck PASS. Остаются
production owner UAT и новый полный gate текущего post-`0131` checkout.

`UAT-114` локально переведён из `PENDING` в `PARTIAL`. Director/system_admin
может создать, изменить и после явного подтверждения soft-delete удалить расход
из канонического финансового журнала; текущий Branch подставляется в create, а
каждая mutation завершается API-readback. В прокручиваемой панели доступны все
`50` загруженных строк, а не только три последние. PostgreSQL-сценарий сверил
`1250→1750→delete` с list/Analytics, сохранив удалённую строку, audit и realtime;
Manager получил deny для list/create/update/delete и не отправил скрытый expense
request. Widget `6/6`, PostgreSQL `3/3`, тёмный Windows device `1/1`; полный
gate Flutter `742/742`, backend `172/172` suites и `1376/1376` tests,
analyze/typecheck/build PASS. RepoWise risk `2.77`; его неизвестное покрытие
перекрыто targeted и полными gate. Production не изменялся, owner UI/API/DB-
повтор остаётся обязательным.

`UAT-115` локально переведён из `PENDING` в `PARTIAL`. Phone-review
получил два явных исхода с обязательной причиной: каноническое RU-
исправление атомарно обновляет source/queue под row lock, а
accept-as-is оставляет source неизменным; audit не содержит raw phone.
Deletion lifecycle теперь точно совпадает в UI/API: Client отменяет
только pending, Admin/Director/system_admin ведёт state machine, Manager
read-only. Completion анонимизирует точный target и отзывает его
доступ, сохраняя legal/business history; PostgreSQL sentinel доказал,
что соседний owner не изменился. Windows device покрыл три сценария
за прогоны `2+1`; полный gate Flutter `747/747`, backend `174/174`
suites и `1387/1387` tests, analyze/build PASS. Production и `magic1` не
изменялись. RepoWise PR risk `2.48`, breaking/conformance/cycles `0`;
его формальные coverage gaps перекрыты targeted и полными gate. Нужен
owner UI/API/DB-повтор на disposable UAT-client.

`UAT-116` локально переведён из `PENDING` в `PARTIAL`. Основные экраны
больше не подменяют сетевой сбой пустым результатом и не показывают raw
exception: Client занятия/абонемент/оплаты/ДЗ, Messenger chats/messages,
Profile, legal gate, Director overview, teacher report и System Settings
получили постоянное безопасное error-состояние с повтором канонического
запроса. Capability load error отделён от настоящего forbidden; списки
Branch/Group/Package/Staff/Teacher используют общий `MagicPageState`.
Widget recovery matrix `9/9`, полный Flutter `756/756`, analyze PASS;
дополнительно исправлен обнаруженный тестом 1px KPI overflow. Production не
изменялся; нужен owner UI-проход loading/empty/error/forbidden/retry по ролям.

`UAT-120`/`UAT-121`/`UAT-122` локально переведены из `PENDING` в
`PARTIAL`. Director-экран и оба экспорта используют один period/Branch
filter и корректно перезагружаются после смены Branch. Manager не
видит finance KPI/export/journal, не отправляет скрытый school-finance
запрос, а backend fail-closed отклоняет его. XLSX/CSV сверены по
фильтрам, колонкам, строкам, кириллице и finance-суммам; Flutter до
сохранения проверяет format signature/BOM и различает «открыт»/
«сохранён». Widget `12/12`, analytics PostgreSQL/OOXML `7/7`, тёмный
Windows device `1/1`; полный gate: Flutter `739/739`, backend `172/172` suites и
`1375/1375` tests, analyze/typecheck/build PASS. Production не изменялся; owner
UI/API/DB-повтор остаётся обязательным.

`UAT-123` локально имеет полный search proof: canonical Schedule посимвольно
разрешает Lead/Student через actor-scoped client refs, Teacher/Room через exact
matrix filters и Lesson по дате; введённый текст, focus, view/date и vertical
scroll не сбрасываются. `client_schedule_calendar_test.dart` проходит `7/7`;
production owner UI/API-повтор всех пяти сущностей остаётся обязательным.

`UAT-130` локально сведён в единый double-submit gate: Lead conversion,
ActualPayment, Subscription purchase, Shared Task close и Lesson transition
дают один business result либо stable replay, а changed fingerprint
отклоняется. PostgreSQL `4/4` suites и `35/35`, Flutter UI `54/54`; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-130.md`. Production не изменялся.

`UAT-133` current candidate actor gate PASS: private routes/scopes `344/344`,
unexplained allows `0`, actor/payload leak `9/9`, capability policy/evaluator/
guard `132/132`. Unknown capability и resource mismatch fail-closed; evidence:
`docs/audits/v7-owner-mega-uat-evidence/UAT-133.md`. Остался production owner
negative-request trace.

`UAT-070` локально переведён из `PENDING` в `PARTIAL`: предпочтительное
расписание проходит typed save и обязательный read-after-write, а фактическое
занятие видно как при пустых предпочтениях/Plan, так и после сохранения новой
series. Widget `28/28`, backend schedule/controller `60/60`, тёмный Windows
device `1/1`; два локальных evidence-кадра сохранены. Production UI/API/DB-
подтверждение ещё не выполнялось.

`UAT-071` локально переведён из `PENDING` в `PARTIAL`: один индивидуальный Plan
атомарно создаёт три series, где два дня используют общих преподавателя и
аудиторию, а отдельная строка — других. Flutter выполняет обязательный
read-after-write и показывает все три строки; реальная PostgreSQL integration
подтверждает idempotency и отсутствие дублей при повторной materialization.
Тёмный Windows device-сценарий и два UI-кадра PASS; production evidence
остаётся обязательным.

`UAT-080` локально переведён из `PENDING` в `PARTIAL`: форма создания требует
три независимых финансовых решения — settlement type, teacher pay rule и
funding source. Widget закрыл явный выбор и пустой каталог, тёмный Windows
device — реальную форму/commit с двумя UI-кадрами, PostgreSQL integration —
пять fail-closed невалидных команд без частичных записей и атомарное сохранение
Lesson/snapshot/plan/revision. Production UI/API/DB evidence остаётся
обязательным.

`UAT-081` локально переведён из `PENDING` в `PARTIAL`: все пять teacher-pay
mode доказаны одной calculation/UI/PostgreSQL матрицей. Windows показывает
полный каталог, блокирует override без причины и отображает preview почасовой
суммы; backend после reject не оставляет частичных facts, а после валидного
override сохраняет default/actual/reason и pinned revision. Production
UI/API/DB evidence остаётся обязательным.

`UAT-082` локально переведён из `PENDING` в `PARTIAL`: форма автоматически
выбирает конкретный активный абонемент, позволяет явный personal account и для
бесплатного settlement переключается на `none` с очисткой `subscriptionId`.
Закрыт найденный дефект: платный или штрафной settlement больше не может пройти
с `none` и тихо создать нулевой факт — общий calculation/plan path возвращает
`CLIENT_FUNDING_SOURCE_REQUIRED`, а transaction не оставляет Lesson/Plan.
Widget, calculation, PostgreSQL и два тёмных Windows evidence-кадра PASS;
production UI/API/DB evidence остаётся обязательным.

`UAT-083` локально переведён из `PENDING` в `PARTIAL`: trial остаётся
независимым frozen marker и не означает бесплатность. UI и Windows подтверждают
пробное платное занятие, widget дополнительно покрывает trial free. Completion
PostgreSQL matrix провела все четыре trial/non-trial × paid/free комбинации:
платные создают `80000 minor` либо `1.00` subscription unit, бесплатные — строго
`0/0.00` без reservation и изменения активного абонемента; teacher pay остаётся
отдельным fact. Production UI/API/DB evidence остаётся обязательным.

`UAT-084` локально переведён из `PENDING` в `PARTIAL`: новый PostgreSQL-сценарий
не вызывает `runOnce` напрямую, а запускает production lifecycle worker и
реально ждёт будущий scheduled end. До due нет work/facts; после timer tick
frozen subscription plan применён один раз, work завершён с `attempts=1`,
client/teacher facts и transition единичны, reservation `consumed`, plan
`settled`; следующий tick не создаёт дублей. Production worker/UI/API/DB
evidence остаётся обязательным.

`UAT-085` локально переведён из `PENDING` в `PARTIAL`: poison worker после
bounded retry оставляет Lesson в `settlement_pending`, plan в
`review_required` и не создаёт финансовых facts. Staff matrix теперь проецирует
актуальную version и role-gated failure code; карточка показывает `Конфликт`,
безопасную русскую причину и `Исправить расчёт`, не раскрывая raw exception.
Прямой settle обычного `scheduled` Lesson заблокирован; recovery требует
`review_required`, а успешный commit ставит plan `settled` и очищает failure.
Тёмный Windows device и сквозной schedule→preview с `expectedVersion=2` PASS;
production worker/UI/API/DB evidence остаётся обязательным.

`UAT-086` локально переведён из `PENDING` в `PARTIAL`: перенос завершённого
Lesson идёт через общий signed preview/idempotent commit, но UI теперь сам
фиксирует обязательный reversal `free_lesson/none`, объясняет сохранение истории
и не заставляет выбирать параметры, которые backend всё равно заменяет.
PostgreSQL fault после вставки replacement facts откатывает correction,
successor и все записи. Успешный commit оставляет старые client/teacher facts и
consumed reservation неизменными, исключает их из effective projection через
superseding zero facts и создаёт successor с исходным `paid_miss` plan и новым
reservation. Обычный completion worker завершает successor ровно один раз;
повторный tick не создаёт эффект. Тёмный Windows evidence PASS; production
UI/API/DB evidence остаётся обязательным.

`UAT-087` локально переведён из `PENDING` в `PARTIAL`: устранён разрыв, при
котором backend принимал `clientDecisions`, но рабочий Flutter UI не мог их
задать. Schedule matrix теперь проецирует имена только active frozen participants;
форма показывает common settlement и sparse override для каждого ученика,
отправляет signed preview/commit и подписывает факты именами. Реальный PostgreSQL
одной транзакцией применил персональный `lesson` к участнику по абонементу
(`settled 0→1`, `reserved 1→0`, reservation `reserved→consumed`) и общий
`partially_paid_lesson` к участнику с личным счётом, оставив по одному effective
client fact на двух участников и один teacher fact. Восемь повторов не создали
дублей; label/color/units/amount/config revision сохранены. Тёмный Windows device
`5/5`; production UI/API/DB evidence остаётся обязательным.

`UAT-090` локально переведён из `PENDING` в `PARTIAL`: реальный staff-путь из
quick view открывает не демонстрационный decision sheet, а полную форму и меняет
дату без drag-and-drop. Найденные разрывы закрыты: Group переносится без
фиктивного client selector с сохранением frozen participants, no-op больше не
создаёт successor, а ошибка видна внутри full-screen формы; schedule после commit
дожидается `_fetchAll`. Reason, settlement и teacher pay проходят общий signed
preview/idempotent commit. Widget `35/35`, PostgreSQL reschedule `5/5`, тёмный
Windows device `1/1` и два UI-кадра PASS; production UI/API/DB evidence остаётся
обязательным.

`UAT-091` локально переведён из `PENDING` в `PARTIAL`: форма подмены теперь
показывает только active преподавателей, назначенных в выбранный Branch, и его
active Room, отдельно объясняя, что занятость проверяет следующий signed
preview. Preview локализует teacher/room overlap и branch mismatch, а каталог
финансового решения загружается для successor Branch. Реальный PostgreSQL
заблокировал занятую пару без token, затем атомарно сохранил свободные
`teacher_id`/`room_id` и одну transition при replay. Targeted widget `25/25`,
PostgreSQL reschedule `6/6`, тёмный Windows device `1/1` и два UI-кадра PASS;
production UI/API/DB evidence остаётся обязательным.

`UAT-092` локально переведён из `PENDING` в `PARTIAL`: one-time create,
reschedule, Plan preview/create/update и horizon materializer используют общий
constraint engine. Закрыты отдельный teacher/room-only worker bypass,
branch-timezone отбор/материализация, несовпадающие client lock keys, SQL NULL
self-exclusion standalone Lesson и Group overlap после изменения текущего
состава — blocker теперь читается из immutable snapshot participants. Dashboard,
Week и Day открывают одну полную форму, drag-and-drop отсутствует, а room
availability остаётся read-only и честно показывает whole-day occupancy как
`Без занятий/С занятиями`. Targeted backend `7/7` suites и `88/88`, Flutter
`40/40`, тёмный Windows device `1/1` со всеми 8 русскими причинами и commit=`0`;
production owner UI/API/DB evidence остаётся обязательным.

`UAT-093` локально переведён из `PENDING` в `PARTIAL`: два независимых
Manager-аккаунта с разными actor/idempotency/request identity одновременно
создали один slot. Transaction-scoped Branch/Client/Room/Teacher locks и
повторная authoritative validation дали ровно одного winner и один structured
`422` с teacher/client/room overlap. В БД осталось ровно по одному Lesson,
snapshot, settlement plan/revision, aggregate version, audit, outbox и
idempotency record. Проигравшая Windows-форма показала понятный conflict без
force-bypass и сохранила весь draft. Targeted backend `5/5`, widget `19/19`,
Windows device `1/1`, полный Flutter `719/719`, backend `168/168` suites и
`1319/1319` tests, analyze/typecheck/build PASS; production owner UI/API/DB
evidence остаётся обязательным.

`UAT-094` локально переведён из `PENDING` в `PARTIAL`: для всех пяти типов,
разрешённых branch catalog в контексте cancel, PostgreSQL table test проверяет
preview и persisted hours/balance/reservation, независимую teacher pay,
labels/colors/configuration revisions, reason history и cardinality
transition/facts/audit/outbox/idempotency. Два settle-only типа получают `422`
без side effects. Общий Flutter `LessonDecisionFlow` больше не повторяет
устаревший commit бесконечно: `STALE_LESSON_VERSION` принимает `currentVersion`
во внутреннее состояние, сохраняет ввод, сбрасывает preview/identity и
возвращает понятное действие `Рассчитать`; входная Map не мутируется. Targeted
backend/Flutter `7/7` и `7/7`, тёмный Windows device `1/1` с тремя кадрами,
полный Flutter `720/720`, backend `168/168` suites и `1320/1320` tests,
analyze/typecheck/build PASS; production owner UI/API/DB evidence остаётся
обязательным.

`UAT-095` локально переведён из `PENDING` в `PARTIAL`: Month/Week/оба Day и
календарь карточки клиента открывают Lesson через общий quick view и
`CreateLessonDialog`. Исправлен найденный тупик paged/Group tray: bounded item,
которого нет в fallback, теперь гидратирует полную Lesson точным actor-scoped
`lessonId`-чтением существующего endpoint и открывает тот же editor; terminal
state разрешён только exact-ID запросу. Windows device сохранил после Back
Day, дату, client-filter и точный vertical scroll; widget сохранил horizontal
tray scroll. Protected reason/signed-preview/confirm/version/idempotency path
не обходится. Targeted widget `13/13`, backend schedule `58/58`, Windows
device `1/1`, полный Flutter `721/721`, backend `168/168` suites и `1321/1321`
tests, analyze/typecheck/build PASS; production owner UI/API/DB evidence
остаётся обязательным.

Дополнительный Windows consumer обнаружил регрессию UAT-060: API-статус
`posted_pending` отображался не утверждённой подписью. Все UI-точки сведены к
одному `clientPaymentStatusLabel`, каноническое название восстановлено как
`Проведён, ожидает подтверждения`; client-workspace device прошёл `4/4`.

Локальная проверка checkout после Staff/Teacher, reference-catalog и последних
schedule/settlement-инвариантов: Flutter `721/721`, backend `168/168` suites и
`1321/1321` tests, backend typecheck/build PASS, полный Flutter analyze PASS.
Windows lesson-settlement device-consumer `5/5`, recurring-plan/preference consumer
`4/4`, client-calendar device `1/1`. Capability
coverage `344/344` private routes, shadow unexplained differences `0`.
RepoWise-указанный Windows configuration integration consumer также прошёл
`3/3` после reference-catalog волны.

## Быстрый старт

1. Прочитать `AGENTS.md` и проверить `git status --short --branch`.
2. Использовать RepoWise для ответа на конкретный вопрос по коду. При
   low-confidence/mock результате подтвердить ответ живым исходником.
3. Если задача касается приёмки, открыть:
   - `docs/audits/v7-owner-production-mega-uat-result.md`;
   - `docs/audits/v7-owner-mega-uat-evidence/README.md`.
4. Если задача касается найденных пробелов продукта, открыть
   `docs/audits/2026-08-11-repowise-application-audit.md`.

Не нужно читать глобальный backlog, проходить фазовый workflow или создавать
служебный отчёт до начала обычной правки.

## Честный production-статус

| Проверка | Результат |
|---|---:|
| Release Flutter | 786/786, analyze PASS |
| Release Backend | 175/175 suites, 1401/1401 tests |
| Backend typecheck/build | PASS |
| Exact image runtime/security gate | PASS, Trivy 0 High/Critical/secret |
| Windows ZIP + Setup install/launch/uninstall | PASS |
| Android APK/AAB signature + API 35 install/launch | PASS |
| Public manifests/artifacts build `182` | PASS |
| UAT PASS | 11 |
| UAT PARTIAL | 89 |
| UAT PENDING | 0 |

`PARTIAL` не равен `PASS`. Приложение нельзя объявлять окончательно принятым,
пока обязательные строки не имеют итоговый статус и требуемые UI/API/DB
доказательства.

Механическая сверка plan/result на 2026-08-12 показывает одинаковый набор из
`100` уникальных UAT-ID.

Production rollout build `182` прошёл encrypted off-host backup, isolated
restore, миграции `0119..0131`, worker pause/resume, reconciliation и automatic
rollback gate. Windows ZIP/Setup и Android APK/AAB опубликованы; оба update-
манифеста переключены на `1.5.2+182`. Server image `sha256:698db9b4…` healthy,
worker/outbox/reconcile drift `0`.

Evidence:

- `docs/audits/v7-production-rollout-182.md`;
- `docs/audits/v7-production-rollout-181.md`;
- `docs/audits/v7-production-rollout-server-hotfix-b04f177.md`;
- `docs/audits/v7-teacher-compensation-181.md`.

## Главный незавершённый продуктовый блок

Организационный lifecycle-контур уже production-reachable, но ещё требует
owner-UAT:

| Сущность | Сейчас | Не хватает |
|---|---|---|
| Branch | list/create/update + preview/archive/history/restore | owner-UAT; future-dated closing пока не поддержан |
| Room | list/create/update + preview/archive/history/restore и DB write guards | owner-UAT; future-dated archive пока не поддержан |
| Group | list/create/update/members + preview/archive/history/restore и DB race guards | owner-UAT; future-dated archive пока не поддержан |
| Teacher | create без обязательного login, credential management, preview/offboard/history/restore | owner-UAT |
| Staff | safe-admin create без обязательного login, credential management, preview/offboard/history/restore | owner-UAT |
| Branch discipline | add/reorder + preview/non-blocking impact/unassign/history/restore | owner-UAT |
| Discipline/loss reason | list/create + rename/archive/history/restore; usage impact не блокирует Discipline | owner-UAT |

Физический cascade delete филиала недопустим: схема смешивает `CASCADE`,
`SET NULL` и restrict/default references, а финансовая, учебная и audit-история
должна оставаться неизменяемой. В production `1.5.2` используется canonical
`preview → remediation/blockers → commit(reason, effectiveDate)` с атомарным
`active → archived`, восстановлением и tombstone-записью Branch. Отдельное
состояние `closing` не вводилось без write guards и scheduler: будущая дата
fail-closed отклоняется, чтобы «закрывающийся» филиал не продолжал принимать
новые операции. Тот же контракт применён к Room и Group. Для Group
архивирование блокируют будущие занятия, активные серии и постоянные планы;
состав группы, завершённые занятия и финансовые факты сохраняются. Новые
schedule/membership writes по архивной группе блокируются на уровне БД.

Последние owner-инварианты расписания production-reachable: дисциплины,
категории и уровни необязательны и не ограничивают занятия; Teacher выбирается
только в назначенном Branch, его availability и рабочие часы Branch блокируют;
Branch и Room обязательны. Новый Branch требует рабочие часы при создании.
При выборе клиента Lesson подставляет его `branch_id`, а Room оператор выбирает
отдельно. Технический release gate PASS; остаётся production owner-UAT.

Последняя локальная G10-волна перевела `UAT-101` из `PENDING` в `PARTIAL` и
расширила `UAT-105`: hidden/share-with-teacher комментарии доказаны для Staff,
Teacher и Client на PostgreSQL и тёмном Windows device. Найден и исправлен
реальный async `setState` дефект успешного refresh. Operational history теперь
связывает существующие audit-факты conversion, comments и linked shared tasks с
карточкой клиента, показывает безопасную причину/автора/время и не возвращает
private body. Полный локальный gate: Flutter `721/721`, backend `168/168`
suites и `1321/1321` tests, analyze/typecheck/build PASS. Production не
изменялся.

Следующая локальная волна закрыла инженерный контур `UAT-102` и task-reminder
часть `UAT-112`: all-day/interval формы имеют явное редактируемое время
напоминания и UI-блокировку некорректного интервала; person/branch/school
preview доказан против фактических PostgreSQL recipients. Worker теперь
маршрутизирует уведомление в точную Task и идемпотентно переживает частичный
сбой нескольких получателей без дублей notification/email/push. Read-state
сохраняется после пересоздания клиента. Тёмный Windows device прошёл `3/3`,
полный локальный gate: Flutter `724/724`, backend `168/168` suites и
`1324/1324` tests, analyze/typecheck/build PASS. Production не изменялся;
`UAT-102` остаётся `PARTIAL` до owner evidence.

Следующая локальная волна закрыла оставшийся инженерный контур `UAT-112`:
создание/перенос/отмена Lesson теперь дают durable, маршрутизируемое и
идемпотентное уведомление. При переносе Client и новый Teacher открывают
successor, снятый Teacher — source; групповые получатели берутся из frozen
snapshot, deleted/non-app identities исключаются. Технический state-only outbox
refresh не создаёт второе уведомление. PostgreSQL retry/cardinality/read-state,
Flutter widget и тёмный Windows device `4/4` PASS; полный локальный gate:
Flutter `725/725`, backend `168/168` suites и `1330/1330` tests,
analyze/typecheck/build PASS. Production не изменялся; `UAT-112` остаётся
`PARTIAL` только до production owner Task/Lesson UI/API/DB evidence.

Следующая локальная волна закрыла инженерный контур `UAT-110`. Voice duration
теперь сохраняется в PostgreSQL и переживает reload; message type проверяется
против File purpose/MIME и владельца upload; неуспешный commit откатывает новый
upload. Reply ограничен текущим чатом, forward хранит message ID и требует
доступ к source chat. Миграция `0125` добавила file FK и исправила soft-delete
media tombstone. В direct-чате pin доступен обоим участникам без расширения
Group/Administration management. PostgreSQL lifecycle/negative matrix,
Flutter widget/service и тёмный Windows device `1/1` PASS; полный gate:
Flutter `729/729`, backend `170/170` suites и `1342/1342` tests,
analyze/typecheck/build PASS. RepoWise risk `2.44`, breaking/conformance/cycles
`0`. Production не изменялся; `UAT-110` остаётся `PARTIAL` до owner UI/API/DB
evidence Client↔Admin и Teacher↔Manager.

Следующая локальная волна закрыла инженерный контур `UAT-111`. Channel теперь
имеет полный role/user ACL editor, разделённые write/manage capabilities и
authoritative `canWrite` для composer; omission permissions сохраняет ACL.
Миграция `0126` нормализует и защищает exact-target, write→read и uniqueness.
Channel create/update/remove синхронизируется realtime по старым и новым
получателям. Group получил create/add/remove/leave lifecycle, защиту от
самоудаления через manage action и корректные app-роли участников. Support
assign/unassign/archive/unarchive доказан на реальном PostgreSQL. PostgreSQL
`3/3`, targeted backend `79/79`, Flutter `70/70`, тёмный Windows device `2/2`
PASS; полный gate: Flutter `735/735`, backend `171/171` suites и `1352/1352`
tests, analyze/build PASS. RepoWise risk `3.64`, breaking/conformance/cycles
`0`; его неразрешённые coverage gaps закрыты фактическими widget/realtime/
Windows/PostgreSQL тестами. Production не изменялся; `UAT-111` остаётся
`PARTIAL` до owner UI/API/DB evidence.

## Следующая работа

1. Выполнить production owner-UAT Branch/Room/Group lifecycle, уже доступного
   через миграции `0119`/`0120`/`0121`.
2. Выполнить production owner-UAT reference lifecycle из migration `0124`.
3. Пройти production owner-UAT `UAT-104` для файлов ДЗ с UI/API/DB-доказательствами.
4. Пройти production owner-UAT `UAT-072` для группового Plan и изменения его
   participant subscriptions с UI/API/DB-доказательствами.
5. Пройти production owner-UAT `UAT-073` для полной conflict matrix и
   редактирования конфликтного Plan с UI/API/DB-доказательствами.
6. Пройти production owner-UAT `UAT-074` для завершения Plan с UI/API/DB-
   доказательствами и проверкой отсутствия новых occurrence после последней даты.
7. Пройти production owner-UAT `UAT-075` для cursor tray и authoritative
   markers с UI/API/DB-доказательствами.
8. Пройти production owner-UAT `UAT-070` для save/readback предпочтений и
   независимой видимости фактических Lesson с UI/API/DB-доказательствами.
9. Пройти production owner-UAT `UAT-071` для многодневного индивидуального
   Plan с общими и разными teacher/room строками и UI/API/DB-доказательствами.
10. Пройти production owner-UAT `UAT-076` для Month/Week/Day client-target
   markers, default-hide и маршрута из карточки с UI/API-доказательствами.
11. Пройти production owner-UAT `UAT-080` для трёх обязательных независимых
   финансовых выборов с UI/API/DB-доказательствами.
12. Пройти production owner-UAT `UAT-081` для пяти teacher-pay mode и ручного
   override с обязательной причиной и UI/API/DB-доказательствами.
13. Пройти production owner-UAT `UAT-087` для common group settlement,
   per-client override и cardinality client/teacher facts с UI/API/DB-
   доказательствами.
14. Пройти production owner-UAT `UAT-090` для переноса индивидуального и
   группового Lesson через форму с UI/API/DB-доказательствами и readback.
15. Пройти production owner-UAT `UAT-091` для подмены преподавателя и аудитории
   с UI/API/DB-доказательствами ограниченного selector, conflict preview и
   persisted successor.
16. Пройти production owner-UAT `UAT-092` по всем one-time/recurring conflict
   entry points с UI/API/DB-доказательствами и нулём частичных записей.
17. Пройти production owner-UAT `UAT-093` с двумя реальными Manager-сеансами,
   UI/API/DB evidence и нулём частичных loser-фактов.
18. Пройти production owner-UAT `UAT-095` из Month/Week/Day, client card и
    paged/ended tray с UI/API/DB-доказательствами и сохранением контекста Back.
19. Пройти production owner-UAT `UAT-101` для hidden/share-with-teacher
    комментариев и `UAT-105` для общей operational history с UI/API/DB-
    доказательствами пяти ролей.
20. Пройти production owner-UAT `UAT-102` для all-day/interval/audience/reminder
    и `UAT-112` для Task/Lesson notifications с UI/API/DB-доказательствами.
21. Пройти production owner-UAT `UAT-110` для Client↔Admin и Teacher↔Manager:
    text/image/file/voice, edit/delete/reaction/pin/read с UI/API/DB-
    доказательствами и повторным открытием voice.
22. Пройти production owner-UAT `UAT-111` для Group create/add/remove/leave,
    Channel role/user ACL и support assign/unassign/archive/unarchive с
    UI/API/DB-доказательствами.
23. Пройти production owner-UAT `UAT-113` для изменения/audited void истории,
    массовой settled-коррекции, CSV и reconciliation текущих проекций.
24. Пройти production owner-UAT `UAT-114`: expense create/edit/soft-delete по
    всей истории, Branch readback, Analytics parity и отсутствие Manager traffic.
25. Пройти production owner-UAT `UAT-115`: phone-review с обоими
    исходами и deletion lifecycle на disposable UAT-client, не затрагивая
    `magic1`, с UI/API/DB evidence и проверкой сохранённой истории.
26. Пройти production owner-UAT `UAT-120`–`UAT-122`: общий period/Branch
    filter, Manager без school-finance traffic и сверка XLSX/CSV с API/DB.
27. Добавить новые owner-UAT строки для lifecycle и optional person accounts,
    затем продолжить оставшиеся
    `PENDING/PARTIAL` сценарии.
28. Перед следующим release проверить, что `origin/main` воспроизводит
    production-reachable код.

## Стоп-условия

Остановить mutation/release при финансовом drift, утечке прав, дубле эффекта,
необъяснённом 5xx или невозможности восстановить backup. Не исправлять такие
состояния ручной очисткой production-истории.
