# V7 owner mega-UAT — актуальные доказательства

Дата прогона: `2026-08-08` — `2026-08-12`
Клиент: production API и update channels `1.5.2+182`; Windows/Android Release
`+182` готовы к актуальному owner UI-retest
Среда данных: production API/DB

Production API развёрнут на client-compatible exact server revision `52b272087`
и client build `1.5.2+182`. Исторические UI-кадры
предыдущих кандидатов сохраняют доказанную предметную операцию, но не повышают
изменённые UI-сценарии до PASS без актуального owner-повтора.

## Production rollout `1.5.2+182`

Полный release gate, encrypted off-host backup, isolated restore,
`0119..0131`, exact production image, rollback gate, Windows ZIP/Setup,
подписанные Android APK/AAB, public update manifests и post-deploy health
зафиксированы в
[`v7-production-rollout-182.md`](../v7-production-rollout-182.md).
Технический `UAT-134` теперь PASS; актуальные credential-based five-role и
предметные UI/API/DB-проходы остаются owner-UAT.

## Предыдущий production rollout `1.5.1+181`

Teacher compensation refinement, полные regression-gates, Windows/Android
smoke, exact server image runtime/Trivy и release hashes зафиксированы в
[`v7-teacher-compensation-181.md`](../v7-teacher-compensation-181.md). Backup,
isolated restore, серверный cutover, five-role/API/reconciliation checks и
публикация клиентов зафиксированы в
[`v7-production-rollout-181.md`](../v7-production-rollout-181.md). Это повышает
только прямо доказанные технические строки; предметные UI-сценарии требуют
отдельного owner-повтора.

Актуальный server hotfix, новый backup/restore, контролируемый rollback первой
попытки, teacher-options API smoke и task performance smoke зафиксированы в
[`v7-production-rollout-server-hotfix-b04f177.md`](../v7-production-rollout-server-hotfix-b04f177.md).

Локальный технический gate и hashes:
[`../v7-production-readiness-180.md`](../v7-production-readiness-180.md).

Предыдущий production rollout `+180`, backup/restore и runtime evidence:
[`../v7-production-rollout-180.md`](../v7-production-rollout-180.md).

Рабочая матрица всех `100` уникальных утверждённых сценариев
(`10 PASS`, `90 PARTIAL`, `0 PENDING`):

## G0 — локальный кандидат UAT-003

Единый журнал известных production-ID, version/counts, business outcomes и
evidence-ссылок создан в
[`api/uat-id-ledger-20260812.json`](api/uat-id-ledger-20260812.json); правила и
точный остаток описаны в [`UAT-003.md`](UAT-003.md). Секреты, телефоны и email
не сохраняются, суммы и результаты не маскируются. Строка остаётся `PARTIAL`,
пока owner-UAT не заполнит все перечисленные `missingRequiredClasses`.

## G1 — локальный кандидат UAT-012

Десять разных связанных сущностей, canonical breadcrumbs, Back/Forward,
сохранность исходной вкладки, restart и logout зафиксированы в
[`UAT-012.md`](UAT-012.md). Windows production-host device `1/1`, связанные
widget-регрессии `33/33`; production не изменялся.

## G1 — локальный кандидат UAT-013

Android system Back, dirty-form order, expandable sheet, keyboard/SafeArea и
Teacher compact navigation зафиксированы в [`UAT-013.md`](UAT-013.md).
Android 15/API 35: `1/1 + 1/1 + 1/1`; исправлены mobile workspace navigation и
reduced-motion sheet crash. Production не изменялся.
[`../v7-owner-production-mega-uat-result.md`](../v7-owner-production-mega-uat-result.md).

Старый набор `00..25` удалён: он содержал устаревший отдельный экран
аудиторий, прежнюю форму преподавателя и один кадр, снятый не из приложения.
Ни один из этих кадров не используется как доказательство.

## G2 — локальный кандидат UAT-020–029

Категории, 16 типов typed-полей, варианты, ширины и все четыре размещения,
эффективные настройки school/branch, configuration lifecycle и RBAC
зафиксированы в [`UAT-020-029.md`](UAT-020-029.md). Отдельно закрыт runtime-
разрыв `payment_reminder_days`: migration `0131`, payer audience, durable
dedup/retry и PostgreSQL `2/2`. Production не изменялся; все десять строк G2
остаются `PARTIAL` до owner UI/API/DB-прохода.

Обязательные системные и настраиваемые поля Lead/Student, inline UI и точный
structured `422` отдельно сведены в [`UAT-024.md`](UAT-024.md). Исправлен
Student refresh конкурентно архивированного источника без потери draft;
Flutter `7/7`, PostgreSQL `8/8`, controllers `5/5`.

Настраиваемые переходы Student доведены до полного локального UI/API/DB proof
в [`UAT-026.md`](UAT-026.md): доска отклоняет запрещённый drop, разрешённый
PATCH меняет колонку и счётчики после refetch, backend возвращает structured
`422`, не оставляет частичного состояния и пишет ровно одну history row.
Flutter `17/17`, PostgreSQL `6/6`, общий CRM `23/23`.

## G3–G5 — локальный кандидат UAT-035–054

Realtime access invalidation, Manager branch scope, Group create/membership,
конкурентная Lead→Student конверсия, постоянный desktop rail, compact card,
staff/shared comments и family/app-user/invite flow зафиксированы в
[`UAT-035-054.md`](UAT-035-054.md). Семь строк переведены из `PENDING` в
`PARTIAL`; production не изменялся.

## G6/G13 — локальный кандидат UAT-061–06A и UAT-131

Финансовые формы, каталог, own/third-party purchase, рассрочка,
replace/cancel/reversal, новое append-only сторно корректировки и безопасный
network/401 Retry зафиксированы в
[`UAT-061-06A.md`](UAT-061-06A.md). Одиннадцать строк переведены из `PENDING`
в `PARTIAL`; production не изменялся.

## G13 — локальный кандидат UAT-130

Double-submit/replay для Lead conversion, ActualPayment, Subscription purchase,
Shared Task close и Lesson transition сведены в
[`UAT-130.md`](UAT-130.md). PostgreSQL `4/4` suites и `35/35`, Flutter
double-click/stable Retry `54/54`; production не изменялся.

## G13 — локальный кандидат UAT-133

Полный private-route inventory, actor matrix, payload-leak, capability policy,
effective evaluator и authorization guard зафиксированы в
[`UAT-133.md`](UAT-133.md): private/scopes `344/344`, unexplained allows `0`,
actor `9/9`, policy/evaluator/guard `132/132`. Production не изменялся.

## G14 — локальный кандидат UAT-140–UAT-144

Полные Client/Teacher mobile и Admin/Manager/Director Windows functional tours,
negative UI/API границы и девять тёмных evidence-кадров зафиксированы в
[`UAT-140-143.md`](UAT-140-143.md). Android 15/API 35 Client `1/1`, общий
Windows device `5/5`, compact workspace widget `12/12`. Найденная тестом
отсутствующая мобильная навигация Teacher исправлена в общей workspace-оболочке.
Все пять строк остаются `PARTIAL` только до production owner evidence;
production не изменялся.

## G14 — локальный кандидат UAT-145

Director archive preview/commit, versioned confirmation, role boundary,
завершение recurring work и сохранность one-time/finance/task/history
зафиксированы в [`UAT-145.md`](UAT-145.md). PostgreSQL `1/1`, Flutter widget
`4/4`, Windows device `1/1`; строка переведена из `PENDING` в `PARTIAL`,
production не изменялся.

## G14 — pre-final UAT-146

Воспроизводимый DOCX со всеми `100` сценариями, текущими техническими
статусами и полями для owner-решения/инициалов/даты зафиксирован в
[`UAT-146.md`](UAT-146.md). Технических `PENDING` больше нет; строка остаётся
`PARTIAL`, пока production owner-UAT не завершён и финальный документ не
подписан.

## Финальный локальный gate UAT-134

После достижения `0 PENDING` полный gate текущего checkout дополнительно
обнаружил реальную несовместимость канонического поля ответственного `name` с
устаревшим чтением `displayName` в ClientCard. После исправления карточка
`11/11`, Flutter `786/786`, backend `175/175` suites и `1401/1401` tests,
analyze/typecheck/build/diff-check PASS. Предыдущий bounded-read regression и
его `41/41` proof также сохранены. Подробности:
[`UAT-134-final-local-gate.md`](UAT-134-final-local-gate.md). На момент этого
локального gate production не менялся; теперь кандидат развёрнут как `+182`.

