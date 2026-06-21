# AGENTS.md — Протокол ИИ-взаимодействия

> **"Если вы читаете этот документ, вы — это Интеллект (The Intelligence)."**
>
> Этот файл — ваш **Якорь (Anchor)**. Он определяет законы проекта, карту территории и протоколы памяти.
> Когда вы пробуждаетесь (начинаете новую сессию), **первым делом прочтите этот файл**.

---

## 🧠 Протокол быстрого восстановления (Quick Recovery)

**Когда вы начинаете новую сессию или чувствуете, что «потерялись», немедленно выполните**:

1. **Прочтите AGENTS.md в корне** → получите карту проекта.
2. **Проверьте «Текущее состояние» ниже** → найдите последнюю версию архитектуры.
3. **Прочтите `.anws/v{N}/05_TASKS.md`** → узнайте текущие задачи.
4. **Приступайте к работе**.

---

## 🚀 АКТУАЛЬНЫЕ ЗАДАЧИ — Редизайн v7 → Прод (на 2026-06-21)

> **Фаза проекта:** дизайн утверждён владельцем; идёт перенос на существующее приложение. Свежий агент — ЭТО твой главный рабочий контекст.

**Что уже сделано:**
- ✅ **Дизайн v7 утверждён** — интерактивный прототип всех окон CRM: `docs/prototypes/crm-redesign-v7.html` (открыть в браузере; 5 ролей, все окна). Это **спека дизайна**, не приложение — функционал замокан, бэкенда нет.
- ✅ **Аудит покрытия** — `docs/audit/REDESIGN-COVERAGE-REPORT.md` + 8 инвентаризаций в `docs/audit/` (~58 групп эндпоинтов, матрица покрытия, 10 сирот-рисков).
- ✅ **План переноса** — `docs/migration/REDESIGN-MIGRATION-PLAN.md` (принципы · матрица покрытия §2 · новая БЭ-работа §3 · фазы §4 · реальные баги §4b · стратегия без регрессий §5 · дерево Linear §6).
- ✅ **Linear-мегаэпик KVA-192** с 10 фазами-подэпиками (ниже).

**Незыблемые принципы (приоритет владельца):**
1. **0 бэкенд-багов** — новый UI шлёт ТЕ ЖЕ API-вызовы; контракты API не меняем.
2. **Полное покрытие бэкенда** — каждый эндпоинт сохраняет «дом» в дизайне (ничего не выронить).
3. **Reskin, не rewrite** — перешиваем существующее Flutter-приложение под v7; бэкенд — источник истины.
4. **RBAC-иерархия (бизнес-правило):** `client < teacher < admin < manager < system_admin`, где **`manager` = Управляющий, `admin` = Администратор, `system_admin` = Администратор системы**. Т.е. **Управляющий > Администратор** (Управляющий круче!). ⚠️ В коде RBAC — НЕ иерархия, а **set-based `@Roles(...)`**: сейчас `manager`/`admin` почти равны как «staff» (`isStaff = admin||manager||system_admin`) — это **баг A1** (у Администратора лишний доступ). **P1 enforce-ит:** Администратор — только Чат/Расписание/Клиенты (убрать `'admin'` из manager-only `@Roles` на бэке + из nav на фронте, без смены ролей); Управляющий — полный доступ. Перенос обязан сохранить эту иерархию идентично.

**Фазы (порядок: P0→P1→P2[+P6]→P3→P4→P5→P5b→P5c→P7):**
| Фаза | Linear | Содержание | server/? |
|---|---|---|---|
| P0 | KVA-193 | Заморозка спеки + дизайн-токены v7 → `lib/core/theme/` | нет |
| P1 | KVA-194 | RBAC + nav-шелл + авторизация (OTP/2FA/онбординг) | нет |
| P2 | KVA-195 | Расписание (блок-бронь, липкие шапки, посещаемость) | нет* |
| P3 | KVA-196 | Клиенты (D&D, перенос, фильтры) ⟵ KVA-181 | нет |
| P4 | KVA-197 | Чат + фиксы E2 (ГС-плей)/E3 (галерея) | нет |
| P5 | KVA-198 | Отчёты/Финансы/Задачи/Пользователи/Настройки + запись расходов | малая |
| P5b | KVA-199 | Каталог абонементов ⟵ KVA-153 | да |
| P5c | KVA-200 | ДЗ с файлами ⟵ KVA-157 | да |
| P6 | KVA-201 | Чистка данных (199 пересечений, B1–B4) ⟵ KVA-177, параллельно | да (БД) |
| P7 | KVA-202 | Приёмка on-device ⟵ KVA-123 | нет |

