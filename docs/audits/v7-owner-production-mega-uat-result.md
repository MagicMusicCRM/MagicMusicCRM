# V7 owner production mega-UAT — рабочая матрица

Run: `OWNER-20260808-01`
Среда: production
Локальный кандидат: `1.5.1+180`; production rollout не выполнялся
Статус: **IN PROGRESS**

`PARTIAL` и `PENDING` допустимы только во время исполнения. Перед `INT-S6`
каждая строка должна стать `PASS`, `FAIL` или `BLOCKED`. `PASS` требует все
применимые UI/API/DB-доказательства из утверждённого плана.

Индекс уже снятых доказательств:
[`v7-owner-mega-uat-evidence/README.md`](v7-owner-mega-uat-evidence/README.md).

## G0 — безопасность и воспроизводимость

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-000 | Зафиксировать commit, образы, миграции и hashes | PARTIAL | локальный кандидат `+180`, release hashes и migrations evidence сняты; нужен финальный commit и production image ledger |
| UAT-001 | Backup, пробный restore, начальные counts | PARTIAL | production backups есть; нужен единый restore-drill и counts этого run |
| UAT-002 | Release, production API, тёмная тема, реальные данные | PARTIAL | Windows/Android `+180` локально собраны и запущены в тёмной теме; нужен owner production Release proof после разрешённого rollout |
| UAT-003 | ID-ledger и каталог evidence без секретов | PARTIAL | evidence index и redacted API JSON созданы; нужен полный ledger всех UAT facts |

## G1 — авторизация и навигация пяти ролей

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-010 | Вход `magic1..5`, роли и навигация | PARTIAL | production API 5/5 PASS: `api/uat-010-five-roles-20260810.json`; ожидаются актуальные UI-кадры |
| UAT-011 | Relogin Client↔Director и Teacher↔Admin | PARTIAL | automated secure-session regression есть; нужен текущий Release UI proof |
| UAT-012 | 10 вкладок и связанные маршруты | PARTIAL | доказаны Lead/Chat/Schedule маршруты; полный набор десяти вкладок не снят |
| UAT-013 | Android Back, клавиатура, safe areas | PARTIAL | teacher session/navigation есть; Client и полный safe-area сценарий ожидаются |

## G2 — конфигурация CRM

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-020 | Категории: создание, порядок, архив | PENDING | — |
| UAT-021 | Все 16 типов полей Lead/Student | PENDING | — |
| UAT-022 | Ширины 1/3, 1/2, 1/1 и размещение | PENDING | — |
| UAT-023 | Одиночные/множественные варианты полей | PENDING | — |
| UAT-024 | Обязательные системные и UAT-поля | PARTIAL | обязательные поля Lead/Teacher доказаны; нужна полная матрица |
| UAT-025 | Длительность занятия и настройки расписания | PENDING | — |
| UAT-026 | Этапы/переходы Lead и Student | PARTIAL | Lead история доказана; конфигурация и Student ещё не пройдены |
| UAT-027 | 7 списаний и 5 правил оплаты преподавателю | PENDING | — |
| UAT-028 | Draft → preview → publish → realtime → rollback | PENDING | — |
| UAT-029 | Branch override и RBAC конфигурации | PENDING | — |

## G3 — филиал, люди, графики и права

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-030 | Создать/изменить филиал и увидеть во всех селекторах | PASS | `windows-release/01-branch-list.png` + `api/uat-030-034-organization-inventory-20260810.json` |
| UAT-031 | 3 аудитории, изменение и удаление свободной | PARTIAL | A/B/C `1/2/8` подтверждены; mutation edit/delete ещё не зафиксирована |
| UAT-032 | Часы филиала и закрытый день | PASS | `windows-release/13`, `17` + API version/readback |
| UAT-033 | 3 преподавателя, дисциплины, ставки, филиалы, графики | PARTIAL | API подтверждает 3 аккаунта/ставки/назначения; нужны UI и графики 02/03 |
| UAT-034 | Сотрудники, роли и app users | PARTIAL | API подтверждает UAT Admin/Manager; нужна role-assignment negative matrix/UI |
| UAT-035 | Capability Manager и realtime-инвалидация | PENDING | — |
| UAT-036 | Группа с преподавателем/филиалом/аудиторией | PENDING | выполняется после UAT-047 |