## G0/G13 — rollout `1.5.2+182`

| Проверка | Результат | Доказательство |
|---|---|---|
| Exact image, source/client revisions, migration ledger и release hashes | PASS | `../v7-production-rollout-182.md` |
| Новый encrypted backup, off-host SHA и isolated restore | PASS | `../v7-production-rollout-182.md` |
| Restore → candidate migrations `0119..0131` → reconcile zero | PASS | `../v7-production-rollout-182.md` |
| Windows portable/Setup и Android APK/AAB build `182` | PASS | `../v7-production-rollout-182.md` |
| Worker/outbox, two reconciliations, restart/log/5xx/latency | PASS | `../v7-production-rollout-182.md` |
| Оба update-манифеста и четыре public client artifacts build `182` | PASS | `../v7-production-rollout-182.md` |
| Credential-based five-role login/profile на новом build | PARTIAL | предыдущий `5/5` остаётся historical `+181`; нужен актуальный owner-проход |

## G3 — филиал, аудитории и преподаватель

| Проверка | Результат | Доказательство |
|---|---|---|
| Филиал `UAT-20260808-01 Оборонная`, адрес `Оборонная 30` | PASS | `windows-release/01-branch-list.png` |
| Дисциплина выбирается из существующего справочника внутри филиала | PASS | `windows-release/02-branch-discipline-picker.png` |
| В филиале видны `Вокал` и аудитории A/B/C вместимостью `1/2/8` | PASS | `windows-release/03-branch-disciplines-and-rooms.png` |
| Часы филиала вынесены в отдельное окно без выбора преподавателя | PASS | `windows-release/13-branch-hours-separate-164.png` |
| Пн–Сб `09:00–21:00`, воскресенье закрыто; исключения настраиваются здесь же | PASS | `windows-release/17-branch-hours-sunday-closed-164.png` |
| Назначения по филиалам вынесены в отдельное окно графика преподавателя | PASS | `windows-release/14-teacher-schedule-separate-164.png` |
| Доступность первого преподавателя сохранена для пн/ср/пт `09:00–21:00` | PASS | `windows-release/15-teacher-recurring-rules-164.png`, `windows-release/19-teacher-availability-saved-164.png` |
| Недоступность нельзя добавить без причины; причина сразу видна сотрудникам | PASS | `windows-release/16-teacher-unavailability-reason-required-164.png`, `windows-release/18-teacher-unavailability-reason-visible-164.png` |
| Имя, филиал и ставка обязательны; email/пароль задаются только парой и необязательны, дисциплины/категории/уровни не блокируют карточку | PASS | локальный актуальный form/person-account proof: [`UAT-033.md`](UAT-033.md); старый кадр `windows-release/06-teacher-required-fields-ready.png` описывает устаревший контракт и не используется как доказательство |
| Создан преподаватель `UAT-20260808-01 Teacher`, специализация `Вокал` | PASS | `windows-release/07-teacher-created.png` |
| Та же операция атомарно создала пользователя с ролью `Преподаватель` | PASS | `windows-release/08-teacher-linked-user.png` |
| Новый аккаунт вошёл в Android и видит профиль с ролью `Преподаватель` | PASS | `android-release/01-teacher-profile.png` |
| Раздел `Ученики` открывается и показывает честное пустое состояние | PASS | `android-release/02-teacher-students-access.png` |
| Android Release `+164` установлен поверх данных и после холодного запуска сохранил сессию преподавателя | PASS | `android-release/03-teacher-session-preserved-164.png` |
| Android Release `+166` повторно установлен поверх данных; teacher-сессия и навигация `Чат / Расписание / Ученики` сохранены | PASS | `android-release/05-teacher-session-preserved-166.png` |

Полный локальный room-management flow отдельно зафиксирован в
[`UAT-031.md`](UAT-031.md): создание `1/2/8`, edit/readback, защита занятой и
архивация только свободной аудитории с сохранением истории. Flutter `4/4`,
server lifecycle/service/migration `13/13`, analyze PASS; production не
изменялся.

Три Teacher, optional linked account, ставки/метаданные, филиальные назначения
и versioned working-hours mutations сведены в [`UAT-033.md`](UAT-033.md).
Flutter `13/13`, backend auth/person/teacher/availability `46/46`,
analyze/typecheck PASS; production не изменялся.

Единственный role-mutation путь и полная Manager/Director/system_admin negative
matrix сведены в [`UAT-034.md`](UAT-034.md). Роль read-only в staff-card,
Manager не получает controls, Director не видит root и не меняет себя, root
работает только через emergency surface. Flutter `19/19`, backend access/actor
matrix `143/143`, analyze/typecheck PASS; production не изменялся.

## G11 — локальный кандидат UAT-113

Управление историей ставок/выплат и директорская массовая коррекция settled
занятий зафиксированы отдельно в [`UAT-113.md`](UAT-113.md). Локальные тёмные
Windows-кадры: `teacher-payroll-history.png` и
`teacher-statistics-integrity.png`. Windows `2/2` теперь также проверяет
канонический CSV Export, BOM/кириллицу/фильтры через перехватываемый file opener
без запуска внешнего приложения; widget/report `16/16`. Эти доказательства не
заменяют production owner UI/API/DB/CSV-повтор.

## G11b — локальный кандидат UAT-114

Director expense CRUD по всей загруженной истории, soft-delete, Manager deny и сверка с Analytics
зафиксированы в [`UAT-114.md`](UAT-114.md). Локальные тёмные
Windows-кадры: `director-expense-edited-readback.png`,
`director-expense-delete-confirmation.png`, `director-expense-deleted-readback.png`
и `manager-without-expense-journal.png`. Production не изменялся.

## G11c — локальный кандидат UAT-115

Phone-review resolution, deletion request state machine, анонимизация
точного target и клиентские profile/auth/legal/notification маршруты
зафиксированы в [`UAT-115.md`](UAT-115.md). Тёмные Windows-кадры:
`data-quality-phone-review-open.png`, `data-quality-phone-review-decision.png`,
`data-quality-phone-review-resolved.png`, `deletion-request-pending-director.png`,
`deletion-request-completion-confirmation.png`,
`deletion-request-completed-director.png`, `uat-client-profile.png`,
`uat-client-auth-methods.png`, `uat-client-legal-documents.png`,
`uat-notification-preferences.png`, `uat-client-deletion-pending.png` и
`uat-client-deletion-cancel-confirmation.png`. Production и реальный
`magic1` не изменялись.

## G11d — локальный кандидат UAT-116

Loading/empty/error/forbidden/retry состояния основных рабочих поверхностей,
безопасные сообщения и восстановление тем же запросом зафиксированы в
[`UAT-116.md`](UAT-116.md). Автоматическая widget-матрица охватывает Client
занятия/абонемент/оплаты, Director overview, capability error/forbidden,
профиль, legal gate, список чатов и сообщения. Production не изменялся;
owner UI-проход всех ролей остаётся обязательным.

## G12 — локальный кандидат UAT-120–123

Общие period/Branch фильтры, Manager scope без school finance и
XLSX/CSV parity, а также посимвольный Lead/Student/Teacher/Room/Lesson search с
сохранением focus/text/scroll зафиксированы в
[`UAT-120-122.md`](UAT-120-122.md).
Локальные тёмные Windows-кадры:
`director-dashboard-xlsx-export.png`, `director-dashboard-csv-export.png` и
`manager-dashboard-without-school-finance.png`. Production не изменялся;
owner UI/API/DB-повтор остаётся обязательным.

## G4 — лид и переходы по карточке

Полный локальный Lead-board filter contract зафиксирован в
[`UAT-041.md`](UAT-041.md): источник, ответственный, период, тип обращения,
цель, пол, предпочтительное расписание и `newest/oldest` больше не являются
недоступными backend-параметрами. Все secondary facets комбинируются с
постоянным посимвольным поиском и per-column keyset pagination. Flutter `6/6`,
backend `34/34`, analyze/typecheck PASS; production owner-повтор обязателен.

