# MagicMusicCRM - production CRM и мессенджер для сети музыкальных школ

## Короткое описание для резюме

Разработал и запустил MagicMusicCRM - production CRM и мессенджер для сети музыкальных школ. В одиночку спроектировал архитектуру, реализовал full-stack, перевел продукт с Supabase runtime на собственный NestJS/PostgreSQL backend на VPS Selectel, импортировал данные из старой CRM HolliHop в собственную БД и провел проект через миграцию данных, performance/security gates, realtime-проверки, Linear delivery tracking и store-readiness процессы с использованием AI-агентов как инженерного ускорителя.

**Стек:** Flutter, Dart, Riverpod, GoRouter, Dio, Socket.IO, NestJS, TypeScript, PostgreSQL, Redis, Docker Compose, Caddy, private file storage, Firebase Messaging, Sentry, Resend/SMTP, МТС Exolve SMS.

**Зона ответственности:** CRM, лиды, расписание, уроки, оплаты, абонементы, домашние задания, мессенджер, приватные файлы, уведомления, авторизация, юридические согласия, удаление аккаунта, аналитика, импорт старой CRM, оптимизация БД, бэкапы, мониторинг, Linear backlog и релизная инфраструктура.

## One-liner для портфолио

MagicMusicCRM - production mobile/desktop CRM и мессенджер для управления сетью музыкальных школ, построенный solo end-to-end с AI-assisted workflow: от продуктовой архитектуры и Flutter UI до защищенного NestJS/PostgreSQL backend, realtime, приватного файлового хранилища, полного импорта данных из HolliHop, оптимизации PostgreSQL, VPS-деплоя, Linear delivery tracking и релизных проверок.

## Статья / Case Study

### Контекст проекта

MagicMusicCRM был создан для Magic Music - сети музыкальных школ, которой нужна была единая система для операционной работы: клиенты, преподаватели, администраторы, управляющие, расписание, оплаты, коммуникации и контроль учебного процесса.

Изначально проект развивался с Supabase-бэкендом, но production-условия потребовали архитектурного перехода. Продукту нужна была стабильная работа из РФ, полный контроль над авторизацией и файлами, серверная модель прав доступа и инфраструктура, которую можно развивать независимо от ограничений BaaS-платформы.

В результате я перевел проект на собственный backend: Flutter-приложение стало API-клиентом, а бизнес-логика, RBAC, realtime, файлы, миграции и аудит переехали в NestJS/PostgreSQL backend на VPS Selectel. По вводным владельца, продукт уже запущен в production и опубликован в Google Play/App Store.

### Моя роль

Я выступал как solo architect и full-stack developer:

- спроектировал продуктовую и техническую архитектуру;
- реализовал Flutter-клиент и NestJS backend;
- спроектировал PostgreSQL-схему и цепочку миграций;
- реализовал auth, RBAC, CRM API, мессенджер, файлы, уведомления и аналитику;
- построил миграционный контур из Supabase и HolliHop;
- перенес данные старой CRM школы в собственную PostgreSQL-базу;
- провел performance-аудит и спроектировал оптимизацию горячих SQL/DTO путей;
- настроил VPS runtime, Docker/Caddy, бэкапы, restore/rollback runbooks;
- подготовил release gates, smoke-тесты, security gates и документацию;
- вел delivery через Linear: эпики, фазы, acceptance gates, статусы и evidence-driven закрытие задач;
- использовал AI-агентов Antigraviti, Codex и Claude Code для ускорения разработки, ревью, QA, аудитов и документирования.

Ключевой момент: AI-агенты использовались как force multiplier, но архитектурные решения, бизнес-правила, acceptance criteria, интеграция и production-проверки оставались под моим контролем.

### Что умеет продукт

MagicMusicCRM закрывает полный операционный цикл музыкальной школы:

- регистрация, вход, OTP, legal consent, onboarding и удаление аккаунта;
- роли client, teacher, admin, manager, system_admin;
- лиды, статусы, kanban, карточка клиента, конвертация лида в ученика;
- ученики, преподаватели, филиалы, аудитории, группы и семейные связи;
- расписание, уроки, посещаемость, конфликт-чек и переносы;
- оплаты, долги, ожидаемые платежи, расходы, абонементы и финансовые отчеты;
- домашние задания с файлами и клиентскими отправками;
- клиентский кабинет с уроками, оплатами, абонементами, ДЗ и прогрессом;
- мессенджер с direct/admin/group/channel потоками;
- голосовые, файловые и image attachments через приватное backend-хранилище;
- уведомления, broadcast, email через Resend с SMTP fallback и SMS-канал через МТС Exolve;
- управленческая аналитика: финансы, воронка, филиалы, SLA чатов, источники, качество данных, активность.