## G4 — Lead до конверсии

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-040 | Создать Lead с обязательными данными | PARTIAL | production Lead создан; нужны все назначенные UAT custom fields |
| UAT-041 | Посимвольный поиск, фильтры и карточка | PARTIAL | focus/search/card PASS; полный набор фильтров ожидается |
| UAT-042 | Статусы, ответственный, история и причины | PASS | `windows-release/25..32` + production DB/API |
| UAT-043 | Duplicate → merge → undo | PASS | `windows-release/33..37` + DB reconciliation |
| UAT-044 | Подписанный webhook и idempotency | PASS | `windows-release/38..40` + ingestion/outbox DB reconciliation |
| UAT-045 | Пробное занятие из Lead | PARTIAL | занятие видно в каноническом расписании; нужен полный create preview proof |
| UAT-046 | Задача по Lead и закрытие Admin | PASS | `windows-release/48..57` + task DB reconciliation |
| UAT-047 | Конкурентная конверсия Lead → Student | PENDING | следующий mutation-сценарий после пользовательского preview-кадра |

## G5 — карточка ученика

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-050 | Длинная desktop-карточка и mobile tabs | PENDING | — |
| UAT-051 | Основные поля, staff note и комментарии | PENDING | — |
| UAT-052 | Представитель, плательщик, family и linked user | PENDING | — |
| UAT-053 | Дополнительные поля внутри Overview | PARTIAL | automated/widget proof есть; нужен production Student UI |
| UAT-054 | Ученик и плательщик в группе | PENDING | зависит от UAT-047 и UAT-036 |

## G6 — личный счёт, оплаты и абонементы

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-060 | Три статуса оплаты (`Срок наступил — требуется проверка`) и долг | PENDING | — |
| UAT-061 | Наличные/безналичные, реквизиты и автор | PENDING | — |
| UAT-062 | Каталог 12×60/30000 и альтернативный пакет | PENDING | — |
| UAT-063 | Покупка абонемента со своего счёта | PENDING | — |
| UAT-064 | Покупка со счёта другого клиента | PENDING | — |
| UAT-065 | Рассрочка с полным резервом и частями | PENDING | — |
| UAT-066 | Долг/pending/paid/переплата/остатки | PENDING | — |
| UAT-067 | Замена активного абонемента | PENDING | — |
| UAT-068 | Отмена абонемента и возврат | PENDING | — |
| UAT-069 | Сторно unpaid/pending/paid и exclusion | PENDING | — |
| UAT-06A | Корректировка/возврат счёта и повтор | PENDING | — |

## G7 — предпочтительное и постоянное расписание

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-070 | Предпочтительное расписание | PENDING | — |
| UAT-071 | Индивидуальный Plan на несколько дней | PENDING | — |
| UAT-072 | Групповой Plan и participant subscriptions | PENDING | — |
| UAT-073 | Полная canonical conflict matrix и редактируемый конфликтный Plan | PENDING | — |
| UAT-074 | Active/ended планы и завершение | PENDING | — |
| UAT-075 | Tray, cursor и authoritative markers | PENDING | — |
| UAT-076 | Скрывать чужие и независимо отмечать target | PARTIAL | один production календарный контекст PASS; нужны Month/Week/Day с маркером связи, не подменяющим три цвета состояния Lesson |

## G8 — списания и оплата преподавателю

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-080 | Обязательные settlement/pay choices | PENDING | — |
| UAT-081 | Все 5 правил teacher pay | PENDING | — |
| UAT-082 | Абонемент по умолчанию и личный счёт | PENDING | — |
| UAT-083 | Пробное и бесплатное занятия | PENDING | — |
| UAT-084 | Реальное ожидание completion worker | PENDING | — |
| UAT-085 | `Конфликт` и `Исправить расчёт` при ошибке worker | PENDING | — |
| UAT-086 | Post-completion correction/reschedule с reversal и successor | PENDING | — |
| UAT-087 | Group common + per-client override | PENDING | — |

## G9 — переносы, отмены и конфликты

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-090 | Перенос через форму без drag-and-drop | PENDING | — |
| UAT-091 | Подмена преподавателя и аудитории | PENDING | — |
| UAT-092 | Все one-time/recurring conflict entry points | PENDING | — |
| UAT-093 | Два Manager бронируют один слот | PENDING | — |
| UAT-094 | Отмена применимыми типами | PENDING | — |
| UAT-095 | Единая Lesson во всех представлениях | PENDING | — |

