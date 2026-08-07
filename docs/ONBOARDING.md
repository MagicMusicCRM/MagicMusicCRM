# Agent Onboarding Guide - MagicMusicCRM

Дата: 2026-06-17  
Источник карты кода: `.understand-anything/knowledge-graph.json`  
Analyze commit: `bf4c3ed723a7d7188e9a035992b1b96b62d43b28`  
Язык гайда: `ru`

Этот документ предназначен для новых ИИ-агентов и разработчиков, которым нужно быстро войти в проект без потери контекста, правил и текущих рисков.

## 1. Что это за проект

**MagicMusicCRM** - Flutter CRM для операционной работы школы Magic Music. Клиент работает на Flutter/Riverpod, backend версии v3 построен как собственный NestJS/PostgreSQL API с Redis, Socket.IO realtime, приватным file API, CRM-модулями, auth/RBAC, staging-инфраструктурой и release/security документацией.

Текущая архитектурная миссия проекта: **Backend Independence**. Проект уходит от runtime-зависимости от Supabase Cloud к собственному backend API. Supabase допускается как legacy/export source, но новые runtime-потоки клиента должны идти через `Magic*` API services и v3 backend.

Основной stack:

| Зона | Технологии |
|---|---|
| Client | Dart, Flutter, Riverpod |
| Backend | NestJS, TypeScript |
| Data | PostgreSQL, SQL migrations |
| Realtime | Socket.IO, `/realtime` |
| Cache / Queue support | Redis |
| Files | Private local storage behind backend authorization |
| Ops | Docker, Docker Compose, Caddy, Selectel staging |
| Quality | Flutter tests, backend Jest tests, smoke scripts, security gates |

Understand-Anything snapshot:

| Метрика | Значение |
|---|---:|
| Nodes | 1885 |
| Edges | 2596 |
| Layers | 9 |
| Guided tour steps | 10 |
| File nodes | 377 |
| Class nodes | 445 |
| Function nodes | 663 |
| Document nodes | 160 |
| Config nodes | 40 |

## 2. Первые 10 минут агента

Любой агент должен начинать не с кода, а с восстановления проектного состояния:

1. Прочитать `AGENTS.md`.
2. Найти максимальную версию `.anws/vN`. На 2026-06-17 актуальна `.anws/v3`.
3. Прочитать `.anws/v3/05_TASKS.md`.
4. Проверить `git status --short` и не откатывать чужие изменения.
5. Если задача похожа на workflow из `AGENTS.md`, сначала прочитать соответствующий процесс.
6. Определить активный task/milestone перед изменениями.
7. Не коммитить env-файлы, ключи, backup-архивы, Firebase private key, HolliHop key, Supabase service role, DB URL с паролями или Telegram token.
8. Для UI помнить: весь пользовательский текст на русском.
9. Для Flutter помнить: глобальное состояние через Riverpod/providers/services, не через локальный хаос в виджетах.
10. Для данных помнить: новые runtime-потоки не должны писать напрямую в Supabase из UI.

Короткая команда восстановления:

```powershell
Get-Content -Raw AGENTS.md
Get-Content -Raw .anws/v3/05_TASKS.md
git status --short
```

## 3. Текущее состояние проекта

Актуальная архитектура: `.anws/v3` - **Backend Independence**.

Закрытые крупные этапы:

| Wave | Смысл | Статус |
|---|---|---|
| S0 | Architecture and Linear Backlog | Закрыто |
| S1 | Staging Infrastructure Rehearsal | Закрыто |
| S2-S3 | Backend Core and Auth Boundary | Закрыто |
| S4 | Feature APIs | Закрыто |
| S5 | Migration Pipeline | Закрыто |
| S6 | Flutter Cutover | Почти закрыто, `INT-S6` открыт |
| S7 | Security and Launch | Pre-release gates пройдены, production gates открыты |
| S8 | Desktop UX/UI Stabilization | Активная зона работ |

Главная активная product-quality зона: **S8 Desktop UX/UI Stabilization**. Последний Windows manager audit нашел trust failures в Schedule, Tasks FAB, lead columns modal и нескольких manager-facing поверхностях.

Открытые задачи S8:

| Task | Смысл |
|---|---|
| `T8.1` | Явные loading/empty/error/retry states для schedule |
| `T8.2` | Надежный task creation flow и видимый feedback |
| `T8.3` | Lead board, pipeline config, пустой lead-columns modal |
| `T8.4` | Safeguards для high-risk manager actions и reporting clarity |
| `INT-S8` | Повторный Windows manager UX audit без P0/P1 trust failures |

Открытые launch blockers:

| Gate | Остаток |
|---|---|
| `INT-S6` | Stable Android smoke, private file upload/download, real account deletion |
| `T7.3` | Production cutover rehearsal, live DB-backed HolliHop dry-run |
| `T7.4` | Production cutover after user-approved freeze window |
| `INT-S7` | Final production launch acceptance |

## 4. Системные границы

| Boundary | Ответственность |
|---|---|
| `SYS-APP` | Flutter client, Russian UI, Riverpod state, API/WebSocket integration |
| `SYS-API` | NestJS REST API, validation, auth guards, RBAC, audit |
| `SYS-AUTH` | Email/password, OTP, refresh rotation, password reset, optional Google OAuth |
| `SYS-DATA` | PostgreSQL schema, migrations, scoped repositories, constraints |
| `SYS-MSG` | Messenger REST плюс WebSocket realtime |
| `SYS-FILES` | Private file storage and signed downloads |
| `SYS-OPS` | Docker runtime, reverse proxy, TLS, backups, monitoring, runbooks |
| `SYS-SEC` | Security gates, actor matrix, scans and launch evidence |

## 5. Архитектурные слои

### Flutter-клиент

Назначение: Dart/Flutter UI, Riverpod state, клиентские API-сервисы и feature screens.

Ключевые файлы:

| Файл | Зачем читать |
|---|---|
| `lib/main.dart` | Точка входа Flutter runtime |
| `lib/core/router/app_router.dart` | Навигация и role-aware routing |
| `lib/core/api/magic_api_client.dart` | Базовый HTTP-клиент v3 API |
| `lib/core/api/magic_api_providers.dart` | Provider wiring для API слоя |
| `lib/core/api/magic_token_store.dart` | Хранение access/refresh токенов |
| `lib/features/auth/data/services/magic_auth_service.dart` | Auth контракты клиента |
| `lib/core/services/magic_crm_service.dart` | CRM API client boundary |
| `lib/core/services/magic_messenger_service.dart` | Messenger REST API client boundary |
| `lib/core/services/magic_realtime_service.dart` | Socket.IO `/realtime` client |
| `lib/core/services/chat_attachment_service.dart` | Private files / attachments через v3 `/files` |
| `lib/core/providers/chat_providers.dart` | Shared messenger providers |

Manager-facing UI, особенно важный для S8:

| Файл | Зона риска |
|---|---|
| `lib/features/manager/presentation/widgets/leads_widget.dart` | Lead board, pipeline UX, lead actions |
| `lib/features/manager/presentation/widgets/manage_statuses_dialog.dart` | Lead columns / statuses modal |
| `lib/features/manager/presentation/widgets/tasks_widget.dart` | Tasks list and create flow |
| `lib/features/manager/presentation/widgets/finance_widget.dart` | Payments and finance form guidance |
| `lib/features/manager/presentation/widgets/reports_widget.dart` | Reporting copy and activity clarity |
| `lib/features/manager/presentation/widgets/user_roles_widget.dart` | Role/status mutation clarity |
| `lib/features/admin/presentation/widgets/schedule_widget.dart` | Schedule state transparency |

Messenger UI:

| Файл | Зачем читать |
|---|---|
| `lib/features/messenger/presentation/screens/messenger_screen.dart` | Основной messenger surface |
| `lib/core/widgets/telegram/chat_info_dialog.dart` | Chat details, media/files, channel edits |
| `lib/core/widgets/telegram/message_bubble.dart` | Rendering message attachments and states |
| `lib/core/widgets/telegram/message_input.dart` | Message composition |

### Backend API

Назначение: NestJS REST/WebSocket backend, auth/RBAC, CRM, messenger, files, notifications и server-side policies.

Ключевые файлы:

| Файл | Зачем читать |
|---|---|
| `server/src/main.ts` | NestJS bootstrap |
| `server/src/app.module.ts` | Сборка модулей backend |
| `server/src/config/env.validation.ts` | Runtime env validation |
| `server/src/common/security/jwt-auth.guard.ts` | Auth boundary для REST |
| `server/src/auth/auth.service.ts` | Signup/login/session auth logic |
| `server/src/auth/session.service.ts` | Refresh rotation, session lifecycle |
| `server/src/auth/roles.guard.ts` | Role-based access |
| `server/src/audit/audit.service.ts` | Audit events |
| `server/src/db/database.service.ts` | PostgreSQL access boundary |
| `server/src/crm/crm.controller.ts` | CRM REST contract |
| `server/src/crm/crm.service.ts` | CRM business logic |
| `server/src/crm/crm.policy.ts` | CRM authorization rules |
| `server/src/messenger/messenger.controller.ts` | Messenger REST contract |
| `server/src/messenger/messenger.service.ts` | Messenger business logic |
| `server/src/messenger/realtime.gateway.ts` | Socket.IO `/realtime` gateway |
| `server/src/files/files.controller.ts` | File REST contract |
| `server/src/files/files.service.ts` | Private file lifecycle |
| `server/src/files/files.policy.ts` | File read/write authorization |
| `server/src/legal/legal.service.ts` | Legal consent and deletion requests |
| `server/src/notifications/notifications.service.ts` | Notifications and provider fallback |

### Слой данных и миграций

Назначение: PostgreSQL schema, migrations, Supabase export/import и HolliHop migration-compatible данные.

Ключевые файлы:

| Файл | Зачем читать |
|---|---|
| `server/db/migrations/*.sql` | История v3 schema evolution |
| `server/db/migrations/0001_core_identity.up.sql` | Core identity baseline |
| `server/db/migrations/0002_profile_crm.up.sql` | Profiles and CRM baseline |
| `server/db/migrations/0003_messenger.up.sql` | Messenger schema |
| `server/db/migrations/0004_files.up.sql` | Private file schema |
| `server/db/migrations/0010_lead_management.up.sql` | Lead management |
| `server/db/migrations/0011_auth_abuse_limits.up.sql` | Auth abuse lockouts |
| `server/src/migration/supabase-export.ts` | Supabase export pipeline |
| `server/src/migration/v3-import.ts` | v3 import pipeline |
| `server/src/migration/hollihop-import.ts` | HolliHop import pipeline |
| `docs/runbooks/supabase-export.md` | Export runbook |
| `docs/runbooks/v3-import.md` | Import runbook |
| `docs/runbooks/storage-import.md` | File migration runbook |
| `docs/runbooks/hollihop-staging-dry-run.md` | HolliHop dry-run runbook |

Правило: migration/import scripts могут работать с чувствительными данными. Любой live/apply режим требует явного намерения пользователя, backup evidence и проверки env.

### Платформенные runners

Назначение: platform embedding для Flutter.

| Путь | Назначение |
|---|---|
| `android/` | Android runner, Gradle config |
| `ios/` | iOS runner |
| `macos/` | macOS runner |
| `windows/` | Windows runner для desktop release/smoke |
| `linux/` | Linux runner |

Обычно эти файлы не трогают для product/API задач, кроме build/signing/platform smoke работ.

### Инфраструктура и Ops

Назначение: staging compose, deployment, backup, monitoring.

| Файл | Зачем читать |
|---|---|
| `infra/staging/docker-compose.yml` | Staging runtime: API, PostgreSQL, Redis, reverse proxy |
| `infra/staging/Caddyfile` | TLS/reverse proxy config |
| `infra/staging/README.md` | Staging notes |
| `infra/scripts/bootstrap-ubuntu-24.04.sh` | Host bootstrap |
| `infra/scripts/backup-staging.sh` | Encrypted staging backup |
| `infra/scripts/restore-staging.sh` | Restore drill |
| `infra/scripts/monitor-staging.sh` | Monitoring checks |
| `scripts/hollihop_staging_dry_run.ps1` | Guarded HolliHop dry-run helper |
| `scripts/android_real_device_smoke.ps1` | Android real-device smoke helper |

Live API: `https://api.magicmusiccrm.ru/api`.

### Тесты и quality gates

| Зона | Команды |
|---|---|
| Flutter static analysis | `flutter analyze` |
| Flutter tests | `flutter test` |
| Flutter integration smoke | `flutter test integration_test/app_launch_smoke_test.dart -d windows` |
| Backend typecheck | `cd server; npm run typecheck` |
| Backend tests | `cd server; npm test` |
| Backend build | `cd server; npm run build` |
| Backend audit | `cd server; npm audit --audit-level=moderate` |
| Realtime staging smoke | `cd server; npm run smoke:realtime` |
| Staging compose config | `cd infra/staging; docker compose --env-file .env config -q` |