\* P2 зависит от фикса данных P6-4. **Только P5b/P5c/P6 и пункт P5-5 трогают `server/`**; остальные фазы — чисто фронт (ассерт `git diff server/` = пусто).

**Стратегия без регрессий (§5 плана):** per-screen wire-to-service чек-лист · baseline сетевых вызовов «снять→перешить→diff» · контрактные тесты зелёные · тест RBAC-матрицы 5 ролей · per-PR `git diff server/` пусто для фронт-фаз.

**Прогресс:**
- ✅ **P0 (KVA-193) — инженерная часть готова** (ветка `kvazar2727/kva-193-p0-design-tokens`, чисто фронт): дизайн-токены v7 `lib/core/theme/design_tokens.dart` + выравнивание `app_theme.dart`; общая библиотека компонентов `lib/core/widgets/v7/` (`MagicToast`/`showMagicMenu`/`showMagicSheet`/`showMagicDrawer`/`SkeletonBox`); wire-to-service чек-лист `docs/migration/WIRE-TO-SERVICE-CHECKLIST.md`. Проверки: `flutter analyze` чисто, `flutter test` 153/153, `git diff server/` пусто. Осталось `P0-1` (пер-оконный апрув владельцем) + забандлить шрифт Inter (сейчас системный).

- 🔄 **P1 (KVA-194) — в работе** (ветка `kvazar2727/kva-194-p1-rbac-nav-auth`, от P0):
  - ✅ **P1-2 (A1 RBAC)** коммит `fe164cfe`: Администратор ≠ Управляющий на фронте. Источник истины `lib/features/messenger/presentation/screens/crm_nav_rbac.dart`; реальная роль (admin vs system_admin) прокинута через `admin_dashboard_screen`; per-role visible-tab модель + guards в `messenger_screen`; смена ролей `user_roles_widget` → только manager/system_admin; тест RBAC-матрицы 5 ролей. Проверки: analyze чисто, test 159/159, `git diff server/` пусто, состязательное ревью 25 агентов — нет admin-escape/регрессий. ⚠️ Бэкенд-`@Roles` ужесточение — отдельная server-задача (P1 чисто-фронт).
  - ⏳ Осталось в P1: **P1-1** v7 nav-шелл (десктоп-rail / bottom-bar + «Ещё»), **P1-3..P1-6** реколы экранов входа (login/signup→OTP/2FA/forgot/онбординг→legal-consent), **P1-7** сетевой baseline.

**▶ Следующий шаг:** **P1-1 + P1-3..P1-6** — визуальные реколы (nav-шелл + экраны авторизации) на v7-токенах/компонентах из P0. Сервис-вызовы `MagicAuthService`/`MagicReleaseGateService` менять НЕЛЬЗЯ (см. `docs/migration/WIRE-TO-SERVICE-CHECKLIST.md` и зафиксированные сигнатуры). Требуют owner-визуального апрува. Детальные подзадачи фаз — в Linear (P0-1…P7-4).

---

## 🗺️ Карта (Территориальная осведомленность)

Вот как организован этот проект:

| Путь | Описание | Протокол доступа |
|------|----------|------------------|
| `src/` | **Слой реализации**. Фактическая кодовая база. | Чтение/запись через Task. |
| `.anws/` | **Корень унифицированной архитектуры**. Содержит версии и историю изменений. | **Только чтение**(старые) / **Запись один раз**(новые). |
| `.anws/v{N}/` | **Текущая истина**. Последнее определение архитектуры. | Всегда ищите максимальную версию `v{N}`. |
| `.anws/changelog/` | **История изменений**. Записи обновлений `anws`. | Обслуживается автоматически, не удалять. |
| `Workflows` | **Рабочие процессы**. `/genesis`, `/blueprint` и др. | Читать соответствующие файлы процессов. |
| `.nexus-map/` | **База знаний**. Картография структуры кода. | Генерируется через `nexus-mapper`. |

## 🛠️ Реестр рабочих процессов (Workflows)

> [!IMPORTANT]
> **Приоритет процессов**: Когда задача соответствует какому-либо процессу или вы считаете, что она **очевидно, в основном или даже просто предположительно** подходит под сценарий процесса — **вы обязаны сначала прочитать соответствующий файл** и строго следовать шагам. Процессы — это тщательно разработанные протоколы, а не просто рекомендации.
>
> **Порядок запуска**:
> 1. Если задача соответствует сценарию, немедленно откройте файл процесса.
> 2. **Строго следуйте** шагам, описанным в процессе.
> 3. Делайте паузы на контрольных точках для подтверждения пользователем.

