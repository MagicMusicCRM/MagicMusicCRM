# Prompt for Developer Agent - Fix Full-App Realtime, Messenger, Administration and Announcements

Ты работаешь в проекте:

`C:\Projects\MagicMusicCRM`

Нужно профессионально починить realtime-функционал во всем приложении, а не только в явно названных местах. Мессенджер, `Администрация` и `Объявления` - обязательные P0-блокеры, но агент должен пройтись по всем ролям, всем вкладкам и всем пользовательским сценариям, где данные должны обновляться без ручного refresh. Не ограничивайся косметическими фиксами в одном экране: нужно доказать end-to-end доставку событий через REST + Socket.IO + Flutter UI.

## Перед началом обязательно прочитай

1. `AGENTS.md`
2. `.anws/v3/05_TASKS.md`
3. `docs/ONBOARDING.md`
4. `docs/migration/WIRE-TO-SERVICE-CHECKLIST.md`
5. `server/src/messenger/messenger.controller.ts`
6. `server/src/messenger/messenger.service.ts`
7. `server/src/messenger/messenger.policy.ts`
8. `server/src/messenger/realtime.gateway.ts`
9. `server/src/realtime/realtime-bus.ts`
10. `server/src/smoke/realtime-smoke.ts`
11. `lib/core/services/magic_realtime_service.dart`
12. `lib/core/services/magic_messenger_service.dart`
13. `lib/features/messenger/presentation/screens/messenger_screen.dart`
14. `lib/features/teacher/presentation/widgets/teacher_chat_widget.dart`
15. `test/core/services/magic_realtime_service_test.dart`
16. `test/core/services/magic_messenger_service_test.dart`
17. `server/src/messenger/messenger.service.spec.ts`
18. `server/src/messenger/messenger.policy.spec.ts`
19. `lib/features/messenger/presentation/screens/crm_nav_rbac.dart`
20. `lib/features/admin/presentation/widgets/schedule_widget.dart`
21. `lib/features/manager/presentation/widgets/clients_widget.dart`
22. `lib/features/manager/presentation/widgets/leads_widget.dart`
23. `lib/features/manager/presentation/widgets/students_board_widget.dart`
24. `lib/features/admin/presentation/widgets/tasks_widget.dart`
25. `lib/features/admin/presentation/widgets/finance_widget.dart`
26. `lib/features/admin/presentation/widgets/reports_widget.dart`
27. `lib/features/admin/presentation/widgets/user_roles_widget.dart`
28. `lib/core/services/crm_realtime_provider.dart`
29. `lib/core/services/magic_crm_service.dart`

## Problem Statement

Владелец сообщает:

- приложение сейчас не работает в realtime для всех пользователей;
- не у всех пользователей по стандарту всегда виден канал `Администрация`;
- не у всех пользователей по стандарту всегда виден канал `Объявления`;
- `Администрация` нужна, чтобы новые клиенты могли писать администраторам, а сообщения были видны всем администраторам;
- `Объявления` нужны для школьных объявлений: видны всем пользователям, но публиковать/редактировать могут только `admin`, `manager`, `system_admin`.
- кроме этих двух каналов, нужно проверить весь функционал CRM и починить realtime там, где пользователь ожидает обновления без ручной перезагрузки.

## Business Rules

### Roles

Сохрани проектную иерархию и RBAC naming:

- `client` - клиент/ученик;
- `teacher` - преподаватель;
- `admin` - администратор;
- `manager` - управляющий;
- `system_admin` - системный администратор.

Права для этой задачи:

- `Администрация`: каждый пользователь видит entry point всегда.
- `Администрация`: `client` и `teacher` могут написать администрации.
- `Администрация`: все `admin`, `manager`, `system_admin` видят сообщения в админском inbox/surface.
- `Администрация`: staff может отвечать пользователю; ответ должен дойти пользователю в realtime.
- `Объявления`: все роли читают.
- `Объявления`: только `admin`, `manager`, `system_admin` создают/редактируют/публикуют объявления.
- `Объявления`: `client` и `teacher` не видят поле ввода/редактирования и получают backend `403` при попытке записать напрямую.

## Current Code Clues - Verify, Do Not Assume

По текущему коду видны подозрительные места. Проверь их фактами перед правками:

- `MagicRealtimeService` подключается к Socket.IO path `/realtime` и имеет `joinChat`, `joinUserRoom`, но явного `joinChannel` сейчас нет.
- `MessengerService.createChannelPost` публикует `channel.post_created` через `this.realtime.publishChatEvent(channelId, "channel.post_created", post)`.
- `RealtimeGateway.canJoinRealtimeRoom` сейчас авторизует `roomType === 'chat'` через chat access; отдельной channel-room авторизации может не быть.
- `MessengerScreen` подписывается на `onChannelPostCreated`, но событие придет только если клиент реально присоединился к комнате канала.
- `MessengerScreen._loadChatListInternal` вызывает `messenger.ensureAdministrationChat()` только для non-staff, а staff получает admin inbox через `listChats`/policy. Проверь, что все staff реально видят все входящие admin conversations.
- `MessengerService.createAdministrationChat` создает administration chat только с текущим пользователем как member. Staff read/write допускается policy, но list/query/inbox может не показывать staff все такие чаты.
- `listChannels` показывает каналы по `channel_permissions` или staff role. Значит `Объявления` должен иметь default permissions для всех read roles и staff write roles, либо отдельный system channel contract.

## Required Outcome

После работы должно быть так:

1. Новый клиент после входа всегда видит `Администрация` и `Объявления`.
2. Новый преподаватель после входа всегда видит `Администрация` и `Объявления`.
3. `admin`, `manager`, `system_admin` всегда видят `Объявления`.
4. Staff видит входящие обращения в `Администрация` от всех пользователей, которым нужен контакт с администрацией.
5. Сообщение клиента в `Администрация` появляется у staff без ручного обновления.
6. Ответ staff в `Администрация` появляется у клиента без ручного обновления.
7. Новый post в `Объявления` появляется у `client`, `teacher`, `admin`, `manager`, `system_admin` без ручного обновления.
8. `client`/`teacher` не могут писать в `Объявления`.
9. Reconnect после потери сети заново восстанавливает нужные realtime-room subscriptions.
10. Realtime не дублирует сообщения при optimistic UI + incoming event.
11. Агент прошел все роли и разделы приложения, составил realtime coverage matrix и исправил все confirmed gaps.
12. Все функции, где realtime не нужен, явно помечены как `REST refresh/manual refresh acceptable` с причиной.

## Full-App Realtime Coverage Requirement

Это обязательный раздел задачи. Нельзя сдать работу, починив только чат.

Агент должен пройти все доступные роли и все основные вкладки/поверхности приложения:

- `client`: чат, расписание/занятия, домашние задания/задачи, профиль, уведомления, объявления;
- `teacher`: чат, расписание, ученики, занятия/посещаемость, домашние задания/заметки, объявления;
- `admin`: чат, расписание, клиенты/лиды/ученики, задачи, объявления;
- `manager`: чат, расписание, клиенты/лиды/ученики, задачи, финансы, отчеты, пользователи, настройки, объявления;
- `system_admin`: все manager/admin surfaces плюс системные настройки/пользователи.

Создай и заполни файл:

`docs/audits/ui-redesign-2026-06-24/full-app-realtime-coverage.md`

Формат матрицы:

| Role | Section | Scenario | Expected realtime behavior | Current behavior | Backend event/room | Flutter subscriber | Fix implemented | Evidence |
|---|---|---|---|---|---|---|---|---|

Минимально проверь и классифицируй:

- direct/group chat messages;
- `Администрация` user-to-staff and staff-to-user;
- `Объявления` channel posts;
- typing/presence/read state if surfaced in UI;
- schedule lesson create/update/delete/reschedule/attendance;
- lead create/update/delete/status move/conversion;
- student create/update/branch/status move;
- client/student card comments/tasks/history if shown in multiple sessions;
- task create/update/status changes;
- payments/finance entries that affect visible balances/reports;
- user role changes that affect navigation/access;
- settings changes that affect shared UI, including admin chat avatar if visible;
- notifications/in-app bell entries;
- file/message attachment lifecycle if visible in chat.

Realtime does not mean "every SQL row must live-update everywhere". It means:

- if two users can reasonably be looking at the same operational surface, a write from one user should update or invalidate the other user's visible state without requiring app restart;
- if full live patching is too risky, emitting a scoped invalidation event and refetching the affected query is acceptable;
- if a surface is intentionally not realtime, document why and make sure the UI has a visible refresh path.

Required event strategy:

- messenger events should deliver payloads directly (`message.created`, `message.updated`, `channel.post_created`, etc.);
- CRM surfaces may use `crm.changed` invalidation if the payload is scoped enough to refetch only affected entities;
- avoid global broadcast to every socket unless RBAC-safe and justified;
- every subscription must be restored after reconnect.

