# Полный RepoWise-аудит MagicMusicCRM

Дата: 2026-08-12
Checkout: `a12cca5` до governance cutover
Метод: RepoWise graph/symbol/risk/health/dead-code + точечная проверка живого
Flutter/NestJS/SQL-кода и актуального UAT evidence.

## Обновление после lifecycle-волн

Branch/Room/Group gaps закрыты в локальном checkout (ещё не production и не
owner-UAT):

- миграции `0119`/`0120`/`0121` добавляют lifecycle/version/tombstone,
  append-only history и write/race guards;
- API поддерживает preview, blockers, archive, restore и history для всех трёх
  сущностей;
- commit использует expected version, idempotency, transaction, audit/outbox;
- UI показывает архив, remediation blockers, preserved history,
  reason/effective date и восстановление;
- Group lifecycle сохраняет roster, завершённые занятия и финансовые факты,
  блокируя archive до завершения future lessons/series/plans;
- runtime-физического cascade delete нет.

Future-dated состояние `closing` намеренно не симулируется без scheduler и
write guards. Atomic Staff/Teacher offboarding, optional account creation,
credential sync и settings-only role elevation также закрыты локально
миграциями `0122`/`0123`; следующий P0 — их owner-UAT/release evidence.

Следующая reference-data волна также закрыта локально миграцией `0124`:
Discipline/Loss reason получили rename/archive/restore, Branch discipline —
unassign/restore, а UI, version/idempotency, audit/outbox, snapshots и DB guards
покрывают обратный сценарий. Это ещё не production-reachable и не owner-UAT.
После уточнения владельца Discipline, категории и уровни зафиксированы как
необязательная информационная метаинформация: текущие usage показываются в
impact/history, но не блокируют archive/unassign и не влияют на расписание.
Жёсткими остаются Teacher→Branch, teacher availability, Branch hours,
обязательные Branch/Room и конфликты. Создание Branch теперь требует график, а
Lesson подставляет `branch_id` выбранного клиента, оставляя Room ручным выбором.
Полный локальный gate после волны: Flutter `685/685`, backend `168/168` suites
и `1300/1300` tests, typecheck/build/analyze PASS; capability coverage
`344/344`, unexplained shadow differences `0`, Windows configuration
integration `3/3`.

Следующая schedule-волна закрыла локальный пробел групповых постоянных планов:
из карточки Group доступны preview/create, индивидуальный выбор активного
абонемента каждого участника и датированное versioned-изменение состава.
Сервер блокирует удаление ученика из roster, пока он остаётся участником
активного/будущего Plan, используя общий advisory group-lock с schedule-plan
write path. Полный локальный gate после этой волны: Flutter `696/696`, backend
`168/168` suites и `1301/1301` tests, typecheck/build/analyze PASS. Изменения
ещё не production-reachable и не прошли owner-UAT.

Волна canonical conflict matrix закрыла разрыв редактирования существующего
Plan: добавлен update-preview, использующий тот же constraint engine и полную
матрицу строк/участников до versioned update. Обычные будущие занятия
заменяемых series исключаются из самоконфликтов, но перенесённые занятия того
же Plan сохраняются как реальные блокеры. Flutter удерживает конфликтный
черновик, показывает все восемь категорий ограничений, имя конфликтующего
ученика группы и возвращает оператора прямо к нужному набору строк. Также
исправлен общий редактор: review скрывает даты, но оставляет доступными время и
длительность. Полный локальный gate: Flutter `698/698`, backend `168/168`
suites и `1304/1304` tests, Windows device-consumer `1/1`,
typecheck/build/analyze PASS. Production и release не изменялись.

Волна завершения Plan закрыла локальный разрыв между статически показанными
active/ended fixtures и настоящим переходом одной сущности. Flutter после
confirmed commit перечитывает Plan в ended-блок, убирает edit/end actions и
показывает управляющей роли дату, автора и причину; Client end metadata не
получает. Backend end/update теперь используют общий per-series advisory lock
с horizon materializer, поэтому worker не может создать occurrence между
impact и commit. Последняя дата ограничивает series, поздние unsettled Lesson
отменяются с release резервов, terminal/history/tray сохраняются. При раскрытии
архивной карточки найден и исправлен runtime PageStorage type collision между
ExpansionTile и горизонтальной tray. Полный локальный gate: Flutter `699/699`,
backend `168/168` suites и `1305/1305` tests, Windows device-consumer `1/1`,
typecheck/build/analyze PASS. Production и release не изменялись.