Полный локальный Lead trial flow зафиксирован в [`UAT-045.md`](UAT-045.md).
Карточка открывает месяц клиента в его дефолтном филиале, не скрывая остальные
занятия; единый create dialog сохраняет Lead/branch preset, требует teacher и
room и до commit показывает точный immutable calculation snapshot. Flutter
`27/27`, PostgreSQL create/readback `1/1`, analyze/typecheck PASS; production
owner-повтор обязателен.

| Проверка | Результат | Доказательство |
|---|---|---|
| Новый лид заполнен реальными обязательными значениями: филиал `UAT-20260808-01 Оборонная`, источник `Звонок` | PASS | `windows-release/20-lead-required-fields-ready-165.png` |
| Источник выбирается в компактном списке: одновременно пять записей и видимая полоса прокрутки | PASS | `windows-release/21-lead-source-compact-scroll-165.png` |
| Лид `Lead UAT-20260809-01` сохранён; поиск `U` → `UA` → `UAT` не теряет фокус и не перезапускает страницу | PASS | `windows-release/22-lead-search-persisted-165.png` |
| Нажатие по имени открывает канонический маршрут `Клиенты → Лид · UAT-20260809-01 Lead`; поля и телефон повторно загружены с production API | PASS | `windows-release/23-lead-card-route-165.png` |
| Список статусов раскрывается локально под полем, показывает пять вариантов и собственную полосу прокрутки | PASS | `windows-release/24-lead-status-menu-compact-166.png` |
| Переход `Звонок после пробного` → `Успешный` выбран и сохранён из канонической карточки | PASS | `windows-release/25-lead-successful-selected-166.png` |
| После возврата доска не использует старый family-кэш: тот же production-лид сразу найден в колонке `Успешный` | PASS | `windows-release/26-lead-status-refreshed-166.png` |
| Основные системные поля повторно прочитаны: реальный филиал, источник `Звонок`, ответственный `Администратор Тестов` | PASS | `windows-release/27-lead-system-fields-166.png` |
| Причина обязательного модерационного действия вводится до подтверждения и видна в активном состоянии | PASS | `windows-release/28-blacklist-reason-dialog-166.png`, `windows-release/29-blacklisted-state-166.png` |
| Чёрный список снят из UI; карточка вернулась в обычное состояние | PASS | `windows-release/30-blacklist-removed-166.png` |
| После снятия ограничения история сохраняет точную причину, автора и время; пустая причина не показывает `[PRIVATE]` | PASS | `windows-release/31-operational-history-167.png` |
| В карточке видна полная реальная цепочка статусов `В процессе` → `Пробный Урок` → `Звонок после пробного` → `Успешный` | PASS | `windows-release/32-status-history-167.png` |
| Кандидат на объединение показывает обе записи раздельно: дату, источник, статус, филиал и короткий ID | PASS | `windows-release/33-merge-candidate-compared-169.png` |
| До явного выбора сохраняемой записи объединение заблокировано; исходный лид выбран осознанно | PASS | `windows-release/34-merge-winner-required-169.png` |
| После объединения штатная отмена остаётся в постоянном окне, а не только в исчезающем уведомлении | PASS | `windows-release/35-merge-result-persistent-169.png` |
| Отмена выполнена через UI; кандидат и обе записи восстановлены | PASS | `windows-release/36-merge-undone-169.png`, `windows-release/37-merge-candidate-restored-169.png` |

## G4b — подписанная внешняя заявка

| Проверка | Результат | Доказательство |
|---|---|---|
| Подписанный production-webhook создал ровно одного лида `Внешняя Заявка UAT-044`, телефон `+79990009003`, источник `Звонок` | PASS | `windows-release/38-external-lead-board-170.png` |
| Повтор с тем же ingestion UUID вернул тот же `leadId` с `replayed=true`; в БД остались 1 Lead и 1 outbox-событие | PASS | production DB reconciliation, `ingestionId=a33f706f-26b2-48a1-8123-202608090044` |
| Outbox-событие опубликовано с первой попытки без dead-letter и создало одно постоянное уведомление; 17 получателей и 17 уникальных push-доставок, дублей нет | PASS | `windows-release/39-webhook-notification-170.png` + production DB reconciliation |
| Нажатие по тексту уведомления открывает новую именованную вкладку, сохраняет вкладку `Клиенты` и показывает маршрут `Клиенты → Лид · Заявка UAT-044 Внешняя` | PASS | `windows-release/40-notification-linked-route-170.png` |

## G4c — чат только для клиента с аккаунтом

| Проверка | Результат | Доказательство |
|---|---|---|
| У лидов `Внешняя Заявка UAT-044` и `Lead UAT-20260809-01` без привязанного аккаунта кнопки чата нет | PASS | `windows-release/41-leads-without-app-user-no-chat-171.png` |
| У связанного с `magic1@gmail.com` ученика `Ученик Тестов` есть единственная кнопка `Написать в чат` | PASS | `windows-release/42-linked-student-chat-action-171.png` |
| Клик открывает отдельную вкладку `Чат`, сохраняет вкладку `Клиенты` и сразу выбирает реальный диалог `Ученик Тестов` | PASS | `windows-release/43-linked-student-chat-opened-171.png` |

## G4d — единое расписание и клиентский контекст

| Проверка | Результат | Доказательство |
|---|---|---|
| В production workspace существует одна каноническая вкладка `Расписание`; отдельного раздела или вкладки `Отчёт` для занятий нет | PASS | `windows-release/44-one-canonical-schedule-unfiltered-175.png` |
| Реальное пробное занятие лида видно 12 августа в обычном расписании филиала `UAT-20260808-01 Оборонная` | PASS | `windows-release/44-one-canonical-schedule-unfiltered-175.png` |
| Исторический `+175` переиспользовал ту же вкладку, но включал `Скрывать чужие занятия`; этот кадр не подтверждает актуальное решение владельца. Текущий локальный маршрут оставляет остальные занятия видимыми и использует независимый маркер связи | PARTIAL | старый контекст: `windows-release/45-client-filtered-canonical-schedule-175.png`; актуальный automated proof: [`UAT-045.md`](UAT-045.md); нужен новый owner-кадр |
| Сохранённые legacy-вкладки с датой как ID нормализуются и схлопываются без потери активной даты и клиентского фильтра | PASS | automated restore regression, Flutter `664/664` |

## G4e — задачи только для операционных сотрудников

| Проверка | Результат | Доказательство |
|---|---|---|
| «Вся школа» включает только `2` администраторов, `14` управляющих и `1` директора; преподаватели, клиенты и системный администратор не получают задачи | PASS | `windows-release/56-school-task-staff-only-179.png` + production DB reconciliation |
| Индивидуальный список реально загружается отдельными role-filtered запросами и содержит только Администраторов/Управляющих/Директора | PASS | `windows-release/57-task-recipient-picker-staff-only-179.png` |
| Директор назначил `UAT-046 Check lead` ровно одному получателю — `Администратор Тестов` | PASS | `windows-release/48-direct-admin-task-ready-178.png`, `windows-release/49-direct-admin-task-preview-178.png`, `windows-release/50-director-created-admin-task-178.png` |
| У администратора доска открылась с фильтрами `Мои задачи` + `Сегодня`; задача на весь день сегодня не считается просроченной | PASS | `windows-release/52-admin-mine-today-not-overdue-179.png` |
| Администратор закрыл задачу; открытых стало `0`, а запись появилась в `Закрытые` | PASS | `windows-release/53-admin-task-closed-open-zero-179.png`, `windows-release/54-admin-closed-task-visible-179.png` |
| История показывает создание и изменение директором и одно закрытие администратором с датой и временем | PASS | `windows-release/55-task-history-director-admin-179.png` + production DB reconciliation |

## Локальный UAT-070 — предпочтительное расписание

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| При пустых предпочтениях и отсутствии Plan фактическое занятие остаётся в карточке | PASS | `test/features/v7/recurring_schedule_plan_section_test.dart`; `preferred-schedule-empty-actual-lesson.png` |
| Сохранение предпочтения отправляет typed client/branch/teacher/room и конечный период | PASS | `test/features/v6/client_workspace_route_test.dart`; четыре branch-scoped POST для двух дней × двух последовательных слотов |
| После commit карточка повторяет GET и показывает сохранённые строки, не скрывая фактическое занятие | PASS | `preferred-schedule-saved-with-actual-lesson.png`; тёмный Windows device `1/1` |
| Flutter widget и backend schedule-контракты | PASS | widget `28/28`; `schedule.service` + `crm-schedule.controller` `60/60` |