| Процесс | Когда запускать | Результат |
|---------|-----------------|-----------|
| `/quickstart` | Новый пользователь / Непонятно, с чего начать | Оркестрация других процессов |
| `/genesis` | Новый проект / Глобальный рефакторинг | PRD, Архитектура, ADRs |
| `/probe` | Перед изменениями / Приемка проекта | Отчет о рисках `.anws/v{N}/00_PROBE_REPORT.md` |
| `/design-system` | После genesis | Технический дизайн в `04_SYSTEM_DESIGN/*.md` |
| `/blueprint` | После genesis | Список задач `05_TASKS.md` + Wave-блоки в AGENTS.md |
| `/change` | Точечные правки существующих задач | Обновление TASKS + SYSTEM_DESIGN (только правки) |
| `/explore` | При исследовании новых технологий | Исследовательский отчет |
| `/challenge` | Перед принятием важных решений | Отчет о критике `07_CHALLENGE_REPORT.md` |
| `/forge` | Кодинг и выполнение | Код + Обновление Wave-блоков в AGENTS.md |
| `/craft` | Создание процессов/навыков/промптов | Документация Workflow / Skill / Prompt |
| `/upgrade` | После `anws update` | План обновления и миграция на новую версию |

---

## 📜 Конституция (The Constitution)

1. **Версия — это Закон**: Не «заплатки» в архитектуре, а «эволюция». Изменения требуют создания новой версии.
2. **Явный Контекст**: Все решения записываются в ADR, а не остаются в «памяти чата».
3. **Перекрестная Проверка**: Перед кодингом сверяйтесь с `05_TASKS.md`. Делаю ли я то, что запланировано?
4. **Эстетика**: Документация должна быть красивой. Используйте Markdown и Emoji.

---
## 🔄 Проектная зона сохранения (State Retention)

<!-- AUTO:BEGIN — Зона сохранения состояния (Не изменять границы блока вручную) -->

## 📍 Текущее состояние (Обновляется процессами)

> **Примечание**: Этот блок автоматически поддерживается процессами `/genesis`, `/blueprint` и `/forge`.

- **Последняя версия архитектуры**: `.anws/v3` (Backend Independence)
- **Активный список задач**: `.anws/v3/05_TASKS.md`
- **Количество задач к выполнению**: 1
- **Последнее обновление**: `2026-06-18`

### 🌊 Wave v3/S0 — Architecture and Linear Backlog
_Текущая фаза: `.anws/v3` создана для перехода с Supabase Cloud на собственный NestJS/PostgreSQL backend. Следующий шаг: завести Linear project `MagicMusicCRM v3 Backend Independence`, подтвердить INT-S0 и перейти к инфраструктурной волне._

### 🌊 Wave v3/S2-S3 — Backend Core and Auth Boundary
_Локальный NestJS backend scaffold создан. `S2` и `S3` закрыты после local gates и staging smoke: request-id/log redaction, health, audit, RBAC, password signup/login, refresh rotation/reuse detection, logout-all, OTP/password reset и optional Google OAuth fail-closed проверены. Следующая волна: `S4` Feature APIs._

### 🌊 Wave v3/S1 — Staging Infrastructure Rehearsal
_Selectel staging server `161.104.50.105` поднят для `api.phantom-net.ru`: Docker Compose, Caddy TLS, PostgreSQL, Redis и NestJS API работают. `S1` закрыт: firewall/listeners, encrypted backup/off-server copy, destructive restore drill, monitoring timer, forced alert drill и rollback restart smoke проверены._

### 🌊 Wave v3/S4 — Feature APIs
_`S4` закрыта: Profile/CRM, Messenger REST/WebSocket, private File API, Legal/Account Deletion API, Notifications provider fallback and full Feature API smoke completed on `api.phantom-net.ru`. Migrations `0002`-`0006`, role-scoped policies, audit evidence and log secret checks passed. Следующий шаг: `S5` migration pipeline from Supabase export._