Downstream device-проверка карточки клиента выявила отдельную UI-регрессию:
`posted_pending` отображался не каноническим вторым статусом. Все точки выбора и
показа сведены к общему mapper, восстановлено название
`Проведён, ожидает подтверждения`; widget tests и Windows client-workspace
device `4/4` PASS. После дополнительного regression-теста полный Flutter gate
составляет `700/700`.

## Итог

Приложение технически зрелое и production-развёрнуто, но продукт нельзя считать
полностью завершённым. Главный очевидный пробел — асимметричный lifecycle:
организационные сущности можно создавать, но значительную часть нельзя штатно
закрыть, расформировать, архивировать или безопасно восстановить.

Это не повод добавлять простой `DELETE branch`. У филиала много исторических и
операционных связей; схема использует смесь `CASCADE`, `SET NULL` и
restrict/default FK. Физическое удаление либо сотрёт часть данных, либо оставит
осиротевшие проекции, либо будет заблокировано immutable finance/config facts.

## P0 — незавершённый organizational lifecycle

| Сущность | Реализовано | Отсутствует | Риск |
|---|---|---|---|
| Branch | локально list/create/update + preview/archive/history/restore | deploy/owner-UAT; future-dated closing | До release функция ещё не production-reachable |
| Room | локально list/create/update + preview/archive/history/restore, version/idempotency/audit/outbox и DB race guards | deploy/owner-UAT миграции `0120`; future-dated archive | До release функция ещё не production-reachable |
| Group | локально list/create/update/members + preview/archive/history/restore, version/idempotency/audit/outbox и DB race guards | deploy/owner-UAT миграции `0121`; future-dated archive | До release функция ещё не production-reachable |
| Teacher | локально optional login, linked credential management, preview/offboard/history/restore | deploy/owner-UAT `0122`/`0123` | До release функция ещё не production-reachable |
| Staff | локально safe-admin create, linked credential management, preview/offboard/history/restore | deploy/owner-UAT `0122`/`0123` | До release функция ещё не production-reachable |
| Branch discipline | локально add/reorder + preview/unassign/history/restore | deploy/owner-UAT `0124` | До release функция ещё не production-reachable |
| Discipline/loss reason | локально list/create + rename/archive/history/restore/usage guards | deploy/owner-UAT `0124` | До release функция ещё не production-reachable |

Нужен единый контракт:

```text
preview
  -> impact counts
  -> blockers
  -> canonical remediation (transfer/end/cancel)
  -> commit(reason, effectiveDate, expectedVersion, idempotencyKey)
  -> audit/outbox/history
```

Для немедленного закрытия Branch использует атомарное
`active → archived`. Если позже появится отложенное закрытие, только тогда
добавляется `active → closing → archived` вместе с write guards и scheduler.
Историческое имя/identity сохраняется в tombstone; активные Students/Leads,
Staff/Teachers, Rooms/Groups, Plans/future Lessons, Tasks и commerce references
сначала переносятся или завершаются явной командой.

## Другие незакрытые продуктовые доказательства

Локальная волна `UAT-075` закрыла технические пробелы tray постоянного Plan:
стабильный двунаправленный keyset cursor, bounded response, fail-closed
невалидные cursor/direction, точный retry страницы, видимые date/time и
authoritative settlement/relation markers. Ended archive остаётся свёрнутым по
умолчанию. Flutter model/widget, PostgreSQL integration, Windows device `2/2`
и полные suites прошли. RepoWise по-прежнему отмечает основной Plan widget как
churn-heavy hotspot (`91%`), поэтому дальнейшие изменения в нём должны быть
малыми и сопровождаться device-проверкой.

Локальная волна `UAT-076` проверила календарь карточки клиента во всех
представлениях. Default-hide, локальное раскрытие branch matrix, независимые
target/other markers, Month day mark, Week, Day-by-room, Day-by-teacher, три
статусных цвета и Back state restore прошли widget и тёмный Windows device
`1/1`. Исправлены отсутствующий marker в teacher timeline и неправильная
подпись Month `августа 2026`. Backend policy запрещает Client доступ к staff
schedule matrix. Production evidence остаётся обязательным. RepoWise отметил
затронутый views-файл как bug-magnet `97%`, поэтому правка подписи оставлена
однострочной, а весь Flutter suite пройден.