## Implementation Requirements

### 1. Diagnose before patching

Сначала создай короткий диагностический отчет в:

`docs/audits/ui-redesign-2026-06-24/realtime-messenger-diagnosis.md`

В нем зафиксируй:

- текущий broken path;
- какие события публикуются backend;
- какие комнаты/каналы реально join-ит Flutter;
- какие REST endpoints возвращают `Администрация` и `Объявления` для каждой роли;
- какие разделы приложения уже используют `crm.changed`/realtime invalidation;
- какие разделы вообще не подписаны на realtime, хотя должны;
- какие тесты/смоки сейчас падают или недостаточны.

Диагностика должна ссылаться на `full-app-realtime-coverage.md`, а не только на мессенджер.

### 2. Backend: default system channels

Реализуй durable default data contract.

Варианты допустимы, но финальная модель должна быть надежной:

- migration/seed для системного канала `Объявления`;
- idempotent service method `ensureDefaultChannels`;
- startup/bootstrap seed, если в проекте уже есть такой паттерн;
- отдельный endpoint вроде `GET /messenger/defaults`, если он лучше ложится на текущую архитектуру.

Минимум для `Объявления`:

- один системный канал с title `Объявления`;
- read permission для ролей `client`, `teacher`, `admin`, `manager`, `system_admin`;
- write permission только для `admin`, `manager`, `system_admin`;
- нельзя создать дубль `Объявления` повторным запуском seed/migration;
- канал возвращается в `GET /messenger/channels` всем ролям.

Если потребуется schema flag, добавь его миграцией аккуратно, например `kind`/`slug`/`is_system`, но не ломай существующие channels.

### 3. Backend: administration inbox semantics

Приведи `Администрация` к понятной модели:

- каждый user-facing actor должен иметь всегда видимый entry point `Администрация`;
- сообщение пользователя должно попадать в inbox staff;
- staff должен видеть все активные `administration` conversations, а не только те, где он явно member;
- staff reply должен возвращаться в тот же conversation и доходить user в realtime;
- unread/read должны оставаться корректными для обеих сторон.

Если текущая модель "один administration chat на пользователя + staff implicit access" сохраняется, убедись, что:

- `listChats` для staff возвращает administration chats, где есть новые обращения;
- `getChat`, `listMessages`, `sendMessage`, `markRead`, realtime join работают для staff через policy;
- UI отображает такие чаты как `Администрация`/имя пользователя понятно.

### 4. Backend: realtime rooms for chat and channels

Нормализуй realtime-room contract:

- `room.join` должен явно поддерживать room types, которые реально нужны: `chat`, `channel`, `user`;
- channel join должен проверять `MessengerPolicy.getChannelAccess` + `canRead`;
- channel post publish должен отправлять в channel-room, не маскироваться под chat-room без явного контракта;
- chat message publish должен отправлять в chat-room и при необходимости user/staff inbox invalidation;
- если `chat.updated` нужен для появления новых conversations в списке, публикуй его в user rooms/staff rooms после создания admin chat/message.

Не делай широковещательный broadcast всем socket-ам без авторизации.

### 5. Flutter: realtime subscription lifecycle

Почини клиент так, чтобы realtime был надежным:

- после загрузки списка чатов join-ить все активные chat rooms, которые нужны для badge/list updates;
- при открытии чата join-ить selected chat;
- при открытии/наличии канала `Объявления` join-ить channel room;
- после reconnect повторно join-ить все нужные rooms;
- добавить явный `joinChannel` в `MagicRealtimeConnection`, если backend поддерживает `roomType: channel`;
- не оставлять silent failure: если realtime не подключен, показывать мягкий статус/лог, но REST должен продолжать работать.

### 6. Flutter: default entries always visible

В UI мессенджера:

- `Администрация` не должна исчезать у новых пользователей даже если нет сообщений;
- `Объявления` не должны исчезать у любых пользователей;
- для `Объявления` скрыть composer у `client`/`teacher`;
- для `Объявления` показать composer/actions только `admin`, `manager`, `system_admin`;
- если доступ к каналу временно не загрузился, UI не должен выглядеть как пустой/сломанный экран.

### 7. Full-app realtime fixes

После диагностики full-app матрицы исправь все confirmed gaps.

Обязательный минимум:

- Messenger surfaces use direct realtime payload events, not periodic polling.
- Schedule surfaces receive `crm.changed` or a more specific event on lesson create/update/delete/reschedule/attendance and refetch affected day/month/matrix.
- Client/lead/student boards receive realtime invalidation on create/update/delete/status/branch changes and update visible kanban/list state.
- Task surfaces receive realtime invalidation on create/update/status changes.
- Finance/balance/report surfaces receive realtime invalidation when payments/expenses/lesson attendance changes affect visible totals.
- User/role management surfaces receive realtime invalidation after role/profile changes, especially when access/navigation can change.
- Settings surfaces receive realtime invalidation when shared settings affect visible UI, including admin chat avatar.
- Notification bell/in-app notification surface updates without app restart.

If an existing backend method already emits `crm.changed`, verify that Flutter subscribes and refetches the correct provider/screen. If a backend write does not emit anything and the corresponding UI should update live, add a scoped event or `crm.changed` emission with enough metadata:

```ts
{
  entity: "lesson" | "lead" | "student" | "task" | "payment" | "user" | "setting" | "...",
  action: "created" | "updated" | "deleted" | "moved" | "...",
  id: "...",
  branchId?: "...",
  affectedUserIds?: ["..."],
  changedAt: "..."
}
```

Do not add noisy global refetches everywhere. Use scoped invalidation and debounce refetches on Flutter side where needed.

### 8. Tests required

Добавь/обнови backend tests:

- `MessengerService` creates/returns default `Объявления` idempotently.
- `listChannels` returns `Объявления` for every role.
- `client`/`teacher` can read `Объявления`.
- `client`/`teacher` cannot create channel posts.
- `admin`/`manager`/`system_admin` can create channel posts.
- `channel.post_created` publishes to the correct realtime room.
- staff can see/list/read/reply to user administration conversations.
- `message.created` for administration conversation reaches the right rooms/user invalidations.
- every write path identified as realtime-required in `full-app-realtime-coverage.md` emits an event or documented invalidation.
- RBAC prevents users from joining realtime rooms they cannot read.
- reconnect/rejoin logic is test-covered at service level where feasible.

Добавь/обнови Flutter tests:

- `MagicRealtimeService` supports `joinChannel`.
- `MagicMessengerService` maps default channels correctly.
- `MessengerScreen` shows `Администрация` and `Объявления` for client/teacher/staff states.
- Composer hidden for read-only announcement users.
- Realtime channel post handler inserts/upserts without duplicates.
- `crm.changed` or specific realtime events invalidate/refetch schedule, clients/leads/students, tasks, finance/reports, users/settings where required.
- duplicate event delivery does not duplicate rows/cards/messages.
- reconnect re-subscribes to user/chat/channel/CRM rooms.

### 9. Smoke tests required

Расширь или добавь smoke script рядом с:

`server/src/smoke/realtime-smoke.ts`

Новый smoke должен проверять минимум:

1. Login as client and admin/manager/system_admin test accounts.
2. Client sees/ensures `Администрация`.
3. Staff sees the administration conversation.
4. Client sends admin message through REST.
5. Staff socket receives `message.created` without refresh.
6. Staff replies through REST.
7. Client socket receives `message.created` without refresh.
8. Everyone can list/read `Объявления`.
9. Admin posts to `Объявления`.
10. Client/teacher socket receives `channel.post_created`.
11. Client/teacher direct POST to announcements returns `403`.
12. Staff creates/updates/reschedules a lesson; another staff session receives realtime invalidation and can refetch updated schedule.
13. Staff updates/moves a lead/client/student; another staff session receives realtime invalidation and can refetch updated board/list.
14. Staff creates/updates a task; another relevant staff session receives realtime invalidation.
15. Payment/finance-affecting write emits invalidation for visible balances/reports if those screens are marked realtime-required.
16. Role/profile/settings updates emit invalidation or a documented forced-refresh path if live UI cannot safely update.

If smoke users need verified email, use the existing verified-account pattern or explicitly verify disposable users in the smoke. Do not hardcode secrets into committed files.

## Likely Files to Change

Backend:

- `server/src/messenger/messenger.controller.ts`
- `server/src/messenger/messenger.service.ts`
- `server/src/messenger/messenger.policy.ts`
- `server/src/messenger/realtime.gateway.ts`
- `server/src/messenger/dto/realtime-events.dto.ts`
- `server/src/realtime/realtime-bus.ts`
- `server/db/migrations/*.sql`
- `server/src/smoke/realtime-smoke.ts` or new smoke file
- `server/src/messenger/*.spec.ts`
- `server/src/crm/crm.service.ts`
- `server/src/crm/crm.controller.ts`
- `server/src/notifications/*`
- relevant CRM/task/finance/user/settings specs