### 🌊 Wave v3/S5 — Migration Pipeline
_`S5` закрыта. `T5.1` подтверждена реальным Supabase export через session pooler `aws-1-eu-central-2.pooler.supabase.com:6543`: `69` tables, `23,188` rows, `36` storage objects, `0` warnings. `T5.2` закрыта после dry-run на Selectel staging v3 PostgreSQL: `22,709` source rows, `25,002` planned rows, `1,105/1,105` messages, rollback confirmed. `T5.3` закрыта: storage/file_objects dry-run скачал `36/36` объектов, signed download API smoke прошёл. `INT-S5` закрыт после второго full dry-run and `.anws/v3/08_CUTOVER_READINESS_REPORT.md`. Следующий шаг: `S6` Flutter cutover._

### 🌊 Wave v3/S6 — Flutter Cutover
_Последнее обновление 2026-06-17: `INT-S6` закрыт по user acceptance staged Android/Windows v3 smoke evidence. S6 считается завершенным этапом: Flutter runtime переведен на owned v3 REST/WebSocket/File API, Android baseline smoke на real device `I2405` ранее прошел login/onboarding/legal/dashboard/chat send, Windows debug build/runtime smoke and no-secret integration smoke passed. Stable-device Android private file/deletion checklist перенесен в S7 launch hardening follow-up и больше не блокирует S6._
_Последнее обновление 2026-06-15: `INT-S6` частично проверен against `api.phantom-net.ru/api`. `flutter doctor -v` clean, Android licenses accepted, Android/Windows debug builds passed, Windows runtime smoke kept the fresh `magic_music_crm.exe` alive for 20 seconds. Real Android device `I2405` on Android 15 previously passed login, onboarding, legal consent, dashboard chat list, Administration chat open and message send; message `AndroidSmokeMessage` was confirmed through v3 API as `f73a5583-14f5-42b5-901e-a9c472e3dd8e`, and logcat had no Flutter/Dart/Fatal app errors. Added no-secret `integration_test/app_launch_smoke_test.dart` plus `docs/runbooks/flutter-integration-smoke.md`; Windows runner smoke starts with in-memory token store/no-op notifications, reaches the Russian login gate, validates empty login errors, checks the fake authenticated account-deletion form and reaches `Запрос принят`. Added `docs/runbooks/android-real-device-smoke.md` and `scripts/android_real_device_smoke.ps1` for the remaining stable-device private file, real-backend deletion, CRM workflow, log evidence and cleanup checklist; helper `-CheckOnly` passes. Milestone остается открытым: run integration smoke/helper on a stable Android target, then real-device Android private file upload/download and account deletion against the real backend._
_Последнее обновление 2026-06-12: `T6.4/KVA-108` закрыт. Добавлен `npm run smoke:realtime` harness, который через публичный `api.phantom-net.ru/api` проверяет health, signup/login, administration chat, Socket.IO `/realtime`, `room.join`, REST send and `message.created` event match. Staging smoke passed: user `b51deb51-60c2-4013-8ef9-5dd18488d755`, chat `3dfdd20a-00cc-4156-a7d3-95d88ff79071`, message/event `8c3324d2-b8f6-4f07-97ca-fd370d2aa698`; temp users soft-deleted. Проверки: backend `npm run typecheck`, `npm test` (`28` suites, `120` tests), `npm run build`, log secret grep clean except benign route names. Следующий шаг: `INT-S6` Android/Windows smoke._
_Последнее обновление 2026-06-12: `T6.5/KVA-108` закрыт. `ChatAttachmentService` переведен с Supabase Storage SDK на v3 `/files` multipart upload and one-time download tokens; migrated messenger/profile flows теперь используют `attachment_file_id` / `avatarFileId`; backend profile update validates own `profile_avatar`, and FilesPolicy allows chat members to read chat-bound files. Проверки: backend `npm run typecheck`, `npm test` (`28` suites, `120` tests), `npm run build`; Flutter `flutter test` (`52` tests), targeted analyze clean, full `dart analyze` только с `9` archive info-lints; staging deploy on `api.phantom-net.ru/api` passed after backup `magicmusiccrm-staging-20260612T172231Z.tgz.enc`, file smoke passed with byte match and one-time token reuse `404`. Следующий шаг: close remaining `T6.4` realtime smoke gap, then `INT-S6` Android/Windows smoke._
_Последнее обновление 2026-06-12: `T6.4/KVA-108` продвинут legacy screen slice. `messenger_screen.dart` переведен с Supabase Auth/DB/realtime and `SupaMessageService`/`SupaMessengerService` на v3 auth/profile, `MagicMessengerService` and `MagicRealtimeService`; `CreateGroupChatDialog` переведен на `/admin/profiles` + `/messenger/groups`; full Flutter tests pass (`47`). Следующий срез: `chat_info_dialog.dart` v3 contract, затем `T6.5` private file/voice attachments._
_Последнее обновление 2026-06-12: `T6.4/KVA-108` продвинут shared provider slice. `chat_providers.dart` переведен с Supabase Auth/DB/realtime на v3 `MagicAuthService` + `MagicProfileAdminService` + `MagicMessengerService`; `MagicMessengerService` расширен group/channel/post контрактами; targeted analyze/tests and full Flutter tests passed. Следующий срез: migrate legacy `messenger_screen.dart` / `chat_info_dialog.dart` onto v3 realtime/API state._
_T6.4 стартовал: добавлен `MagicRealtimeService` over Socket.IO `/realtime`, `socket_io_client 3.1.5`, unit tests for auth/path/join/typing/presence/event mapping, and `TeacherChatWidget` now consumes v3 `message.created/message.updated` realtime events after REST direct-chat bootstrap. Следующий срез: migrate legacy `messenger_screen.dart` and `admin_chat_dashboard.dart` from Supabase realtime/DB to `MagicMessengerService` + `MagicRealtimeService`._
_Последнее обновление 2026-06-12: `T6.3/KVA-108` закрыт после teacher chat slice. `MagicMessengerService` добавлен, `TeacherChatWidget` переведен на v3 `/crm` + `/messenger`, local Flutter tests and staging direct-chat smoke passed. Следующий шаг: `T6.4` messenger realtime flows, затем `T6.5` file/storage flows._
_`T6.1` и `T6.2` закрыты. `T6.3` в работе (`KVA-108`): добавлен `MagicCrmService`, client lessons/homework/subscription/progress переведены на `/crm`, profile load/save переведён на `/profile/me`; backend CRM contract расширен для `/crm/branches`, `/crm/rooms` read/write, `/crm/groups`, `/crm/students/:id/groups`, `/crm/lead-statuses` read/write, `/crm/subscriptions`, `/crm/comments` read/write, `/crm/expected-payments`, `/crm/lessons/:id/attendance`, `/crm/overview`, `/crm/leads` read/write/delete, `/crm/payments`, `/crm/tasks`, `/crm/student-balances`, `/crm/reports/finance`, `/settings/admin-chat-avatar`, `/admin/settings/admin-chat-avatar`, lesson `branchId/roomId/isTrial/leadId`; `PATCH /crm/students/:id` added for manager/admin student profile/custom-data updates with audit; `app.expenses`, `app.system_settings`, migrations `0009_lesson_attendance` and `0010_lead_management` добавлены для migration-compatible reports/settings/attendance/leads; `CreateLessonDialog`, `ScheduleWidget`, `TeacherScheduleWidget`, `TeacherStudentsWidget`, `AdminOverviewWidget`, `ManagerOverviewWidget`, `ConversionTrackingWidget`, `UserRolesWidget`, `LessonsKanbanWidget`, `LessonAttendanceDialog`, `LeadsWidget`, `LeadDetailDialog`, `ManageStatusesDialog`, `FinanceWidget`, `TopUpDialog`, `TasksWidget`, `DebtorsWidget`, `ReportsWidget`, `FinancialDashboardWidget`, `CreateRoomDialog`, `SupaSettingsService`, `ManageEntitiesWidget`, `StudentDetailDialog` и `StudentDetailScreen` переведены с прямого Supabase на v3 API. Backend разрешает assigned teacher обновлять только `status/notes` своего lesson and attendance on own lessons; attendance contract persists `present/absent` plus `passReason`; lead contract supports status create/delete, lead create/list/update/soft-delete, lead comments/tasks and lead-only trial lessons; finance contract поддерживает `from/to/studentId/limit` и student summary; task contract поддерживает `status/studentId` filters and display names; student balance contract computes paid/cost/balance server-side; report contract computes monthly revenue/expenses/attendance, teacher revenue and room load server-side; room write contract supports manager/admin create/update/soft-delete with audit; settings contract supports authenticated admin-avatar read and admin-only validated write; entity management reads students/teachers/lessons/groups/rooms/staff via v3 services and updates lesson cancel/reschedule via `/crm/lessons/:id`; student detail dialog loads/saves student and comments through v3 one-shot APIs; full student detail screen now loads student, payments, lessons, tasks, active groups, balance, comments and expected payments through v3 APIs and saves comments, tasks, individual price and contract URL through backend writes. Проверки: backend `npm run typecheck`, `npm test` (`28` suites, `119` tests), `npm run build`; Flutter `flutter test` (`34` tests), targeted `dart analyze` clean; full `flutter analyze` has pre-existing info-level lints outside this slice. Staging deploy/smoke on `api.phantom-net.ru/api` passed after encrypted backups: health, reference endpoints, subscriptions, seeded progress comments, authenticated `/crm/overview`, unauth `401`, `/crm/leads`, `/crm/lessons?isTrial=true`, `/admin/profiles`, admin role update, `/crm/payments` list/create/filter, client payment write `403`, `/crm/tasks` create/list/filter/status update, client task write `403`, `/crm/student-balances?debtOnly=true`, client balance list `403`, migration `0007_expenses_reports`, `/crm/reports/finance` admin `200` with monthly/teacher/room aggregates, unauth report `401`, client report `403`, cleanup `1/1/1/1/1/1/2/2`, `/crm/rooms` create/list/update/delete smoke with unauth `401`, client write `403`, room cleanup, migration `0008_system_settings`, settings smoke with unauth `401`, manager write `403`, invalid URL `400`, setting cleanup/restore, `PATCH /crm/students/:id` + `POST/GET /crm/comments` smoke with audit events `crm.student_updated`/`crm.comment_created`, `/crm/students/:id/groups` + `/crm/expected-payments` smoke returned `1/1`, migration `0009_lesson_attendance` applied (`1/1`), `/crm/lessons/:id/attendance` read/save smoke returned `2/2`, migration `0010_lead_management` applied (`1/1/1/1`), lead status/lead/comment/task/lead trial smoke passed, temporary smoke cleanup `users=0/leads=0/lessons=0`, and strict API log secret grep found only benign route/module names. Следующий шаг: teacher chat, T6.4 messenger и T6.5 files._