Локальная волна `UAT-070` закрыла технический пробел в доказательстве
предпочтительного расписания: тестовый API теперь моделирует commit и
read-after-write, карточка после повторного GET показывает сохранённые
branch/teacher/room/weekday series. Отдельный widget и тёмный Windows device
подтвердили, что фактическое Lesson видно при пустых preferences/Plan и не
исчезает после добавления preference. Production-компоненты не менялись:
RepoWise оценил `student_schedule_section.dart` как hotspot `95%` с test gap,
а Plan widget как hotspot `91%`/bus factor 1, поэтому доказательство добавлено
на швах тестового API и device consumer. Production evidence ещё обязательно.

Локальная волна `UAT-071` подтвердила многодневный индивидуальный Plan без
создания параллельной модели: одна команда сохраняет два дня с общими
teacher/room и отдельную строку с другими teacher/room. Widget и тёмный Windows
device доказали create/read-after-write, PostgreSQL integration — атомарность,
idempotency и отсутствие дублей при повторной materialization. RepoWise
отметил тестовый API как hotspot `95%` с 32 dependents, Plan widget как hotspot
`87%`, device-файл как `81%`, а PostgreSQL integration как `93%`; поэтому
эмуляция commit включается только opt-in, production orchestration не
рефакторилась, а изменение закрыто точечными и полными gate. Production
evidence ещё обязательно.

Локальная волна `UAT-080` доказала обязательность и независимость трёх решений
при создании Lesson: типа списания, правила оплаты преподавателю и источника
средств. Widget проверяет явный выбор и пустой каталог, Windows device — живую
форму и успешный commit, PostgreSQL integration — пять fail-closed вариантов
без частичных записей и атомарный Lesson/snapshot/plan/revision для валидной
команды. RepoWise отметил `create_lesson_dialog.dart` как hotspot `99%`, widget-
тест как `95%`, device consumer как `70%`, backend parity test как `92%`;
поэтому production orchestration не рефакторилась без доказанного дефекта, а
контракт усилен на тестовых швах. Полные gate: Flutter `705/705`, backend
`168/168` suites и `1306/1306` tests. Production evidence ещё обязательно.

Локальная волна `UAT-081` закрыла недостающую five-rule матрицу teacher pay.
Чистый calculation test проверяет формулы none/standard/percent/fixed/hourly и
границы override, staff UI показывает все пять правил и требует reason до
preview, а реальная PostgreSQL settlement сохраняет effective fact каждого
mode с отдельными configured default, actual value, amount и revision.
Отклонённый override доказан транзакционно: ни client, ни teacher fact не
остаётся. RepoWise отметил repository как hotspot `98%` с test gap/bus factor
1, PostgreSQL test как `94%`, decision flow как недавно исправлявшийся hotspot,
поэтому production orchestration не менялась без доказанного дефекта. Полные
gate: Flutter `706/706`, backend `168/168` suites и `1308/1308` tests.
Production evidence ещё обязательно.

Локальная волна `UAT-082` обнаружила и закрыла реальную несогласованность
funding source: платный `lesson` раньше принимал `clientChargeType=none` и мог
тихо сформировать нулевой client fact. Общий settlement calculation теперь
разрешает `none` только при нулевых share и fixed penalty, а create transaction
проверяет это до commit и откатывает Lesson/Plan целиком. Flutter автоматически
выбирает конкретный активный абонемент, сохраняет явный personal-account путь и
переключает бесплатный settlement на `none` без `subscriptionId`. RepoWise
отметил форму как bug magnet/hotspot `99%`, repository как hotspot `98%`, parity
test как `92%`; поэтому изменение закреплено widget, calculation, PostgreSQL и
Windows device evidence. Полные gate: Flutter `707/707`, backend `168/168`
suites и `1309/1309` tests. Production evidence ещё обязательно.