Flutter:

- `lib/core/services/magic_realtime_service.dart`
- `lib/core/services/magic_messenger_service.dart`
- `lib/core/services/crm_realtime_provider.dart`
- `lib/core/services/magic_crm_service.dart`
- `lib/features/messenger/presentation/screens/messenger_screen.dart`
- `lib/features/teacher/presentation/widgets/teacher_chat_widget.dart`
- `lib/features/admin/presentation/widgets/schedule_widget.dart`
- `lib/features/manager/presentation/widgets/clients_widget.dart`
- `lib/features/manager/presentation/widgets/leads_widget.dart`
- `lib/features/manager/presentation/widgets/students_board_widget.dart`
- `lib/features/admin/presentation/widgets/tasks_widget.dart`
- `lib/features/admin/presentation/widgets/finance_widget.dart`
- `lib/features/admin/presentation/widgets/reports_widget.dart`
- `lib/features/admin/presentation/widgets/user_roles_widget.dart`
- `lib/core/widgets/telegram/chat_info_dialog.dart`
- related tests under `test/core/services/` and `test/features/`

## Verification Commands

Run backend:

```powershell
cd C:\Projects\MagicMusicCRM\server
npm run typecheck
npm test -- --runInBand messenger
npm test -- --runInBand crm
npm test
npm run build
npm run smoke:realtime
```

Run Flutter:

```powershell
cd C:\Projects\MagicMusicCRM
flutter analyze
flutter test test/core/services/magic_realtime_service_test.dart
flutter test test/core/services/magic_messenger_service_test.dart
flutter test test/features
flutter test
```

If staging verification is required:

```powershell
cd C:\Projects\MagicMusicCRM\server
npm run smoke:realtime -- --base-url=https://api.phantom-net.ru/api
```

Adapt the exact smoke command to the current script contract if needed and document it.

## Required App Rebuilds

After the fix is verified, rebuild PC and Android artifacts.

Windows:

```powershell
cd C:\Projects\MagicMusicCRM
flutter build windows --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Android APK:

```powershell
cd C:\Projects\MagicMusicCRM
flutter build apk --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

If release process requires AAB:

```powershell
flutter build appbundle --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Record artifact paths and SHA-256 hashes.

## Acceptance Matrix

Return this messenger/default-channel matrix filled by evidence:

| Actor | Sees Администрация | Can write Администрация | Sees Объявления | Can write Объявления | Receives realtime |
|---|---:|---:|---:|---:|---:|
| client | yes | yes | yes | no | yes |
| teacher | yes | yes | yes | no | yes |
| admin | yes | yes | yes | yes | yes |
| manager | yes | yes | yes | yes | yes |
| system_admin | yes | yes | yes | yes | yes |

Also return a second full-app realtime matrix generated from:

`docs/audits/ui-redesign-2026-06-24/full-app-realtime-coverage.md`

Minimum final summary table:

| Area | Required realtime scenarios | Implemented events/invalidation | Verified by test/smoke | Remaining limitation |
|---|---|---|---|---|
| Messenger direct/group | ... | ... | ... | ... |
| Administration | ... | ... | ... | ... |
| Announcements | ... | ... | ... | ... |
| Schedule | ... | ... | ... | ... |
| Clients/leads/students | ... | ... | ... | ... |
| Tasks | ... | ... | ... | ... |
| Finance/reports | ... | ... | ... | ... |
| Users/roles/settings | ... | ... | ... | ... |
| Notifications | ... | ... | ... | ... |

## Final Response Required

В финальном ответе обязательно укажи:

- root cause или несколько root causes с доказательствами;
- backend files changed;
- Flutter files changed;
- migration/seed details;
- realtime event contract after fix;
- path to `full-app-realtime-coverage.md` and summary of all areas reviewed;
- which realtime-required gaps were fixed outside messenger;
- which surfaces were reviewed and classified as no-realtime-needed, with reasons;
- tests and smoke results;
- Windows artifact path + SHA-256;
- Android artifact path + SHA-256;
- что проверено на ролях `client`, `teacher`, `admin`, `manager`, `system_admin`;
- какие ограничения остались, если есть.