### 🌊 Wave v3/S7 — Security and Launch
_Последнее обновление 2026-06-17: `S7` закрыт under clarified launch scope. HolliHop был только one-time bulk extraction source и не является runtime dependency/launch blocker; credential rotation сейчас не планируется; public API endpoint остается `api.phantom-net.ru`, смена адреса не планируется. `T7.3/KVA-114`, `T7.4/KVA-115` и `INT-S7/KVA-116` закрыты: `npm run security:gate` после корректировки gate проходит `7 pass / 4 warn / 0 fail`, backend `npm run typecheck` passes, HTTPS health на `api.phantom-net.ru` passes, realtime/auth smoke passed with message/event `3747cdde-1f90-4299-90a1-b35716cafdf9`, private file smoke passed with byte match and one-time token reuse `404`, email-provider smoke sent notification `8fcf4bd9-0376-447d-8a8b-3a5be368beab` via `resend/sent`, API restart rollback smoke recovered on attempt `2`. Следующий этап: `S8` desktop UX/UI stabilization._
_`S7` pre-release gate completed 2026-06-12 and evidence is in `.anws/v3/09_S7_RELEASE_EVIDENCE.md`. Codex Security repository pass generated `C:\tmp\codex-security-scans\MagicMusicCRM\c683807_20260612T204722\report.md` and `report.html`; official validator passed. Fixed in working tree: `server/exports`/`server/storage` excluded from Git and Docker context, chat attachment IDOR closed via `assertCanReadChat`, login and OTP verify lockouts added with migration `0011`, SSH bootstrap now disables root/password login by default, and test PostgreSQL bind is localhost-only. Current gates passed: backend `npm run typecheck`, `npm test` (`28` suites, `123` tests), `npm run build`, `npm audit --audit-level=moderate`; Flutter `flutter analyze` (`No issues found`) and `flutter test` (`52` tests); staging health and `npm run smoke:realtime`; `npm run security:gate` returned `7` pass, `4` warning, `0` fail. Google Play AAB `v1.1.6+116` built at `build/app/outputs/bundle/release/app-release.aab`, SHA-256 `D6E0BE113070FC62F41171F403351702A39ABE1C5291A0882247D04106C5DF5D`. Последнее обновление 2026-06-15: guarded HolliHop archive DB-backed dry-run passed as one-time migration evidence after backup `magicmusiccrm-staging-20260615T131610Z.tgz.enc`; report `hollihop-import-2026-06-15T13-40-42-091Z.json`, batch `3c4fc480-74a7-4801-a0e2-45c26972004a`, warnings `tasks_source_missing`/`timeline_sources_missing`, secret grep clean._