Безопасность не завязана на UI. Backend является источником истины для прав доступа, ролей, владения данными и доступа к файлам.

### Архитектура

Текущая архитектура - owned v3 backend:

```text
Flutter app
  -> HTTPS REST API
  -> Socket.IO realtime

NestJS API
  -> PostgreSQL app schema
  -> Redis
  -> private file storage
  -> notification providers
  -> audit logs and security gates

Operations
  -> Docker Compose
  -> Caddy TLS reverse proxy
  -> encrypted backups
  -> restore and rollback runbooks
```

Flutter использует Riverpod для state management, Dio для REST, Socket.IO client для realtime и secure storage для сессий. Backend построен на NestJS 11, TypeScript, DTO validation, guards, policies, audit logging и PostgreSQL migrations.

По текущему состоянию репозитория backend содержит 10 контроллеров, 200+ route decorators, 49 `up`-миграций PostgreSQL и отдельные модули для CRM, messenger, analytics, auth, profile, files, legal, notifications, settings и health.

### Миграция с Supabase на собственный backend

Самая сложная инженерная часть проекта - заменить Supabase runtime без потери функциональности и истории данных.

Для этого я построил полный migration/cutover контур:

- deterministic export из Supabase;
- transform/import pipeline в новую PostgreSQL-схему;
- импорт storage и маппинг приватных файлов;
- dry-run отчеты с row counts и integrity checks;
- staging rehearsals с rollback-сценарием;
- smoke-тесты для auth, CRM, messenger, files, legal и notifications;
- Flutter cutover с прямого Supabase SDK на typed service layer поверх Magic Music API.

После cutover Supabase остался только как legacy export/import reference, а не как runtime-зависимость приложения.

### Импорт старой CRM HolliHop

Отдельный большой пласт проекта - перенос данных из старой CRM школы HolliHop в собственную PostgreSQL-базу. Это был не "ручной перенос таблиц", а безопасный импортный pipeline с dry-run режимом, источниками, отчетами, батчами, проверкой потерь данных и защитой от повторного запуска.

Что было сделано:

- разработан `hollihop-import` pipeline для чтения архивных и live-источников HolliHop;
- добавлен dry-run режим по умолчанию, а `apply` требует явного флага;
- импорт закрыт backup gate: сначала зашифрованный backup, затем dry-run, затем review отчета;
- импортируются филиалы, аудитории, статусы лидов, преподаватели, ученики, лиды, группы, уроки, участия в группах и платежи;
- сохранены HolliHop-derived поля в CRM custom fields для студентов, лидов и преподавателей;
- добавлены import audit/source records, batch reports, duplicate candidates и field-loss visibility;
- учтены особенности legacy-данных: телефоны, email, статусы, расписание, группы, платежи, связи lead/student.

Измеримые результаты по HolliHop:

| Источник / проверка | Объем |
|---|---:|
| Archive QA: students | 922 |
| Archive QA: leads | 1,736 |
| Archive QA: education units | 2,034 |
| Archive QA: group memberships | 1,090 |
| Archive QA: payments | 2,709 |
| DB-backed dry-run: planned lessons | 22,839 |
| DB-backed dry-run: planned lesson participations | 22,778 |
| DB-backed dry-run: duplicate candidates | 2,070 |
| Live HolliHop validate-only: students | 1,025 |
| Live HolliHop validate-only: leads | 1,944 |
| Live HolliHop validate-only: education units | 2,264 |
| Live HolliHop validate-only: memberships | 1,211 |
| Live HolliHop validate-only: payments | 3,166 |

После импорта production DB snapshot уже содержал тысячи CRM-записей: 1,953 students, 3,674 leads, 4,292 groups, 2,300 group_students, 35,132 lessons и 5,806 payments. Это потребовало не только загрузить данные, но и адаптировать UI/API под реальные объемы, а не под демо-датасет.