Локальная волна `UAT-083` доказала, что trial и free не являются синонимами.
Flutter payload покрывает trial paid subscription, trial free, non-trial paid и
non-trial free; Windows визуально показывает включённый trial marker вместе с
платными `lesson/personal_account`. Реальный completion worker провёл четыре
PostgreSQL‑комбинации: trial paid сохранил `80000` minor, non-trial subscription
потребил `1.00`, оба `free_lesson/none` сохранили `0/0.00` без reservation и
изменения активного абонемента. Teacher fact остался независимым (`90000`) во
всех случаях. RepoWise отметил create form как bug magnet/hotspot `99%`,
completion test как hotspot `93%`, lifecycle/completion сервисы как bus factor
1 с test gap; живой код не показал дефекта, поэтому production orchestration не
менялась, а пробел закрыт UI/device/DB evidence. Полные gate: Flutter `709/709`,
backend `168/168` suites и `1313/1313` tests. Production evidence ещё
обязательно.

Локальная волна `UAT-084` закрыла отдельный пробел доказательства: прежний тест
измерял уже due fixture через прямой `runOnce`, но не запускал lifecycle-таймер
worker. Новый PostgreSQL-сценарий создаёт Lesson, окончание которого наступает
через `2.5s`, подтверждает отсутствие due/work/facts до срока, запускает
production `onModuleInit` с секундным polling и наблюдает completion только после
реального ожидания. Frozen subscription plan применён ровно один раз: work
`completed/attempts=1`, по одному transition/client/teacher/audit/outbox/
idempotency, reservation `consumed`, plan `settled`; последующий timer tick не
меняет counts. RepoWise отметил test как churn-heavy hotspot `93%` и bus factor
1, поэтому production orchestration не менялась. Полные gate: Flutter `709/709`,
backend `168/168` suites и `1314/1314` tests, analyze/typecheck/build PASS.
Production worker/UI/API/DB evidence ещё обязательно.

Локальная волна `UAT-085` обнаружила четыре сквозных разрыва: schedule matrix
не отдавала version, lifecycle `settlement_pending` в quick view подменялся
legacy `scheduled`, failure code не доходил до staff, а прямой API позволял
settle обычного scheduled Lesson. Теперь poison worker оставляет связку
`settlement_pending + review_required`; role-gated API проецирует version и
failure code только staff; UI показывает `Конфликт`, безопасную русскую причину
и `Исправить расчёт`; scheduled settle получает
`LESSON_SETTLEMENT_REVIEW_NOT_REQUIRED`. Recovery повторно валидирует plan под
lock, а успешный commit переводит его в `settled` и очищает failure code.
RepoWise отметил transition/schedule/UI projection как churn-heavy/bug-prone
hotspots с широким impact surface, поэтому исправление закреплено PostgreSQL,
mapper, isolated widget, реальным schedule→preview и Windows device evidence.
Полные gate: Flutter `710/710`, backend `168/168` suites и `1315/1315` tests,
analyze/typecheck/build PASS. Production evidence ещё обязательно.

Локальная волна `UAT-101/UAT-105` закрыла два сквозных пробела G10. Визуальный
Windows-прогон обнаружил успешный PATCH, после которого refresh возвращал
`Future` из `setState` и показывал пользователю техническую ошибку; callback
исправлен и закреплён device regression. PostgreSQL доказывает четыре staff-
роли, exact Teacher/Client projection, stale/replay/deny без частичных записей
и отсутствие private body в outbox/history. Operational history теперь
связывает существующие immutable audit-факты conversion, comments и linked
shared tasks с Lead/Student наряду с commerce/schedule/note. Полные gate:
Flutter `721/721`, backend `168/168` suites и `1321/1321` tests,
analyze/typecheck/build PASS. Production не изменялся.

Локальная волна `UAT-102/UAT-112-task` обнаружила четыре разрыва: all-day дата
сохраняла время открытия формы, точное время reminder нельзя было увидеть или
изменить, UI пропускал обратный interval, а уведомление не содержало task
route. Дополнительно частичный сбой multi-recipient delivery мог повторно
создать уже доставленное уведомление. Форма теперь использует календарную
all-day дату, явный reminder и fail-fast interval validation. Worker передаёт
exact task route и стабильный per-recipient notification id; notification
service дедуплицирует email/push side effects. RepoWise заранее отметил UI,
task worker/repository и notification service как churn-heavy/bug-prone
hotspots с широким impact surface, поэтому изменения закреплены table-driven
PostgreSQL audience matrix, simulated partial retry, widget и Windows device
route/read-state. Полные gate: Flutter `724/724`, backend `168/168` suites и
`1324/1324` tests, analyze/typecheck/build PASS. Production не изменялся.