### 🌊 Wave v3/S8 — Desktop UX/UI Stabilization
_Последнее обновление 2026-06-18: `S8` remediation выполнена (`T8.1`–`T8.4` закрыты в Linear: `KVA-119`–`KVA-122`): schedule loading/empty/error+retry с видимым header, trustworthy task FAB с pending/error feedback, lead columns modal loading/empty/error states + board scroll affordance, lead status-menu current-state marker, role/activity/finance clarity. Проверки: `flutter analyze` clean, `flutter test` 94/94 (вкл. `test/features/s8_desktop_ux_states_test.dart`). Осталась 1 задача — `INT-S8` (`KVA-123`, In Review): нативная Windows-сборка и живой Computer-Use desktop re-audit заблокированы окружением без сети (CMake `firebase_core` SDK download) и должны быть выполнены в сетевом окружении перед закрытием gate и публичным релизом. `KVA-117`/`KVA-118` оставлены In Review до прохождения acceptance. Acceptance write-up: `docs/audits/windows-ux-ui-2026-06-18/report.md`._ Linear `KVA-117`/`KVA-118` и дочерние `KVA-119`–`KVA-123` закрыты. Следующий этап: дальнейший P2 polish (design tokens, overview hierarchy)._
_Последнее обновление 2026-06-16: локальный manager-role Windows audit `docs/audits/windows-ux-ui-2026-06-16/report.md` выявил новые product-quality blockers после v3 cutover. Критические trust failures: Schedule может зависать в безымянной blank/skeleton state, Task FAB не открывает create flow и не показывает pending/error feedback, lead columns modal рендерится пустым серым телом. Дополнительно зафиксированы `P1/P2` проблемы в lead board affordance, role/status mutation clarity, manager-facing reports activity copy, finance form guidance и design-token consistency. В `.anws/v3/05_TASKS.md` создан remediation backlog `T8.1`-`T8.4` + `INT-S8`; те же follow-ups привязаны к текущему stabilization parent `KVA-117` в Linear. Следующий шаг: выполнить `T8.1` и `T8.2`, затем повторить Windows audit до закрытия `INT-S8`._