### Realtime и мессенджер

Мессенджер в проекте - это не простой чат-компонент. Он включает:

- direct, group, channel и administration chats;
- Socket.IO gateway с JWT-auth и server-authorized room joins;
- typing, presence, read state, reactions, pinning, edit/delete и forwarding;
- administration chat как рабочий канал client-to-school;
- файлы, изображения и voice messages через backend file IDs и one-time download tokens;
- fallback polling и targeted refresh, если realtime временно недоступен.

Поздний production-аудит показал, что проблемные сценарии были не в одном UI-баге, а в расхождениях backend policies, realtime fan-out и frontend invalidation. Я расширил coverage событий, добавил fallback-поведение и выровнял operational access для admin/manager согласно реальным бизнес-правилам.

### Уведомления: email, SMTP fallback и SMS

Коммуникационный слой был вынесен на backend, чтобы Flutter не хранил provider secrets и не принимал доверенные решения о доставке.

Реализованный email-контур:

- Resend API как основной email provider;
- SMTP fallback поверх TLS, если Resend недоступен или не сконфигурирован;
- email outbox и worker-drain модель;
- exponential retry до 5 попыток;
- защита от SMTP header injection;
- audit/metadata по результатам доставки;
- smoke evidence с отправкой через `resend/sent`.

Для SMS-канала в проектном контуре использовался МТС Exolve как провайдер для SMS/OTP-коммуникаций. В публичное портфолио это стоит оставлять как "интеграция/использование SMS-провайдера МТС Exolve", без публикации ключей, sender IDs, шаблонов и внутренних endpoint-ов.

### Security и надежность

В проекте security и recovery были частью архитектуры, а не финальным полишем.

Реализовано:

- server-side RBAC и ownership policies;
- refresh-token rotation и reuse detection;
- OTP, password reset и logout-all;
- legal consent gate и account deletion lifecycle;
- private file storage вне public web root;
- one-time signed download tokens;
- audit events для чувствительных операций;
- request IDs и log redaction;
- dependency/security gates;
- encrypted backups и restore drills;
- rollback runbooks и smoke checks.

В релизных артефактах зафиксированы backend typecheck/build/tests, Flutter analyze/tests, dependency audit, security gate, realtime smoke и private file smoke. Последний записанный полный backend gate: 43 suites / 432 tests. Последний записанный Flutter gate: `flutter analyze` clean и 233 tests.

### Performance и production-аудиты

Я провел performance-аудит live staging API. Он показал, что проблема perceived latency не сводится к "медленному серверу": большинство одиночных REST-запросов укладывались быстрее 500 ms, а отправка сообщения и realtime delivery в smoke-сценариях занимали десятки миллисекунд.

Часть baseline-метрик:

| Экран / действие | Замер |
|---|---:|
| Health endpoint | 0.004 sec |
| Overview `/crm/overview` | 0.011 sec |
| Finance report `/crm/reports/finance` | 0.023 sec |
| Lead board `/crm/leads/board` | 0.045 sec |
| Schedule day matrix | 0.022 sec |
| Student card bundle | 0.092 sec |
| Lead card bundle | 0.024 sec |
| Chat messages `limit=50` | 0.009 sec |
| Send message REST | 0.013 sec |
| Realtime client->admin message | 0.052 sec |
| Realtime admin->client message | 0.060 sec |
| Create task | 0.055 sec |
| Create lesson | 0.065 sec |

Основные bottlenecks оказались продуктово-архитектурными:

- screen waterfalls: экран открывает несколько endpoint-ов каскадом;
- heavy DTO/payload для расписания и students board;
- отдельные SQL hot paths в profile diagnostics и room availability;
- слишком широкие realtime refetch-паттерны;
- frontend rebuild/refetch, из-за которых быстрый backend может ощущаться медленным.

Итогом стал конкретный план оптимизации: lightweight DTO, lazy loading секций, targeted realtime updates, query rewrites, frontend caching и метрики p50/p95 по ключевым ролям и экранам.

### Оптимизация PostgreSQL и backend payload

На реальном staging baseline сервер не был уперт в CPU/RAM/disk: CPU idle около 95%, доступной RAM около 6.8 GB из 7.9 GB, cache hit PostgreSQL около 99.96%, deadlocks 0. Поэтому первым фокусом была не замена VPS, а оптимизация формы запросов и загрузки экранов.