## Локальный UAT-071 — индивидуальный Plan на несколько дней

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Один набор строки разворачивается в два дня с общими преподавателем и аудиторией, отдельная строка использует другого преподавателя и аудиторию | PASS | `individual-plan-mixed-row-review.png`; `test/features/v7/recurring_schedule_plan_section_test.dart` |
| После одной create-команды карточка повторяет GET и показывает три сохранённые series с правильными именами преподавателей и аудиториями | PASS | `individual-plan-mixed-row-readback.png`; тёмный Windows device `1/1`, весь `v7_recurring_plans_device_test.dart` `4/4` |
| PostgreSQL сохраняет Plan и три series атомарно и идемпотентно; повторная materialization не создаёт дубли Lesson | PASS | `server/src/crm/schedule/schedule-plan-postgres.integration.spec.ts`; targeted integration `1/1` |
| Полный регресс после добавления доказательства | PASS | Flutter `703/703`; backend `168/168` suites, `1305/1305` tests; Flutter analyze и backend build PASS |

## Локальный UAT-080 — обязательные settlement/pay/funding choices

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Форма создания показывает три обязательных независимых выбора и отправляет выбранные stable keys/source | PASS | `lesson-create-required-financial-choices.png`; `test/features/v4/lesson_form_test.dart`; тёмный Windows device `1/1` |
| После commit форма закрывается, показывает «Занятие создано», а payload содержит `settlementTypeKey=lesson`, `teacherCompensationRuleKey=standard`, `clientChargeType=personal_account` без `subscriptionId` | PASS | `lesson-create-financial-committed.png`; `integration_test/v7_lesson_settlement_device_test.dart` |
| Пустой каталог и неполные/несогласованные settlement, pay rule, funding source или subscription не создают частичных Lesson/Plan | PASS | `test/features/v4/lesson_form_test.dart`; `server/src/crm/schedule/lesson-write-parity.integration.spec.ts` |
| Валидная команда атомарно сохраняет Lesson snapshot, settlement plan и одну revision; для личного счёта reservation не создаётся | PASS | реальная PostgreSQL integration `5/5`; snapshot `personal_account/1500.00`, plan `lesson/none`, revisions `1`, reservations `0` |
| Полный регресс после добавления доказательства | PASS | Flutter `705/705`; backend `168/168` suites, `1306/1306` tests; Flutter analyze, backend typecheck/build PASS; Windows settlement device `2/2` |

## Локальный UAT-081 — все пять правил оплаты преподавателю

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Одна staff-форма показывает `Не оплачивать`, `Полная стандартная ставка`, `Процент ставки`, `Фиксированная сумма` и `Почасовая сумма` | PASS | `teacher-pay-five-rule-catalog.png`; `test/features/v7/lesson_decision_flow_test.dart`; тёмный Windows device `1/1` |
| Значение редактируется только для percent/fixed/hourly; почасовая сумма форматируется в рублях и попадает в preview как minor units | PASS | `teacher-pay-hourly-override-preview.png`; payload `hourly/125000`, preview `1 250,00 ₽` |
| Изменённый override без причины не отправляет preview и не создаёт частичные DB facts | PASS | `teacher-pay-override-reason-required.png`; UI `Укажите причину`; PostgreSQL после reject: client facts `0`, teacher facts `0` |
| Валидный override сохраняет отдельно configured default, actual value и reason; none/standard override запрещён | PASS | `lesson-settlement.calculation.spec.ts`; `lesson-settlement-postgres.integration.spec.ts` |
| Реальная PostgreSQL settlement сохраняет effective teacher fact для всех пяти правил | PASS | `none=0`; `standard=75001`; `percent=43750`; `fixed override=95000`; `hourly=120000`; targeted integration и весь файл `6/6` |
| Полный регресс после добавления доказательства | PASS | Flutter `706/706`; backend `168/168` suites, `1308/1308` tests; Flutter analyze, backend typecheck/build PASS; Windows settlement device `3/3` |

## Локальный UAT-082 — абонемент, личный счёт и допустимое «Без списания»

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| При активном абонементе форма по умолчанию показывает его остаток и отправляет `clientChargeType=subscription` вместе с конкретным `subscriptionId` | PASS | `lesson-funding-subscription-default.png`; `test/features/v4/lesson_form_test.dart`; PostgreSQL reservation path в `lesson-write-parity.integration.spec.ts` |
| Оператор может отдельно выбрать личный счёт; `subscriptionId` и reservation при этом отсутствуют | PASS | `lesson-create-required-financial-choices.png`; payload `personal_account`; PostgreSQL snapshot `personal_account/1500.00`, reservations `0` |
| Бесплатный settlement автоматически переключает источник в `none`, очищает абонемент и создаёт payload без `subscriptionId` | PASS | `lesson-funding-free-no-charge.png`; payload `free_lesson/none/0`; тёмный Windows device `1/1` |
| Платный или штрафной settlement с `none` не создаёт Lesson/Plan и не может позже породить ложный нулевой fact | PASS | `CLIENT_FUNDING_SOURCE_REQUIRED`; calculation `7/7`; PostgreSQL lesson-write parity `5/5`, после reject Lesson `0`, Plan `0` |
| Платные transition-preview используют реальный personal-account source, а бесплатные сохраняют `none` | PASS | `server/src/crm/schedule/reschedule-postgres.integration.spec.ts` `4/4`; paid miss `1.00`/`100000`, free lesson `0.00`/`0` |
| Полный регресс после добавления доказательства | PASS | Flutter `707/707`; backend `168/168` suites, `1309/1309` tests; Flutter analyze, backend typecheck/build PASS; Windows settlement device `4/4` |

## Локальный UAT-083 — пробное и бесплатное занятия

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Trial marker включается отдельно и не меняет settlement, pay rule или funding source | PASS | `lesson-trial-paid-personal-account.png`; payload `isTrial=true`, `settlementTypeKey=lesson`, `clientChargeType=personal_account`; тёмный Windows device `1/1` |
| UI допускает все четыре комбинации trial/non-trial × paid/free и не выводит бесплатность из trial автоматически | PASS | `test/features/v4/lesson_form_test.dart` `14/14`; отдельные payload assertions для trial paid subscription и trial free `none` |
| Trial paid с личного счёта создаёт реальный client fact, а marker одинаково заморожен в Lesson и snapshot | PASS | completion PostgreSQL: `is_trial=true`, `snapshot.trial=true`, amount `80000`, units `1.00` |
| Non-trial paid с абонемента списывает ровно `1.00` и terminalize переводит reservation в `consumed` | PASS | completion PostgreSQL: charge type `subscription`, units `1.00`, settled subscription units `1.00`, reservation `consumed` |
| Trial free и non-trial free дают `amount=0`, `units=0.00`, не создают reservation и не меняют активный абонемент | PASS | `free_lesson/none`; completion PostgreSQL matrix `4/4`, `lessons_used=0.00`, settled subscription units `0` |
| Оплата преподавателю остаётся независимой даже у бесплатного занятия | PASS | во всех четырёх completion-сценариях teacher fact `90000`, при free client fact остаётся `0/0.00` |
| Полный регресс после добавления доказательства | PASS | Flutter `709/709`; backend `168/168` suites, `1313/1313` tests; Flutter analyze, backend typecheck/build PASS; Windows settlement device `4/4` |

## Локальный UAT-084 — реальное ожидание completion worker

Это техническое доказательство текущего checkout, а не production owner-UAT.
Сценарий намеренно использует lifecycle-таймер worker через `onModuleInit`, а не
прямой вызов `runOnce`; для чисто серверного assert UI-скриншот не требуется.