### Технологические решения
- Язык/фреймворк: Dart + Flutter client, NestJS + TypeScript backend.
- Backend: Owned HTTPS/WebSocket API, PostgreSQL, Redis, private local storage, workers.
- State: Riverpod.
- Quality Gates: `flutter analyze`, `flutter test`, backend unit/integration/security tests, actor-matrix, secrets/dependency/container scans, migration dry-runs, backup restore drill.

### Границы систем
- **SYS-APP**: Flutter client, Russian UI, Riverpod state, API/WebSocket integration.
- **SYS-API**: NestJS REST API, validation, auth guards, RBAC, audit.
- **SYS-AUTH**: Email/password, OTP, refresh rotation, password reset, optional Google OAuth.
- **SYS-DATA**: PostgreSQL schema, migrations, scoped repositories, constraints.
- **SYS-MSG**: Messenger REST plus WebSocket realtime.
- **SYS-FILES**: Private file storage and signed downloads.
- **SYS-OPS**: Docker runtime, reverse proxy, TLS, backups, monitoring, runbooks.
- **SYS-SEC**: Security gates, actor matrix, scans and launch evidence.

### Активные ADR
- ADR-001: Backend Stack — NestJS + TypeScript, PostgreSQL, Redis, Docker Compose.
- ADR-002: Own Auth and Session Model — email/password primary, OTP, refresh rotation, optional Google OAuth.
- ADR-003: Private File Storage — local NVMe storage behind backend authorization plus external encrypted backups.
- ADR-004: Realtime and Messaging — owned WebSocket gateway with per-room authorization.
- ADR-005: Deployment and Recovery — Moscow primary, external backups, restore drill and rollback runbook.
- ADR-006: Security Gates — scans, actor matrix, 50-point checklist and release evidence block cutover.

---

## 🌳 Структура проекта (Project Tree)

> **Примечание**: Поддерживается процессом `/genesis`.

```text
.
├── lib/                  (Flutter client)
├── server/               (v3 NestJS backend; planned)
│   ├── apps/api/         (HTTPS/WebSocket API)
│   ├── modules/          (auth, profile, crm, messenger, files, legal)
│   └── db/               (PostgreSQL migrations; planned)
├── infra/                (Docker/reverse proxy/backups; planned)
└── .anws/v3/             (Backend Independence architecture)
```