## G10 — заметки, комментарии, задачи, ДЗ и история

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-100 | Staff note и скрытие от Client/Teacher | PARTIAL | backend/widget gates есть; нужен production role proof |
| UAT-101 | Hidden/share-with-teacher комментарии | PENDING | — |
| UAT-102 | All-day/interval задачи и reminder | PARTIAL | all-day закрыта Admin; interval/reminder ещё не пройдены |
| UAT-103 | Admin board: Мои+Сегодня, scopes, close | PASS | `windows-release/52..57` + DB reconciliation |
| UAT-104 | ДЗ с файлом из Прогресса | PENDING | — |
| UAT-105 | Operational history авторов/причин | PARTIAL | Lead/task PASS; нужны commerce/schedule/client actions |

## G11 — чат, уведомления и остальные разделы

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-110 | Direct chat: text/image/file/voice | PARTIAL | eligibility и открытие диалога PASS; сообщения/медиа ожидаются |
| UAT-111 | Group/channel permissions/lifecycle | PENDING | — |
| UAT-112 | Lead/task/lesson notifications | PARTIAL | inbound Lead PASS; task reminder и lesson change ожидаются |
| UAT-113 | Teacher rates, accrual, payout, stats, CSV | PENDING | — |
| UAT-114 | Expenses и finance RBAC | PENDING | — |
| UAT-115 | Data quality и deletion request | PENDING | — |
| UAT-116 | Loading/empty/error/forbidden/retry UI | PENDING | — |

## G12 — аналитика, поиск и экспорт

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-120 | Общие period/branch filters | PENDING | — |
| UAT-121 | Manager без school finance | PENDING | — |
| UAT-122 | XLSX OOXML и сверка строк/сумм | PENDING | — |
| UAT-123 | Поиск Lead/Student/teacher/room/lesson | PARTIAL | Lead search PASS; остальные сущности ожидаются |

## G13 — нагрузка и аварийные проверки

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-130 | Double-submit/idempotency mutations | PARTIAL | webhook/merge/task paths доказаны; finance/schedule/conversion ожидаются |
| UAT-131 | Обрыв сети, сохранение формы и Retry | PENDING | — |
| UAT-132 | Stale expectedVersion и recovery | PARTIAL | automated contracts есть; нужен production UI scenario |
| UAT-133 | Полная actor matrix private routes | PARTIAL | регулярные route/actor gates есть; нужен финальный candidate run |
| UAT-134 | Full tests/build/migrations/clean schema | PARTIAL | локально Flutter `666/666`, backend `157/157`/`1256/1256`, build/analyze PASS; clean `0001..0118`, `0118..0116 down/up`, Windows/APK/AAB собраны; нужен production candidate ledger |
| UAT-135 | Health, constraints, reconcile, workers, logs | PARTIAL | production-like startup `/health/live`+`/health/ready` PASS, v7 reconcile=0, fail-closed negative smoke PASS; нужен финальный production reconcile после rollout |

## G14 — пять персон и итоговое доказательство

| ID | Сценарий | Статус | Доказательство / остаток |
|---|---|---|---|
| UAT-140 | Client Android persona | PENDING | — |
| UAT-141 | Teacher Android persona | PARTIAL | session/navigation proof есть; нужен полный functional tour |
| UAT-142 | Admin Windows persona | PARTIAL | Lead/Schedule/Tasks доказаны; нужен полный functional tour |
| UAT-143 | Manager Windows persona | PENDING | — |
| UAT-144 | Director Windows persona | PARTIAL | organization/settings/tasks доказаны; нужен полный functional tour |
| UAT-145 | Архивация завершает recurring work и сохраняет историю | PENDING | только после приёмки остальных строк |
| UAT-146 | Итоговый DOCX и подпись владельца | PENDING | генерируется после 100 финальных результатов |

## Решение кандидата

**NOT YET APPROVED** — `T7.1.2` продолжается. `INT-S6` нельзя закрывать, пока
остаются `PARTIAL`/`PENDING`, открытый P0, необъяснённый drift/error либо
отсутствующее ролевое доказательство.