Use targeted tests first for a narrow change, then broader gates when touching shared API/services/auth/data.

### Архитектурная документация

| Файл | Роль |
|---|---|
| `AGENTS.md` | Якорь проекта, протоколы, текущее состояние |
| `.anws/v3/01_PRD.md` | Product requirements для v3 |
| `.anws/v3/02_ARCHITECTURE_OVERVIEW.md` | Architecture overview |
| `.anws/v3/03_ADR/` | Архитектурные решения |
| `.anws/v3/04_SYSTEM_DESIGN/` | Детальный системный дизайн |
| `.anws/v3/05_TASKS.md` | Активный backlog и task status |
| `.anws/v3/08_CUTOVER_READINESS_REPORT.md` | Migration/cutover readiness |
| `.anws/v3/09_S7_RELEASE_EVIDENCE.md` | Security/release evidence |
| `docs/audits/windows-ux-ui-2026-06-16/report.md` | Последний desktop UX/UI audit |

## 6. Ключевые концепции проекта

### Backend Independence

v3 переводит runtime с Supabase Cloud на собственный NestJS/PostgreSQL backend. Для нового кода baseline такой:

- Flutter UI вызывает `Magic*Service`.
- `Magic*Service` вызывает `MagicApiClient`.
- `MagicApiClient` ходит в `MAGIC_API_BASE_URL`.
- Backend выполняет validation, RBAC, audit и data access.
- Direct Supabase calls из UI/build handlers запрещены.

### Service Boundary на Flutter

Правильное место для API-контрактов - `lib/core/services/*` и feature-specific data services. Виджеты должны быть тонкими: state, layout, user intent, feedback. Сетевые детали, DTO mapping и error normalization должны жить в services/providers.

### Riverpod as State Boundary

Основной state management - Riverpod. Не добавляйте глобальное состояние через произвольные singleton/stateful hacks. Для shared flows ищите существующие providers:

- `lib/core/api/magic_api_providers.dart`
- `lib/core/providers/chat_providers.dart`
- `lib/features/auth/providers/*`
- feature providers внутри `lib/features/**/providers`

### Russian UI Standard

Весь пользовательский UI-текст должен быть на русском. Код и комментарии - на английском, если нет причины иначе.

### Flat Magic Visual Direction

Проектный дизайн-код:

- Deep Charcoal and Sophisticated Gold.
- Gold anchor: `#C5A059`.
- Без яркого свечения, glossy gradients и декоративной перегруженности.
- Desktop surfaces должны быть спокойными, операционными и предсказуемыми.
- Blank/silent states считаются trust failure.

### Auth, RBAC, Audit

Backend отвечает за trust boundary:

- login/signup/password reset/OTP;
- refresh token rotation and reuse detection;
- role guards;
- ownership checks;
- audit events for privileged writes and sensitive lifecycle actions.

Нельзя полагаться на client-side role checks как на безопасность. Client checks - UX only.

### Private Files

Файлы не должны быть публичными bucket URLs. Модель v3:

- upload через `/files`;
- metadata в DB;
- authorization через `FilesPolicy`;
- download через one-time signed token;
- chat attachments доступны только участникам чата.

### Realtime Messenger

Realtime идет через Socket.IO namespace/path `/realtime`. REST остается источником durable write/read, realtime - доставка событий:

- `room.join`;
- `message.created`;
- `message.updated`;
- typing/presence events;
- channel events where supported.

### Migration Safety

Supabase export, v3 import и HolliHop import - high-risk зона. Default должен быть dry-run. Любой apply/live режим требует:

- явного task context;
- backup evidence;
- проверенного env;
- post-run report;
- rollback/smoke plan.

## 7. Guided Tour для нового агента

Следуйте этому маршруту, если нужно полностью понять проект.

### Step 1 - Project anchor

Прочитайте:

- `AGENTS.md`
- `.anws/v3/05_TASKS.md`
- `.anws/v3/02_ARCHITECTURE_OVERVIEW.md`

Цель: понять текущую фазу, правила работы и границы систем.

### Step 2 - Flutter startup

Прочитайте:

- `lib/main.dart`
- `lib/core/router/app_router.dart`
- `lib/core/constants/env.dart`

Цель: понять, как приложение стартует, выбирает API base URL и маршрутизирует роли.

### Step 3 - Client API services

Прочитайте:

- `lib/core/api/magic_api_client.dart`
- `lib/core/api/magic_api_providers.dart`
- `lib/features/auth/data/services/magic_auth_service.dart`
- `lib/core/services/magic_crm_service.dart`
- `lib/core/services/magic_messenger_service.dart`
- `lib/core/services/magic_realtime_service.dart`
- `lib/core/services/chat_attachment_service.dart`

Цель: понять client/backend contract boundary.

### Step 4 - CRM UI flows

Прочитайте:

- `lib/features/manager/presentation/screens/manager_dashboard_screen.dart`
- `lib/features/manager/presentation/widgets/leads_widget.dart`
- `lib/features/manager/presentation/widgets/tasks_widget.dart`
- `lib/features/manager/presentation/widgets/finance_widget.dart`
- `lib/features/manager/presentation/widgets/reports_widget.dart`

Цель: понять operator workflows и текущую S8 UX-поверхность.

### Step 5 - Backend bootstrap

Прочитайте:

- `server/src/main.ts`
- `server/src/app.module.ts`
- `server/src/config/env.validation.ts`
- `server/src/health/health.controller.ts`

Цель: понять NestJS runtime, modules, config и health boundary.

### Step 6 - Auth and RBAC

Прочитайте:

- `server/src/auth/auth.service.ts`
- `server/src/auth/session.service.ts`
- `server/src/auth/roles.guard.ts`
- `server/src/common/security/jwt-auth.guard.ts`
- `server/src/audit/audit.service.ts`

Цель: понять trust boundary, token lifecycle, roles и audit.

### Step 7 - Feature APIs

Прочитайте:

- `server/src/crm/crm.controller.ts`
- `server/src/crm/crm.service.ts`
- `server/src/messenger/messenger.controller.ts`
- `server/src/messenger/messenger.service.ts`
- `server/src/messenger/realtime.gateway.ts`
- `server/src/files/files.controller.ts`
- `server/src/files/files.service.ts`
- `server/src/legal/legal.service.ts`

Цель: понять основные business contracts.

### Step 8 - Data and imports

Прочитайте:

- `server/db/migrations/`
- `server/src/migration/supabase-export.ts`
- `server/src/migration/v3-import.ts`
- `server/src/migration/hollihop-import.ts`
- `docs/runbooks/v3-import.md`
- `docs/runbooks/hollihop-staging-dry-run.md`

Цель: понять schema, migration compatibility и cutover path.

### Step 9 - Staging infrastructure

Прочитайте:

- `infra/staging/docker-compose.yml`
- `infra/staging/Caddyfile`
- `infra/scripts/backup-staging.sh`
- `infra/scripts/restore-staging.sh`
- `infra/scripts/monitor-staging.sh`

Цель: понять реальное окружение `api.magicmusiccrm.ru`.

### Step 10 - Acceptance and smoke

Прочитайте:

- `integration_test/app_launch_smoke_test.dart`
- `docs/runbooks/flutter-integration-smoke.md`
- `docs/runbooks/android-real-device-smoke.md`
- `server/src/smoke/realtime-smoke.ts`
- `.anws/v3/09_S7_RELEASE_EVIDENCE.md`

Цель: понять, какие gates доказывают готовность изменений.

## 8. File Map по задачам

### Если чините S8 Schedule

Начать с:

- `docs/audits/windows-ux-ui-2026-06-16/report.md`
- `lib/features/admin/presentation/widgets/schedule_widget.dart`
- `lib/core/widgets/skeletons.dart`
- `lib/core/services/magic_crm_service.dart`

Что проверить:

- есть ли видимые loading/empty/error/retry states;
- не остается ли пустая сетка без объяснения;
- period/header controls всегда видимы;
- ошибки API превращаются в actionable UI.

### Если чините S8 Tasks

Начать с:

- `lib/features/manager/presentation/widgets/tasks_widget.dart`
- `lib/core/services/magic_crm_service.dart`
- `test/core/services/magic_crm_service_test.dart`

Что проверить:

- FAB сразу открывает create flow или показывает pending state;
- prefetch failures видны пользователю;
- disabled submit объяснен;
- success/error feedback не теряется.