---

## 🧭 Навигация (Navigation Guide)

> **Примечание**: Поддерживается процессом `/genesis`.

- **Обзор архитектуры**: `.anws/v3/02_ARCHITECTURE_OVERVIEW.md`
- **ADR (Решения)**: `.anws/v3/03_ADR/` (Источник истины архитектурных решений)
- **Детальный дизайн**: `.anws/v3/04_SYSTEM_DESIGN/`
- **Задачи**: `.anws/v3/05_TASKS.md`
- **Challenge Report**: `.anws/v3/07_CHALLENGE_REPORT.md`
- **Cutover Readiness**: `.anws/v3/08_CUTOVER_READINESS_REPORT.md`
- **S7 Release Evidence**: `.anws/v3/09_S7_RELEASE_EVIDENCE.md`

<!-- AUTO:END -->

---

## 🛡️ Операционные Правила (Magic Music Rules)

> [!IMPORTANT]
> **Принципы разработки в этом проекте (v1):**
>
> 1. **Префиксная Сервисная Модель**: Все новые сервисы, работающие напрямую с Supabase, ДОЛЖНЫ иметь префикс `Supa` (например: `SupaStudentService.dart`, `SupaLessonService.dart`).
> 2. **Декомпозиция Виджетов**: Запрещено писать SQL-подобные запросы (`Supabase.instance.client.from(...)`) напрямую в методах `build()` или обработчиках событий виджетов. Логика должна быть вынесена в провайдеры (Riverpod) или `Supa`-сервисы.
> 3. **Стейт-менеджмент**: Основной инструмент — **Riverpod**. Не используйте `StatefulWidget` для хранения глобальных данных, работайте через провайдеры.
> 4. **Языковой стандарт**: Весь UI-текст должен быть на русском языке (`ru`). Комментарии и код — на английском.
> 5. **Дизайн-код (Flat Magic)**:
>    - Придерживайтесь схемы **Deep Charcoal & Sophisticated Gold** (`#C5A059`).
>    - **ЗАПРЕЩЕНО** использовать свечение (`boxShadow`), яркие градиенты и эффект глянца для основных кнопок. Стиль должен быть плоским (Flat) и матовым.
>    - Для Desktop используйте `ConstrainedBox(maxWidth: 450)` для центрирования контента.
> 6. **Проактивность Агента**: Если я вижу в коде нарушение этих правил (например, прямой вызов Supabase в UI или "вырвиглазные" цвета), я ОБЯЗАН предложить рефакторинг перед выполнением основной задачи.
> 7. **Синтаксическая безопасность**: При редактировании глубоко вложенных деревьев виджетов (Scaffold -> Safe -> Center -> Scroll -> Constrained) ВСЕГДА проверяйте количество закрывающих скобок. Рекомендуется использовать `write_to_file` для перезаписи всего метода `build` при обнаружении коррупции.

---
## 🔐 Env / Ops Recovery

> [!IMPORTANT]
> Реальные env-файлы ignored. Не коммитьте секреты, backup-архивы, Firebase private key, HolliHop key, Supabase service role, DB URL с паролями или Telegram token.

| Файл | Назначение |
|------|------------|
| `server/.env` | Локальный NestJS backend, DB, email/push providers, HolliHop key, local migration DB URL. |
| `server/.migration.env` | Безопасные дефолты импортов: dry-run, batch size, Supabase export dir, HolliHop mode. Секреты брать из `server/.env`. |
| `infra/staging/.env` | Staging Docker Compose runtime для `api.phantom-net.ru`. |
| `infra/staging/.backup.env` | Backup root/storage root/encryption passphrase для `backup-staging.sh` и `restore-staging.sh`. |
| `infra/staging/.monitor.env` | Health URL, disk threshold, service list and alert sink for `monitor-staging.sh`. |
| `infra/staging/.deploy.env` | SSH/deploy координаты: `magicdeploy@161.104.50.105`, key `C:/Users/potyl/.ssh/mmcrm_proxy_ed25519`, remote `/opt/magicmusiccrm`. |
| `.flutter.env` | Build-time values for Flutter; Flutter still needs these passed as `--dart-define`. |

Минимальные проверки после env-правок:
- `cd infra/staging && docker compose --env-file .env config -q`
- `cd server && npm run typecheck`
- `flutter analyze`

---
> **Самопроверка**: Готовы? Предложите пользователю запустить `/quickstart` для новой задачи.