| Проверка | Результат | Доказательство |
|---|---|---|
| До scheduled end занятие не является due и не имеет work, transition или финансовых фактов | PASS | PostgreSQL fixture с end через `2.5s`; initial metrics `due=0`, все evidence counts `0` |
| Production polling реально дожидается времени и применяет frozen plan | PASS | `LESSON_COMPLETION_WORKER_POLL_MS=1000`; первый completion не раньше `1.5s`; log `claimed=1 completed=1` |
| Один commit создаёт ровно один transition, client fact, teacher fact, audit, outbox и idempotency record | PASS | work `completed`, `attempts=1`, terminal `successfully_completed`; counts `1/1/1/1/1/1`, fact IDs совпадают с work |
| Subscription reservation terminalize и frozen plan завершены атомарно | PASS | client fact `subscription/1.00`, reservation `consumed`, plan `settled`, одна plan revision, teacher fact `90000` |
| Следующий реальный timer tick не повторяет эффект | PASS | после дополнительного `1250ms` polling counts полностью неизменны |
| Полный регресс после добавления доказательства | PASS | completion PostgreSQL `11/11`; schedule `9/9` suites, `38/38` tests; backend `168/168` suites, `1314/1314` tests; Flutter `709/709`; Flutter analyze, backend typecheck/build PASS |

## Локальный UAT-085 — безопасный конфликт и исправление расчёта

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Bounded poison retry оставляет ошибку видимой и переводит расчёт в review | PASS | completion PostgreSQL: work `poison/attempts=2`, Lesson `settlement_pending`, plan `review_required`, `failure_code=ConflictException`; финансовых facts `0` |
| Staff получает актуальную версию и только безопасный failure identifier, Client/Teacher не получают внутреннюю причину | PASS | `ScheduleService` matrix/list projection; role-gated SQL; `schedule.service.spec.ts`; mapper readback `version=2` и `settlement_failure_code` |
| Карточка показывает `Конфликт`, безопасную русскую причину и действие `Исправить расчёт`, не раскрывая `ConflictException` | PASS | `lesson-settlement-review-required.png`; `representative_modal_set_test.dart`; сквозной `schedule_redesign_test.dart` |
| Preview реального schedule-flow использует текущую версию и не предлагает штатное ручное проведение | PASS | Flutter schedule test: `expectedVersion=2`, `lesson/standard`; `Провести занятие` и `Завершить занятие` отсутствуют |
| Прямой API settle обычного scheduled Lesson заблокирован; recovery возможен только для `settlement_pending + review_required` | PASS | PostgreSQL transition: `409 LESSON_SETTLEMENT_REVIEW_NOT_REQUIRED`; успешный repair переводит plan в `settled`, очищает failure code и создаёт факты один раз |
| Ошибка recovery откатывает Lesson, plan и facts целиком | PASS | insufficient-capacity PostgreSQL: Lesson остаётся `settlement_pending/version=2`, plan `review_required`, facts `0` |
| Полный регресс после исправления | PASS | backend targeted `71/71`, полный `168/168` suites и `1315/1315` tests; Flutter targeted `68/68`, полный `710/710`; Flutter analyze, backend typecheck/build, diff-check PASS; Windows device `1/1` |

## Локальный UAT-086 — post-completion reversal и successor

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Завершённое занятие использует canonical preview/commit и не требует от оператора фиктивного финансового выбора | PASS | `lesson_decision_flow_test.dart`: completed state автоматически фиксирует `free_lesson/none`, скрывает оба dropdown и отправляет signed preview/idempotent commit |
| UI заранее объясняет append-only reversal и не раскрывает технический warning | PASS | `lesson-completed-reschedule-reversal-preview.png`; тёмный Windows `v6_modal_device_test.dart` показывает source/successor, причину, нулевой reversal и отдельный будущий расчёт без `COMPLETED_LESSON_EFFECTS_WILL_BE_REVERSED` |
| Ошибка после записи replacement facts откатывает весь post-completion transition | PASS | PostgreSQL fault: source остаётся `successfully_completed/version=3`, successors/corrections `0/0`, исходные client/teacher facts `1/1`, effective subscription units `1.00` |
| Успешный commit сохраняет историю и отменяет только effective-эффект | PASS | исходные client/teacher facts остаются; новые correction facts ссылаются через `supersedes_fact_id` и дают `0.00/0`; старый consumed reservation неизменяем и ссылается на уже неэффективный fact |
| Successor получает исходный план и отдельный reservation | PASS | successor `scheduled/version=1`, plan `paid_miss/planned`, новый reservation `reserved`; effective subscription units после reversal `0.00` |
| Обычный completion worker повторно завершает successor ровно один раз | PASS | первый `runOnce`: `claimed=1/completed=1`, work `completed/attempts=1`, plan `settled`, reservation `consumed`, facts/transition `1/1/1`; второй tick `claimed=0/completed=0`, итоговые effective units `1.00` |
| Полный регресс после исправления | PASS | backend `168/168` suites и `1315/1315` tests; Flutter `711/711`; Flutter analyze, backend typecheck/build, diff-check PASS; targeted decision/edit `18/18`, PostgreSQL `4/4`, Windows device `1/1` |

## Локальный UAT-087 — общий групповой расчёт и per-client override

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Рабочая schedule-проекция отдаёт форме только активных frozen participants группы с именами | PASS | `ScheduleService.getScheduleMatrix` собирает `groupParticipants` из immutable `lesson_snapshot_participants`, исключает `lesson_participant_exclusions`; `schedule.service.spec.ts`; Flutter legacy mapper readback |
| Сотрудник выбирает один общий settlement и может оставить `Как у всей группы` либо задать override конкретному ученику | PASS | `group-settlement-common-client-override.png`; тёмный Windows `v7_lesson_settlement_device_test.dart`; compact dropdown policy PASS |
| Preview/commit отправляют только явное исключение и показывают рассчитанные факты с именами | PASS | payload: общий `partially_paid_lesson`, один `clientDecisions[{Анна, lesson}]`, один teacher-pay rule; `group-settlement-named-facts-preview.png`; widget test |
| Источник и резерв каждого участника обрабатываются сервером | PASS | реальный PostgreSQL в одной транзакции: персональный `lesson` для участника по отдельному абонементу даёт `1.00 / 0 minor`, effective units `0→1`, reserved units `1→0`, reservation `reserved→consumed`; общий `partially_paid_lesson` для второго участника использует личный счёт и даёт `0.50 / 40000` |
| Число effective client facts равно числу участников, teacher fact ровно один | PASS | реальный PostgreSQL: `2/2` client facts и `1` teacher fact; оба client facts и teacher fact сохраняют label/color/config revision, teacher amount `60000` |
| Конкурентный повтор не создаёт дубликаты | PASS | 8 параллельных повторов вернули тот же результат; в effective projection осталось `client=2`, `teacher=1`, consumed reservation ровно один |
| Полный регресс после исправления | PASS | Flutter `712/712`; backend `168/168` suites и `1315/1315` tests; Flutter analyze, backend typecheck/build PASS; targeted Flutter `61/61`, PostgreSQL group settlement `6/6`; Windows device `5/5` |

## Локальный UAT-090 — перенос через реальную форму без drag-and-drop

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Доступный staff-путь открывает настоящую форму и действительно меняет дату | PASS | quick view вызывает `CreateLessonDialog`; `lesson-reschedule-real-form.png` показывает исходные ресурсы и новую дату `08.08.2026` вместо `07.08.2026` |
| Причина, списание и оплата преподавателю обязательны до commit | PASS | `lesson-reschedule-real-form-preview.png`: причина, `Бесплатное занятие`, `Не оплачивать`, старое/новое время и рассчитанные нулевые факты видны до кнопки `Перенести` |
| Preview и commit используют один optimistic/idempotent контракт | PASS | Windows payload: `expectedVersion=4`, successor `2026-08-08T09:00:00.000Z`, `free_lesson/none`; commit повторяет successor и financial decision preview; device `1/1` |
| Фиктивный перенос без изменений запрещён внутри видимой формы | PASS | `lesson_form_test.dart`: inline-ошибка перечисляет дату, время, длительность, филиал, аудиторию и преподавателя; preview/commit не вызываются |
| Групповое занятие переносится тем же контрактом без фиктивного клиента | PASS | widget показывает неизменяемую Group вместо пустого client selector; PostgreSQL successor сохраняет `group_id` и один frozen participant, создаёт ровно один transition/client fact/teacher fact и стабильно replay-ит idempotency key |
| После успешного commit вызывающий календарь дожидается authoritative readback | PASS | schedule `_editLesson` ожидает `_fetchAll`; клиентская tray ожидает собственный refresh; Flutter targeted `35/35` |
| Полный регресс после исправления | PASS | Flutter `714/714`, analyze PASS; backend `168/168` suites и `1316/1316` tests, typecheck/build PASS; PostgreSQL reschedule `5/5`; Windows device `1/1` |