### Если чините S8 Leads

Начать с:

- `lib/features/manager/presentation/widgets/leads_widget.dart`
- `lib/features/manager/presentation/widgets/manage_statuses_dialog.dart`
- `lib/features/manager/presentation/widgets/lead_detail_dialog.dart`
- `lib/features/manager/presentation/providers/leads_providers.dart`
- `lib/core/services/magic_crm_service.dart`

Что проверить:

- lead columns modal не бывает пустым серым телом;
- statuses list/edit states inspectable;
- horizontal board navigation очевидна на desktop;
- destructive/status actions имеют feedback.

### Если чините Finance / Reports / User Roles

Начать с:

- `lib/features/manager/presentation/widgets/finance_widget.dart`
- `lib/features/manager/presentation/widgets/reports_widget.dart`
- `lib/features/manager/presentation/widgets/user_roles_widget.dart`
- `lib/core/services/magic_crm_service.dart`

Что проверить:

- high-risk mutations требуют явного intent;
- отчеты используют человекочитаемый текст;
- формы объясняют blocked submit states;
- визуальные токены соответствуют Flat Magic.

### Если чините Messenger

Начать с:

- `lib/features/messenger/presentation/screens/messenger_screen.dart`
- `lib/core/providers/chat_providers.dart`
- `lib/core/services/magic_messenger_service.dart`
- `lib/core/services/magic_realtime_service.dart`
- `server/src/messenger/messenger.service.ts`
- `server/src/messenger/realtime.gateway.ts`

Что проверить:

- REST write succeeded before optimistic assumptions;
- realtime event updates do not duplicate messages;
- room authorization enforced server-side;
- attachments use v3 file IDs, not public URLs.

### Если чините Files

Начать с:

- `lib/core/services/chat_attachment_service.dart`
- `lib/core/widgets/file_attachment_widget.dart`
- `server/src/files/files.service.ts`
- `server/src/files/files.policy.ts`
- `server/db/migrations/0004_files.up.sql`

Что проверить:

- no public storage URL assumptions;
- upload purpose is correct;
- download token is one-time;
- foreign access denied.

### Если чините Auth

Начать с:

- `lib/features/auth/data/services/magic_auth_service.dart`
- `lib/features/auth/providers/magic_auth_provider.dart`
- `server/src/auth/auth.service.ts`
- `server/src/auth/session.service.ts`
- `server/src/auth/auth.controller.ts`
- `server/db/migrations/0011_auth_abuse_limits.up.sql`

Что проверить:

- safe errors;
- refresh rotation/reuse detection;
- logout-all;
- OTP/password reset abuse limits;
- audit events.

## 9. Complexity Hotspots

Understand-Anything не дал числовой рейтинг complexity для всех file-level nodes, но отметил file-level complexity labels вроде `simple`/`moderate`. Практически high-risk зоны определяются blast radius, количеством контрактов и security/data impact.

| Hotspot | Почему осторожно |
|---|---|
| `lib/core/api/magic_api_client.dart` | Shared HTTP behavior, tokens, errors, retries affect all client flows |
| `lib/core/services/magic_crm_service.dart` | Большой CRM contract surface: leads, tasks, finance, reports, schedule |
| `lib/core/services/magic_messenger_service.dart` | Durable messenger contract and DTO mapping |
| `lib/core/services/magic_realtime_service.dart` | Async Socket.IO lifecycle, event ordering, auth path |
| `lib/features/manager/presentation/widgets/leads_widget.dart` | Dense desktop board, many actions, current S8 trust risks |
| `lib/features/manager/presentation/widgets/tasks_widget.dart` | Create flow had silent failure in audit |
| `lib/features/admin/presentation/widgets/schedule_widget.dart` | Current P0 blank/skeleton state risk |
| `server/src/auth/auth.service.ts` | Security-critical credential/session behavior |
| `server/src/auth/session.service.ts` | Refresh rotation and reuse detection |
| `server/src/crm/crm.service.ts` | Core business data and role-scoped writes |
| `server/src/messenger/realtime.gateway.ts` | Realtime auth/authorization and room events |
| `server/src/files/files.policy.ts` | Private file access control |
| `server/src/migration/v3-import.ts` | Data migration integrity and rollback expectations |
| `server/src/migration/hollihop-import.ts` | Live import risk, external API/data mapping |
| `infra/scripts/restore-staging.sh` | Ops recovery path, destructive if misused |