Выявленные hot paths:

- `/admin/profiles?limit=100` - 471 ms live, SQL 440 ms из-за per-profile subplans и phone-normalization в join/filter;
- `/crm/rooms/availability` - 189 ms live, SQL 178 ms из-за многократных overlap scans по lessons;
- `/crm/students/search?limit=500` - 224 ms и payload 498 KB;
- month schedule matrix - 707 KB payload;
- lead board - 169 KB payload.

План оптимизации БД и API:

- rewrite `/admin/profiles`: lightweight list по умолчанию, link/candidate counts отдельным expansion/detail endpoint;
- rewrite room availability через bounded lessons CTE вместо повторного full scan;
- partial covering indexes по active lessons для room/teacher overlap checks;
- stored/indexed normalized phone вместо regexp-normalization per row;
- paginated/cursor board endpoints для students/leads;
- split DTO на list/detail/section payload;
- lazy loading вторичных секций карточки клиента;
- targeted realtime invalidation вместо full tab refetch.

Целевые performance budgets: обычные list endpoints p95 <= 500 ms, тяжелые экраны p95 <= 1000-2000 ms, save mutations p95 <= 800-1000 ms, month schedule payload <= 150-250 KB.

### Редизайн v7

После backend independence проект перешел в редизайн v7. Важное решение: не переписывать приложение с нуля, а переносить утвержденный дизайн на существующее production-приложение.

Принципы редизайна:

- backend остается источником истины;
- API contracts не ломаются;
- каждый endpoint сохраняет UI-дом;
- frontend-only фазы не трогают `server/`;
- каждое окно проходит wire-to-service checklist;
- RBAC проверяется по матрице всех ролей.

Это важно, потому что проект уже имеет глубокую операционную функциональность. Красивый prototype недостаточен, если при переносе потеряются channels, custom CRM fields, legal flows, account deletion, analytics, private files, role-specific actions или realtime behavior.

### Delivery management через Linear

Проект велся не как хаотичный набор задач, а через backlog и acceptance gates в Linear. Для backend independence были заведены фазы S0-S8, milestone-задачи и Linear issues. Для редизайна v7 создан мегаэпик KVA-192 с 10 фазами-подэпиками: P0-P7, включая RBAC/nav/auth, schedule, clients, chat, reports/finance/tasks/users/settings, subscription catalog, homework with files, data cleanup и on-device acceptance.

Linear использовался для:

- декомпозиции архитектурного перехода на фазы;
- связи задач с acceptance criteria и evidence;
- tracking статусов In Review/Done;
- синхронизации локальных docs, roadmap и release gates;
- контроля, какие фазы имеют право трогать backend, а какие должны быть frontend-only.

### Результаты в цифрах

По состоянию репозитория и последних audit/evidence документов:

- production Flutter + NestJS architecture;
- 140 Dart-файлов в `lib`;
- 218 TypeScript-файлов в `server/src`;
- 49 PostgreSQL `up`-миграций;
- 10 backend controllers;
- 200+ backend route decorators;
- Supabase export: 69 tables, 23,188 rows, 36 storage objects, 0 warnings;
- v3 import dry-run: 22,709 source rows, 25,002 planned rows, 1,105/1,105 messages covered;
- HolliHop archive import QA: 922 students, 1,736 leads, 2,034 education units, 2,709 payments;
- HolliHop DB-backed dry-run: 22,839 planned lessons, 22,778 lesson participations, 2,070 duplicate candidates;
- production DB snapshot: 1,953 students, 3,674 leads, 35,132 lessons, 5,806 payments;
- 43 backend test suites / 432 tests в последнем recorded full gate;
- 233 Flutter tests в последнем recorded Flutter gate;
- common REST endpoints mostly < 500 ms on staging baseline;
- realtime message smoke around 52-60 ms;
- PostgreSQL cache hit около 99.96% на performance audit snapshot;
- private file API с one-time download tokens;
- realtime smoke harness для REST + Socket.IO event matching;
- Resend primary email provider + SMTP fallback;
- SMS-провайдер МТС Exolve для SMS/OTP-коммуникаций;
- Linear backlog: v3 backend independence phases + v7 mega-epic KVA-192;
- VPS runtime на Docker Compose + Caddy + PostgreSQL + Redis;
- encrypted backups, restore drill и rollback runbooks;
- Google Play AAB release evidence в проектной документации.