## Локальный UAT-091 — подмена преподавателя и аудитории

Это техническое доказательство текущего checkout, а не production owner-UAT.

| Проверка | Результат | Доказательство |
|---|---|---|
| Селекторы содержат только статически допустимые ресурсы выбранного филиала | PASS | `lesson-replacement-options.png`: выбраны `Мария Сменова` и `Зал 2`; widget исключает inactive/foreign teacher и foreign room, а подпись объясняет отдельную проверку занятости |
| Динамическая занятость проверяется единым signed preview и объясняется по-русски | PASS | widget блокирует `TEACHER_OVERLAP` и `ROOM_OVERLAP` без commit; `lesson-replacement-preview.png` показывает обязательную причину, финансовое решение и состояние «готово к подтверждению» для свободной пары |
| При смене Branch каталог решения соответствует successor, а mismatch не маскируется кодом | PASS | controller test проверяет `branchId` successor; UI локализует `TEACHER_BRANCH_MISMATCH`, `ROOM_BRANCH_MISMATCH` и `INVALID_INTERVAL` |
| Сервер блокирует занятую пару и атомарно сохраняет свободную подмену | PASS | `reschedule-postgres.integration.spec.ts`: конфликт не выдаёт preview token; свободная пара сохраняет новые `teacher_id`/`room_id`, source=`rescheduled`, transition=`1`; replay возвращает тот же transition |
| Полный регресс после исправления | PASS | targeted Flutter `25/25`; PostgreSQL reschedule `6/6`; Windows device `1/1`; Flutter `718/718`, analyze PASS; backend `168/168` suites и `1317/1317` tests, typecheck/build PASS |

## Локальный UAT-092 — единая матрица конфликтов