Локальная волна `UAT-112-lesson` обнаружила, что после закрытия legacy bypass
канонический lesson transition больше не вызывал старое прямое уведомление, а
platform outbox публиковал schedule event только в realtime. Кроме того,
lesson reminder/trial payload не содержал канонический entity route, group
audience зависел от текущего roster, а state-only settlement refresh мог быть
ошибочно принят за второй перенос. Теперь только явные
`created/rescheduled/cancelled` action материализуют durable notification:
Client и новый Teacher открывают successor, снятый Teacher — source; group
audience использует frozen snapshot и active app accounts. Event ID обеспечивает
retry-dedupe notification/push, read-state сохраняется после service restart.
RepoWise отметил notification/schedule/outbox точки как hotspots с широким
impact surface, поэтому изменение закреплено unit/action matrix, реальной
PostgreSQL reschedule/cardinality/retry интеграцией, Flutter route widget и
тёмным Windows device `4/4`. Полные gate: Flutter `725/725`, backend `168/168`
suites и `1330/1330` tests, analyze/typecheck/build PASS. Production не
изменялся.

Owner mega-UAT содержит 100 уникальных сценариев: `10 PASS`, `52 PARTIAL`,
`38 PENDING`. Не доказаны полностью:

- role/device сценарии пяти ролей;
- весь CRM configuration publish/rollback/realtime цикл;
- Student Card desktop/mobile и связанные family/payer flows;
- subscription/payment/reversal/refund combinations;
- recurring plans, lesson transition и settlement drilldowns;
- messenger attachments/voice/channel lifecycle;
- loading/empty/error/forbidden/retry/offline/stale-version states;
- analytics filters, exports и entity-wide search.

Точный статус хранится в
`docs/audits/v7-owner-production-mega-uat-result.md`.

## Техническое здоровье

RepoWise dashboard на исходном checkout:

- средний health: `7.2`;
- hotspot health: `6.6`;
- worst score: `1.0`;
- 67 static performance findings;
- 198 dead-code candidates;
- только 20 high-confidence cleanup-ready exports, около 204 строк.

Основные hotspots для отдельного рефакторинга:

| Файл/модуль | Причина |
|---|---|
| `lib/features/crm/presentation/client_card/client_card_student.dart` | worst health, крупный UI aggregate |
| `lib/features/admin/presentation/widgets/crm_configuration_workspace.dart` | draft/catalog/publish/UI в одном файле |
| `lib/features/admin/presentation/widgets/shared_tasks_v4_panel.dart` | query, filters, audience editor и cards сцеплены |
| `server/src/crm/commerce/subscription-lifecycle.service.ts` | крупная transaction orchestration |
| `server/src/crm/crm.service.ts` | god-service и bug-magnet |
| `server/src/crm/lesson-settlement.repository.ts` | смешаны reads, writes, correction/reversal |

Cleanup нужно делать отдельными малыми изменениями после проверки runtime
dispatch. RepoWise не нашёл ни одного high-confidence package, безопасного для
автоматического удаления: его medium `zombie_package` кандидаты включали
`windows`, `android`, `infra` и integration tests, то есть были structural false
positives.

## Release и source-of-truth

На момент аудита production candidate был на 17 commits впереди `origin/main`.
Это recovery-риск: новый hotfix не должен стартовать со старого default branch.
Governance cutover должен быть fast-forward синхронизирован в GitHub.

Production build 181 и exact hotfix image прошли технические gates, но это не
закрывает owner UAT и не отменяет lifecycle findings.

## Приоритет

1. Branch/Room/Group lifecycle deploy/owner-UAT для миграций
   `0119`/`0120`/`0121`.
2. Staff/Teacher optional account + lifecycle owner-UAT для `0122`/`0123`.
3. Reference-data lifecycle deploy/owner-UAT для `0124`.
4. Новые owner-UAT строки для всех обратных lifecycle.
5. Production owner-UAT многодневного индивидуального Plan.
6. Production owner-UAT группового Plan и participant subscriptions.
7. Затем — hotspot refactoring и проверенный dead-code cleanup.