### Что проект показывает работодателю/клиенту

MagicMusicCRM показывает, что я умею доводить реальный бизнес-продукт до production, а не только писать отдельные фичи.

Проект демонстрирует опыт в:

- product thinking и моделировании бизнес-правил;
- full-stack mobile/backend engineering;
- backend authorization и private data handling;
- realtime systems и failure-mode design;
- миграции с BaaS на owned infrastructure;
- импорт legacy CRM с dry-run/apply safety и data-quality reporting;
- PostgreSQL/API performance audit и оптимизацию запросов/DTO;
- production deployment и operations;
- delivery management через Linear;
- test gates, release evidence и incident-oriented documentation;
- практической orchestration AI-агентов для ускорения solo development.

## Готовые bullets для резюме

- Разработал и запустил production CRM + мессенджер для сети музыкальных школ как solo architect/full-stack developer: Flutter client, NestJS backend, PostgreSQL schema, realtime, private files, auth, analytics, Linear tracking и release operations.
- Перевел проект с Supabase runtime на собственный NestJS/PostgreSQL backend на VPS Selectel: 69 exported tables, 23,188 rows, storage migration, dry-runs, smoke tests, backups и rollback runbooks.
- Выполнил импорт данных старой CRM HolliHop в собственную БД: students/leads/groups/lessons/payments, dry-run/apply pipeline, import reports, duplicate candidates и data-quality checks.
- Реализовал secure role-based workflows для client, teacher, admin, manager и system_admin с backend-enforced RBAC, ownership policies, audit events и private file access.
- Построил messenger-инфраструктуру на Socket.IO: direct/group/channel/admin chats, read states, reactions, pinned messages, voice/files/images и fallback refresh behavior.
- Настроил notification stack: Resend primary email provider, SMTP fallback, email outbox/retry worker и SMS-канал через МТС Exolve.
- Провел performance-аудит и спроектировал оптимизацию PostgreSQL/API: common REST <500 ms, realtime 52-60 ms, выявлены hot paths `/admin/profiles`, room availability, heavy schedule/students payloads.
- Настроил production gates: backend typecheck/build/tests, Flutter analyze/tests, security gate, realtime smoke, private file smoke, encrypted backups и restore/rollback runbooks.
- Использовал AI-агентов как engineering force multiplier для implementation, code review, QA, documentation и migration work, сохранив контроль над архитектурой, acceptance criteria и production verification.

## Компактная версия для HH / LinkedIn

MagicMusicCRM - production CRM и мессенджер для сети музыкальных школ. Solo full-stack проект с AI-assisted workflow: Flutter/Dart client, NestJS/TypeScript backend, PostgreSQL, Redis, Socket.IO realtime, private file storage, Resend/SMTP, МТС Exolve SMS, Docker/Caddy deployment на VPS Selectel. Реализованы auth, OTP, refresh rotation, RBAC, client/teacher/admin/manager workflows, CRM, лиды, расписание, оплаты, абонементы, ДЗ, мессенджер, файлы, уведомления, аналитика, legal consent и account deletion. Проведен переход с Supabase runtime на owned backend и импорт старой CRM HolliHop: 23,188 rows Supabase export, HolliHop dry-run на 22,839 lessons / 22,778 participations / 2,070 duplicate candidates, production DB snapshot 35,132 lessons / 5,806 payments. Проведен performance-аудит: common REST mostly <500 ms, realtime 52-60 ms, PostgreSQL cache hit около 99.96%, дальнейший план оптимизации через DTO split, query rewrites и targeted realtime invalidation. Delivery велся через Linear backlog и фазовые acceptance gates. Последние recorded gates: 43 backend suites / 432 tests, Flutter analyze clean и 233 Flutter tests.

## Примечания перед публичной публикацией

- Добавь реальные ссылки на Google Play и App Store вручную, если хочешь публиковать текст наружу.
- Не публикуй внутренние API hostnames, IP, smoke account IDs, backup artifact names или приватные operational logs.
- Для рекрутера лучше оставить "Короткое описание", "Готовые bullets" и "Компактную версию".
- Для технического портфолио лучше оставить архитектуру, миграцию, security, realtime и performance sections.