Это техническое доказательство текущего checkout, а не production owner-UAT.
Подробный trace: [`UAT-092.md`](UAT-092.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Student/Group/Teacher/Room overlap, часы/закрытый день Branch, Teacher availability/Branch assignment, Room Branch и duration overlap проверяются одной матрицей | PASS | `constraint-engine.spec.ts` + `constraint-engine-postgres.integration.spec.ts`; group Lesson блокирует ученика и после выхода из текущего состава по immutable `lesson_snapshot_participants` |
| One-time, reschedule, Plan create/update и horizon materializer не имеют отдельного conflict bypass | PASS | lesson write parity, reschedule, lesson-series и schedule-plan PostgreSQL tests; materializer вызывает `ScheduleConstraintEngine.validate` для каждого occurrence/participant под общими resource/client/series locks |
| Конфликт не создаёт частичный результат | PASS | schedule-plan PostgreSQL: standalone client overlap и закрытый день дают `0` materialized Lesson; после удаления blocker создаётся ровно одно занятие в branch-local времени |
| Dashboard/week/day и room-availability путь не обходят полную форму | PASS | пустой слот открывает единственный `CreateLessonDialog`; drag target отсутствует; availability остаётся read-only occupancy projection и показывает `Без занятий/С занятиями`, не обещая свободный slot |
| Пользователь видит все причины до сохранения | PASS | [`lesson-constraint-blocked-preview.png`](lesson-constraint-blocked-preview.png): обязательная причина, старое/новое время, состояние `Изменение заблокировано`, все 8 русских объяснений и только `Закрыть/Повторить расчёт`; Windows device `1/1`, preview=`1`, commit=`0` |
| Полный регресс после исправления | PASS | targeted backend `7/7` suites, `88/88`; targeted Flutter `40/40`; Flutter `719/719`, analyze PASS; backend `168/168` suites и `1319/1319` tests, typecheck/build PASS |

## Локальный UAT-093 — конкурентное бронирование двумя Manager

Это техническое доказательство текущего checkout, а не production owner-UAT.
Подробный trace: [`UAT-093.md`](UAT-093.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Два независимых Manager-сеанса одновременно создают один slot | PASS | PostgreSQL test использует разные Manager user/actor keys, idempotency keys и request IDs; результат — ровно `1` fulfilled winner и `1` authoritative structured `422` loser с teacher/client/room overlap |
| Проигравший запрос не оставляет частичных данных | PASS | после race в БД ровно по одному Lesson, snapshot, settlement plan/revision, aggregate version, audit, outbox и completed idempotency record |
| Conflict понятен, bypass отсутствует | PASS | [`lesson-concurrent-manager-conflict.png`](lesson-concurrent-manager-conflict.png): «Занятие не сохранено», «Аудитория уже занята», ссылка на Lesson, нет «Всё равно назначить» |
| Введённые данные проигравшего Manager сохранены | PASS | [`lesson-concurrent-manager-draft-retained.png`](lesson-concurrent-manager-draft-retained.png): Client, Branch, Room, Teacher, дата/время, `90 мин`, пробный флаг и финансовое решение остались в форме |
| Полный регресс | PASS | targeted backend `5/5`, widget `19/19`, Windows device `1/1`; Flutter `719/719`, analyze PASS; backend `168/168` suites и `1319/1319` tests, typecheck/build PASS |

## Локальный UAT-094 — отмена всеми применимыми типами

Это техническое доказательство текущего checkout, а не production owner-UAT.
Подробный trace: [`UAT-094.md`](UAT-094.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| UI показывает только пять типов, разрешённых каталогом для cancel | PASS | [`lesson-cancel-applicable-types.png`](lesson-cancel-applicable-types.png): free/paid/partial/unpaid/penalty с конфигурационными labels/colors; settle-only типы backend отклоняет `422` без side effects |
| Preview объясняет финансовый результат до подтверждения | PASS | [`lesson-cancel-financial-preview.png`](lesson-cancel-financial-preview.png): причина, `0.50 ч`, независимая полная ставка `700,00 ₽`; PostgreSQL table test сверяет все пять типов |
| Баланс, резерв, история и replay атомарны | PASS | для каждого типа проверены Lesson `v1→v2`, доступные часы, `consumed/released`, client/teacher facts, configuration revisions, reason transition, audit/outbox/idempotency cardinality `1` и exact replay |
| Stale-version не создаёт тупик и не теряет ввод | PASS | [`lesson-cancel-stale-version-recovered.png`](lesson-cancel-stale-version-recovered.png): понятная конкурентная причина, поля сохранены, действие вернулось к `Рассчитать`; устаревшие preview/identity сброшены, `currentVersion` используется внутри controller без мутации входной Map |
| Полный регресс | PASS | targeted backend `7/7`, Flutter `7/7`, Windows device `1/1`; Flutter `720/720`, analyze PASS; backend `168/168` suites и `1320/1320` tests, typecheck/build PASS |

## Локальный UAT-095 — одна Lesson и один editor

Это техническое доказательство текущего checkout, а не production owner-UAT.
Подробный trace: [`UAT-095.md`](UAT-095.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Month/Week/оба Day и карточка клиента используют один editor | PASS | общий `ScheduleWidget` ведёт все lesson entry points через `_showLessonDetails → CreateLessonDialog.show`; [`lesson-canonical-editor.png`](lesson-canonical-editor.png) показывает полную форму из календаря клиента |
| Paged и Group tray больше не являются тупиком | PASS | item вне `fallbackLessons` загружается точным actor-scoped `lessonId` через существующий endpoint и открывает тот же editor; widget проверяет запрос и group path без внешнего callback |
| Back сохраняет дату, фильтр и scroll | PASS | [`lesson-editor-back-context-restored.png`](lesson-editor-back-context-restored.png): тот же Day `4 августа`, раскрытые чужие занятия и позиция `20:00`; device сравнивает точный vertical offset, widget — horizontal tray offset |
| Новый entry point не обходит protected mutation flow | PASS | открытие только гидратирует actor-scoped Lesson; перенос/подмена остаются в общем reason/signed-preview/confirm/version/idempotency path, отмена/расчёт — в `LessonDecisionFlow` |
| Полный регресс | PASS | targeted tray widget `13/13`, backend schedule `58/58`, Windows device `1/1`; Flutter `721/721`, analyze PASS; backend `168/168` suites и `1321/1321` tests, typecheck/build PASS |

## Локальный UAT-101 — hidden/share-with-teacher комментарии

Это техническое доказательство текущего checkout, а не production owner-UAT.
Подробный trace: [`UAT-101.md`](UAT-101.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Staff явно различает скрытый и Teacher-поток | PASS | [`comment-hidden-staff.png`](comment-hidden-staff.png): скрытый текст, badge `Админ`, действие публикации и подпись выбора потока |
| Versioned-публикация обновляет UI без технической ошибки | PASS | [`comment-shared-staff.png`](comment-shared-staff.png); исправлен async return из `setState`, тест запрещает error/snackbar; exact PATCH содержит flag/version/reason |
| Teacher видит только опубликованный текст, Client — ни один staff stream | PASS | [`comment-shared-teacher.png`](comment-shared-teacher.png); PostgreSQL assigned/unrelated Teacher и Client projection |
| Audit/outbox/idempotency/stale атомарны и не содержат body | PASS | PostgreSQL staff `4/4`, denied roles `2/2`, exact replay, stale rollback, один audit/outbox с безопасным reason text |
| Полный регресс | PASS | targeted backend `9/9`, Flutter `6/6`, Windows `1/1`; Flutter `721/721`, backend `168/168` suites и `1321/1321` tests, analyze/typecheck/build PASS |

## Локальный UAT-105 — operational history клиента

Это техническое доказательство текущего checkout, а не production owner-UAT.
Подробный trace: [`UAT-105.md`](UAT-105.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Conversion/comment/task больше не выпадают из client history | PASS | allowlist и SQL lineage связывают `crm.lead_converted`, оба comment action и три shared-task action с Lead/Student |
| Автор и понятная причина присутствуют | PASS | exact user reason сохраняет приоритет; действия без reason field получают безопасное русское объяснение, comment sharing пишет явный `reason_text` |
| Private body не попадает в проекцию | PASS | PostgreSQL fixture содержит `PRIVATE-HISTORY-COMMENT`, итоговый history JSON — нет |
| Teacher/Client не читают staff history | PASS | backend отказывает до history query, Flutter не монтирует staff endpoint |
| Полный регресс | PASS | PostgreSQL `9/9`, Flutter context `6/6`; Flutter `721/721`, backend `168/168` suites и `1321/1321` tests, analyze/typecheck/build PASS |

## Локальный UAT-102 — all-day/interval задачи и reminder

Это техническое доказательство текущего checkout, а не production owner-UAT.
Связанный task-reminder срез `UAT-112` включён в тот же trace:
[`UAT-102.md`](UAT-102.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| All-day и interval имеют явную семантику даты/времени | PASS | [`task-all-day-reminder.png`](task-all-day-reminder.png) и [`task-interval-reminder.png`](task-interval-reminder.png); invalid interval виден и не отправляется |
| Person/Branch/School preview совпадает с фактическими получателями | PASS | table-driven PostgreSQL: exact `recipientSummary`, audience/reminder и unique `reminderRecipients` для трёх сценариев |
| Частичный delivery retry не создаёт дубли | PASS | стабильный id на reminder+recipient; после simulated outage остаются ровно два notifications/recipients без повторной email/push постановки |
| Task notification открывает точную задачу и сохраняет read-state | PASS | [`task-reminder-notification.png`](task-reminder-notification.png); PostgreSQL service restart и тёмный Windows device route |
| Полный регресс | PASS | targeted Flutter `19/19`, backend `3/3` suites и `24/24` tests, Windows `3/3`; Flutter `724/724`, backend `168/168` suites и `1324/1324` tests, analyze/typecheck/build PASS |

## Локальный UAT-112 — Lesson change notification

Это техническое доказательство текущего checkout, а не production owner-UAT.
Полный Lead/Task/Lesson trace: [`UAT-112.md`](UAT-112.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Создание/перенос/отмена материализуются из durable outbox | PASS | backend action matrix; технический state-only refresh не создаёт уведомление |
| Client и новый Teacher открывают successor, снятый Teacher — source | PASS | PostgreSQL reschedule `8/8`, exact recipients/routes и push cardinality `2+1` |
| Group audience использует frozen snapshot и только active app accounts | PASS | audience regression на изменённом текущем составе, deleted/non-app identities исключены |
| Retry не создаёт notification/push дубли, read-state переживает restart | PASS | двойная materialization и новый экземпляр notification service на PostgreSQL |
| Windows notification открывает точное занятие | PASS | [`lesson-change-notification.png`](lesson-change-notification.png); тёмный Windows device `4/4` |
| Полный регресс | PASS | targeted backend `6/6` suites и `94/94` tests, Flutter widget `3/3`; Flutter `725/725`, backend `168/168` suites и `1330/1330` tests, analyze/typecheck/build PASS |

## Локальный UAT-110 — прямой чат и медиа

Это техническое доказательство текущего checkout, а не production owner-UAT.
Полный trace: [`UAT-110.md`](UAT-110.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Text/image/file/voice сохраняются и повторно читаются, voice duration не теряется | PASS | PostgreSQL integration; [`direct-chat-media.png`](direct-chat-media.png); Windows device `1/1` |
| Edit/delete/reaction/pin/read работают в Teacher↔Manager direct | PASS | реальная PostgreSQL lifecycle; pin выполнен Manager и Teacher |
| Чужой upload, неверные purpose/MIME и cross-chat reply/forward fail-closed | PASS | negative PostgreSQL/service matrix; partial messages `0`; file FK `23503` |
| Ошибка message commit не оставляет новый upload сиротой | PASS | Flutter File API rollback contract и service tests |
| Media soft-delete сохраняет tombstone и не нарушает payload constraint | PASS | миграция `0125`, PostgreSQL image delete/readback |
| Полный регресс | PASS | Flutter `729/729`, backend `170/170` suites и `1342/1342` tests; analyze/typecheck/build PASS; RepoWise risk `2.44`, breaking/conformance/cycles `0` |

## Локальный UAT-111 — группы, каналы и support lifecycle

Это техническое доказательство текущего checkout, а не production owner-UAT.
Полный trace: [`UAT-111.md`](UAT-111.md).

| Проверка | Результат | Доказательство |
|---|---|---|
| Group создаётся, состав расширяется/сокращается, участник выходит отдельным действием | PASS | PostgreSQL lifecycle; [`group-member-management.png`](group-member-management.png); Windows device `1/1` |
| Channel role/user ACL различает чтение, публикацию и управление | PASS | PostgreSQL access matrix; [`channel-permissions.png`](channel-permissions.png); Windows device `1/1` |
| Teacher с явным `canWrite` видит composer, но не может менять ACL | PASS | authoritative `/channels/:id/access`, policy и Flutter widget matrix |
| Title-only update сохраняет ACL; invalid/duplicate/write-only targets fail-closed | PASS | service tests и PostgreSQL constraints миграции `0126` |
| Channel create/update/remove синхронизирует старых и новых получателей realtime | PASS | gateway/service и Flutter realtime tests |
| Support assign/unassign/archive/unarchive переживает readback | PASS | реальный PostgreSQL lifecycle |
| Полный регресс | PASS | Flutter `735/735`, backend `171/171` suites и `1352/1352` tests; analyze/build PASS; RepoWise risk `3.64`, breaking/conformance/cycles `0` |

## UX — длинные списки

| Проверка | Результат | Доказательство |
|---|---|---|
| Ввод `UAT-20260808` прямо в поле оставляет только три совпавших реальных аккаунта | PASS | `windows-release/11-searchable-teacher-filter.png` |
| Без фильтра одновременно видны не более пяти записей; справа виден scrollbar, колесо показывает следующие записи | PASS | `windows-release/12-searchable-teacher-scroll.png` |
| Все оставшиеся короткие выпадающие списки ограничены высотой пяти строк и прокручиваются штатным scrollbar; длинные сущностные списки используют поиск | PASS | `windows-release/21-lead-source-compact-scroll-165.png` |

Тот же общий компактный селектор используется для клиентов, преподавателей,
аудиторий, абонементов, плательщиков и исполнителей. На Android его список
прокручивается стандартным свайпом.

Production DB дополнительно подтверждает: дисциплина филиала `Вокал`,
аудитории `1/2/8`, пользователь `uat.teacher.20260808.01@gmail.com` с ролью
`teacher`, связанный профиль преподавателя, филиал и дисциплина. Секреты и
хеши паролей в evidence не сохраняются.

После разделения экранов production API повторно проверен: health=`ok`,
отдельное чтение часов вернуло филиал `60958318-8d92-4c54-8d56-ded34ee8f8c1`,
версию `2` и `6` рабочих дней; тот же endpoint без сессии вернул `401`.
Перед выкладкой создан серверный backup
`server-pre-schedule-settings-20260809T133353Z.tgz`; миграции и данные БД не
изменялись.

График `Teacher UAT-20260808-01` сохранён через production UI и повторно
прочитан через API: версия `2`, правила пн/ср/пт `09:00–21:00`, недоступность
`20.08.2026 14:00–18:00`, причина `UAT-20260808 teacher unavailable`.

Android APK `versionCode=164`/`versionName=1.5.1` подписан схемой v2,
установлен поверх предыдущей версии без очистки данных и после холодного
перезапуска эмулятора открыл сохранённое рабочее пространство преподавателя;
UI-tree содержит `Чат`, `Расписание`, `Ученики`, fatal/ANR в logcat — `0`.

Повторная сборка `versionCode=165`/`versionName=1.5.1` прошла после общего
ограничения высоты всех выпадающих меню. Windows Release создал и повторно
прочитал production-лида; Android Release установлен поверх `+164`, сохранил
сессию преподавателя (`android-release/04-teacher-session-preserved-165.png`),
fatal/ANR/`E/flutter` в свежем logcat — `0`. Flutter analyze чистый, полный
набор Flutter-тестов — `654/654`.

В `1.5.1+166` закрыт обнаруженный мегатестом дефект возврата из канонической
карточки: доски лидов и учеников больше не возвращают устаревший результат
того же фильтра. Реальный лид прошёл статусы `В процессе` → `Пробный Урок` →
`Звонок после пробного` → `Успешный`; production API подтвердил итоговый
статус, филиал `UAT-20260808-01 Оборонная` и источник `Звонок`. Flutter
analyze чистый, полный набор Flutter-тестов — `656/656`. Android APK
`versionCode=166`/`versionName=1.5.1` подписан v2, установлен обновлением без
очистки данных; после холодного запуска UI-tree содержит `Чат`, `Расписание`,
`Ученики`, fatal/ANR/`E/flutter` в свежем logcat — `0`.

В `1.5.1+167` production-аудит сохраняет причину модерационного действия в
отдельном `reason_text`, оставляя технические метаданные маскированными.
Реальный API и длинная Admin-карточка вернули `UAT-042 audit visibility
2026-08-09`, автора `Директор Тестов` и время. Перед deploy создан backup
`pre-client-history-20260809T175624Z.sql.gz`; миграций не было. Backend:
typecheck/build PASS, Jest `157/157` suites и `1248/1248` tests. Android APK
`versionCode=167` подписан v2 и после реального входа `magic2` сохранил
Teacher-сессию при холодном перезапуске (`android-release/06-teacher-session-preserved-167.png`);
UI-tree содержит `Чат`, `Расписание`, `Ученики`, fatal/ANR/`E/flutter` — `0`.

В `1.5.1+169` закрыты два дефекта, найденные на UAT-043. Случайный порядок UUID
больше не назначает сохраняемую запись молча: оператор сравнивает дату создания,
источник, статус, филиал и короткий ID и обязан явно выбрать запись. После merge
штатный undo остаётся в постоянном диалоге. Production DB после UI merge→undo
подтвердила обе активные карточки, телефон `+79990009001`, источник `Звонок`,
статус `Успешный` исходной записи, восстановленный комментарий
`UAT-043 comment must survive merge and undo` на дубле и `undone_at` у обеих
тестовых записей `merge_log`. Health=`ok`; необъяснённых 5xx после исправления
нет. Перед сборкой Flutter analyze был чистым; общий gate для изменения:
Flutter `656/656`, backend `157/157` suites и `1248/1248` tests.

В `1.5.1+170` пройден UAT-044: HMAC-секрет настроен в production без
раскрытия значения, одинаковый webhook дважды вернул один `leadId`
`9b35e688-45d7-4efb-bacc-1d3e952cf6b5` (`replayed=false` → `true`). Outbox
`0643931d-48c4-4c95-ba44-306c9c7af11d` опубликован с первой попытки,
notification/recipient/delivery reconciliation дал `1/17/17`, уникальность
получателей и доставок — `17/17`, email-outbox — `0`, dead-letter — `0`.
Найденный мегатестом разрыв materialization закрыт на сервере, а связанное
уведомление теперь открывает каноническую именованную desktop-вкладку. Сервер
работает на ревизии `9178064`, health=`ok`; миграций не было. Перед выкладками
сохранены backups `pre-4ea273d-20260809T191343Z` и
`pre-9178064-20260809T193246Z`. Flutter analyze чистый, Flutter `657/657`,
backend `157/157` suites и `1249/1249` tests.

В `1.5.1+171` карточки лидов и учеников показывают переход в чат только при
наличии активного аккаунта приложения. Production API и БД подтвердили
`linkedUserId=null` у двух UAT-лидов и активную связь ученика `Ученик Тестов`
с `magic1@gmail.com`. Найденная UI-проверкой потеря адресата при замене вкладки
закрыта каноническим маршрутом с `partnerId`; исходная вкладка сохраняется.
Flutter analyze чистый, полный набор Flutter-тестов — `659/659`; backend gate
для серверной части — `157/157` suites и `1249/1249` tests.

В `1.5.1+175` закрыт обнаруженный owner-UAT разрыв расписания. Переход из
карточки больше не создаёт псевдораздел `Отчёт`: `lesson_list` имеет один
канонический ID раздела, повторный переход переиспользует существующую вкладку,
а сохранённые legacy-дубли схлопываются при восстановлении workspace. Клиентский
контекст теперь общий для встроенного и основного расписания: занятия филиала
загружаются один раз, чужие по умолчанию скрыты, выбранные записи и дни в том
кандидате были зелёными, после снятия чекбокса остальные становились видимыми
серыми. Начиная с локального `+180`, это историческое цветовое поведение
заменено независимым маркером связи, а фон занят только состояниями
`Забронировано`/`Завершено`/`Конфликт`. Production API и БД
подтвердили занятие `05ec7b08-dd74-5120-84a1-b43ab7e04e32` у лида
`bd5627b5-2767-4cee-913c-ccfb2bca7a27`; UI выявил отдельный дубль лида с тем же
именем, поэтому доказательство снято через typed-связь самого занятия. Также
исправлено завершение устаревшей локальной сессии после неуспешного refresh.
Flutter analyze чистый, полный набор Flutter-тестов — `663/663`; Windows Release
`1.5.1+175` собран и проверен на том же сохранённом production-профиле.

В `1.5.1+179` закрыты три дефекта, найденные UAT-046. Получатели задач теперь
ограничены одним серверным правилом `Admin / Manager / Director`; Teacher не
попадает ни в прямое назначение, ни в филиал, ни во «Всю школу», а
`system_admin` сохраняет глобальную видимость без получения задачи и
напоминания. Production-состав «Вся школа» уменьшился с `46` до корректных
`17`. Индивидуальный селектор больше не делает два невалидных запроса с
`limit=200`: сотрудники загружаются отдельными фильтрами ролей, филиалы — с
допустимым лимитом `100`. Задача на весь день становится просроченной только со
следующего московского дня. Production task
`00c7ab5e-b526-4337-b948-fb8262719595` имеет единственную audience-связь с
`magic3@gmail.com` (`admin`), `state=closed`, `version=3` и ровно один
append-only close-факт от этого администратора. Production API после deploy
healthy; targeted gates: backend `8/8`, Flutter tasks UI `15/15`, typecheck и
Flutter analyze PASS. Финальный gate: Flutter `664/664`, backend `157/157`
suites и `1250/1250` tests, backend build PASS. Публичный production health
вернул `status=ok`; контейнер API healthy, за 30 минут после deploy ответов 5xx
и runtime ERROR нет.

Статус всего мегатеста: **IN PROGRESS**. Этот файл фиксирует только уже
повторно пройденные части G3 и G4 и не заменяет итоговую матрицу UAT.