Approach these files with targeted tests and explicit rollback thinking.

## 10. Development Protocol

Before coding:

1. Identify the task ID from `.anws/v3/05_TASKS.md`.
2. Read the relevant architecture/system design docs.
3. Inspect existing patterns with `rg`.
4. Check current git diff for files you will touch.
5. Decide the smallest safe slice.

During coding:

1. Keep changes scoped.
2. Use existing providers/services/contracts.
3. Keep UI text Russian.
4. Preserve Flat Magic design.
5. Do not introduce direct Supabase calls in UI.
6. Do not add unrelated refactors.
7. Do not remove or overwrite user changes.

After coding:

1. Run targeted tests first.
2. Run broader gates based on blast radius.
3. Update task/evidence docs only when the project protocol requires it.
4. Report remaining risks honestly.

## 11. Verification Matrix

| Change type | Minimum verification |
|---|---|
| Flutter UI-only narrow change | `flutter analyze`, relevant `flutter test` if present, manual/screenshot smoke when visual |
| Flutter shared API/service change | Targeted service tests, `flutter test`, `flutter analyze` |
| Backend controller/service change | `cd server; npm run typecheck`, `npm test`, `npm run build` |
| Auth/RBAC/files/security change | Backend full tests, actor/policy tests, audit/log secret check if applicable |
| Realtime change | Backend tests plus `cd server; npm run smoke:realtime` when staging is intended |
| Migration/import change | Unit tests, dry-run report, rollback/count verification |
| Infra/env change | `cd infra/staging; docker compose --env-file .env config -q`, relevant health/backup smoke |
| Release/cutover change | Read `.anws/v3/09_S7_RELEASE_EVIDENCE.md` and matching runbook first |

## 12. Anti-patterns

Avoid these patterns:

- Direct `Supabase.instance.client.from(...)` calls in widget `build()` or event handlers.
- Silent blank UI states after failed async loading.
- Disabled buttons without visible reason.
- Manager mutations without confirmation/success/error feedback.
- Public URLs for private user/chat files.
- Client-only security checks without backend enforcement.
- Live import/cutover operations without backup evidence and explicit user approval.
- Editing ignored env files into commits.
- Reverting unknown dirty working tree changes.
- Broad visual restyling while fixing a narrow UX bug.

## 13. Understand-Anything Assets

Generated project graph:

- `.understand-anything/knowledge-graph.json`
- `.understand-anything/meta.json`
- `.understand-anything/fingerprints.json`
- `.understand-anything/intermediate/scan-result.json`
- `.understand-anything/.understandignore`

Local dashboard may be available if the custom server is still running:

```text
http://127.0.0.1:5175/?token=<local-session-token>
```

The token/server are local session details and can change. If the dashboard is blank, use the production-built dashboard/static server workaround rather than relying on the Vite dev server; the earlier failure mode was raw TSX served for `/src/main.tsx`.

## 14. Handoff Checklist

Use this checklist before handing work to another agent:

- [ ] State the active task ID or explain why no task ID applies.
- [ ] List files changed.
- [ ] List tests/gates run.
- [ ] List tests not run and why.
- [ ] Mention any dirty worktree changes that were pre-existing.
- [ ] Mention open risks or follow-up tasks.
- [ ] For UX work, include screenshot/audit evidence when possible.
- [ ] For backend/security work, mention auth/RBAC/audit impact.
- [ ] For migration/ops work, mention dry-run/backup/rollback evidence.

## 15. Fast Context Links

| Need | Go to |
|---|---|
| Project rules | `AGENTS.md` |
| Current task state | `.anws/v3/05_TASKS.md` |
| Architecture overview | `.anws/v3/02_ARCHITECTURE_OVERVIEW.md` |
| ADRs | `.anws/v3/03_ADR/` |
| System design | `.anws/v3/04_SYSTEM_DESIGN/` |
| S7 release evidence | `.anws/v3/09_S7_RELEASE_EVIDENCE.md` |
| Latest UX audit | `docs/audits/windows-ux-ui-2026-06-16/report.md` |
| Flutter API boundary | `lib/core/api/` and `lib/core/services/` |
| Backend API boundary | `server/src/` |
| Migrations | `server/db/migrations/` |
| Staging ops | `infra/staging/` and `infra/scripts/` |

