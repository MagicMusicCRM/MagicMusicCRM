# Flutter CRM — Production-Readiness Audit Inventory

**Scope:** `lib/features/admin`, `lib/features/manager`, `lib/features/messenger`  
**Date:** 2026-06-21  
**Auditor:** Claude Code (automated static analysis)

---

## 1. Overview

The CRM shell is a **single Flutter screen** (`MessengerScreen`) rendered for every staff role (`admin`, `system_admin`, `manager`, `teacher`). Role-specific content is swapped in via a `switch` on `_selectedCrmTab`. On desktop a `NavigationRail` exposes 8 destinations (Chat / Overview / Schedule / Clients / Users / Finance / Tasks / Reports); on mobile a `BottomNavigationBar` exposes 5 (Chat / Overview / Schedule / Clients / Users). Finance, Tasks, and Reports are desktop-only tabs; on mobile they are not reachable via the navigation bar (they appear to be accessible only via deep-link or Overview card taps). Teacher role has only 3 tabs: Chat / Schedule / Students.

Both `AdminDashboardScreen` and `ManagerDashboardScreen` are thin wrappers that immediately render `MessengerScreen(role: 'admin'|'manager')`. The admin has the same UI as the manager but `_isAdminRole` gates extra permissions (posting to channels, seeing all admin profiles).

All data is fetched via two service layers:
- **`MagicCrmService`** — REST/RPC calls for CRM entities (leads, students, lessons, payments, tasks, comments, etc.)
- **`MagicMessengerService`** — chat, channels, reactions, pinning
- **`MagicRealtimeService`** — WebSocket-based typing, presence, message push
- **`MagicProfileAdminService`** — user profile listing and role assignment
- **`MagicSettingsService`** — custom field schema, admin chat avatar
- **`HollihopService`** — external system: disciplines, levels, categories (read-only, used as filter metadata)

State management is **Riverpod** (`FutureProvider`, `FutureProvider.family`, `StateNotifier`). Filter presets are persisted via **`FlutterSecureStorage`**.

---

## 2. Features (complete inventory)

### 2.1 Shell / Navigation

- **Telegram-style two-column shell** (`AdaptiveMessengerShell`): left chat list + right chat view on desktop; full-screen chat on mobile.
- **Role-based navigation rail** (desktop) / bottom bar (mobile): Chat, Обзор, Расписание, Клиенты, Пользователи, Финансы (desktop only), Задачи (desktop only), Отчёты (desktop only).
- **Deep-link navigation** via `messengerNavigationProvider`/`crmNavigationRequestProvider`: external code can navigate to a specific tab or open a direct chat by partner user ID.
- **Back-navigation interception** via `PopScope`: pressing back closes sub-views (profile panel, in-chat search, selected chat) before popping the route.
- **Unread badge** on Clients tab (Лиды count from `appLeadsCountProvider`).
- **Dark/light theme** switch (read from `themeProvider`).
- **Desktop platform detection**: `>= 768 px` width triggers desktop layout regardless of OS.

### 2.2 Messenger (Tab 0 — Чат)

- **Chat list** — loads all direct chats + group chats + channels via `messenger.listChats(limit: 100)` + `listChannels()`.
- **Administration chat** — for non-staff (client role) `ensureAdministrationChat()` is called to create/return a single school-to-client chat.
- **Direct chat opening from CRM** — staff can open a direct chat from a lead card (`resolveLeadChatUser`) or from contact resolution (`resolveContactForUser`).
- **Send text message** — optimistic local insert, replaced by server response; edits also supported.
- **Voice message recording and sending** — `VoiceRecorderWidget` + `ChatAttachmentService.uploadVoice()`.
- **File/image message sending** — file picker + MIME detection; images sent as `message_type: 'image'`, others as `'file'`; caption supported.
- **Desktop drag-and-drop file upload** — `DesktopDrop` package; triggers `_showSendFileDialog`.
- **Reply to message** — `replyToId` passed to `sendMessage`.
- **Edit own message** — `updateMessage` RPC.
- **Delete own message** — confirmation dialog → `deleteMessage(mode: 'own')`; soft-delete (shows tombstone from server response).
- **Forward message** — dialog shows full chat list; user picks target; original `sender_id` forwarded as `forwardedFromId`.
- **Emoji reactions** — optimistic toggle (add/remove) via `setReaction`/`removeReaction`; authoritative state applied from server response; rendered per-message from `_reactionsMap`.
- **Pinned messages** — `fetchPinnedMessages()` on chat open; dismissible per-message pinned bar; real-time pin updates via `message_updated` event.
- **In-chat message search** — `_isSearchingInChat` mode; `_chatSearchController`; navigate through `_searchResults`.
- **Typing indicator** — broadcast start/stop via realtime; auto-stop timer after 3 s.
- **Presence (online/offline)** — `onPresenceUpdated` realtime event; per-chat presence join on select; shown as online dot.
- **Read receipts** — `markRead` called on chat selection + on incoming message for the active chat; `unread_count` badge on chat list items.
- **Chat mute/unmute** — `setChatMute`; realtime sync on `chat_updated` event; muted chats skip local notification.
- **Chat pin** — tracked in `_pinnedChatIds`; no UI action visible yet (data loaded, not rendered in sorted position — potential gap).
- **Group chats** — `_item_type: 'group'`; create via `CreateGroupDialog` (Telegram widget); manage members via `ChatInfoDialog`.
- **Channels** — `_item_type: 'channel'`; channel posts via `createChannelPost`; posting restricted to manager/admin role only (`_canPostToChannel()`).
- **Local push notifications** — `NotificationService.showLocalNotification` for messages in non-active, non-muted chats.
- **Realtime connection** — WebSocket via `MagicRealtimeService.connect()`; joins user room on connect; joins/leaves per-chat room on chat selection.
- **Save chat contact to CRM** — staff action from chat header: save partner as lead or student (`saveContactFromChat`).
- **Open CRM card from chat** — resolves partner to student or lead and opens appropriate detail screen.
- **Profile screen** — in-chat-list panel (`ProfileScreen`); tap avatar to open own profile.
- **Chat info panel** — `ChatInfoDialog`: shows members, mute, search trigger.

### 2.3 Overview / Dashboard (Tab 1 — Обзор)

**Admin role (`AdminOverviewWidget`):**
- **4 KPI cards** (clickable, navigate to sub-tab): Учеников, Преподавателей, Филиалов, Занятий сегодня.
- Data from `getOverviewStats()` RPC.

**Manager role (`ManagerOverviewWidget`):**
- Similar overview cards; delegates sub-tab navigation via `onTabChange` callback.

### 2.4 Schedule (Tab 2 — Расписание)

- **Month view** — calendar grid; day cells show lesson count badge; per-day aggregate from `_monthDaySummary`; navigate months with prev/next arrows.
- **Day view** — horizontal swimlanes, switchable between **by-room** and **by-teacher** mode.
- **Branch selector** — dropdown to switch branch; per-branch UTC offset (`utc_offset_minutes`) used to render lesson times in branch local time.
- **Room colour coding** — 8-colour palette assigned to rooms; stable within session.
- **Teacher names** and **student names** displayed on lesson cards.
- **Schedule conflicts** — `_scheduleConflicts` list loaded; shown as a warning indicator (exact UI not fully read, but data is fetched).
- **Room availability** — `_roomAvailability` fetched; used to grey-out booked slots.
- **Create lesson** — `CreateLessonDialog` opened from FAB or day-view empty slot tap.
- **Lesson detail** — tap lesson card to open detail; mark attendance via `LessonAttendanceDialog`.
- **Cancel / reschedule lesson** — popup menu on lesson card in ManageEntities → Занятия list.
- **Auto-switch to branch with data** — on first load with no lessons, retries once with a different branch (`_autoBranchRetried` guard).

### 2.5 Клиенты (Tab 3 — Клиенты)

Container with a `SegmentedButton` toggle between **Лиды** and **Ученики** boards. Both boards preserved in `IndexedStack` (scroll positions survive tab switch).

#### 2.5.1 Лиды Kanban (`LeadsWidget`)

- **Sales funnel** heading with total lead count.
- **Horizontal kanban board** — one column per status (dynamically loaded from `listLeadStatuses`); custom column widths (300 px capped, responsive on narrow screens).
- **Drag-and-drop status move** — `LongPressDraggable<String>` + `DragTarget<String>`; 180 ms delay; haptic feedback; animated hover highlight on target column; `_optimisticLeadStatuses` for immediate visual feedback; rollback on API error.
- **Horizontal auto-scroll** — 16 ms timer scrolls board left/right when dragging within 110 px of screen edge.
- **Load more** — cursor-based pagination; "Загрузить ещё" button at column bottom; `_extraLeadsByStatus` appended to column items; deduplication via `_loadedExtraLeadIds`.
- **Search** — 350 ms debounce text field; searches name, phone, source.
- **Quick filters** — chips: Все / В работе / Отложенные / Обработанные (`quick` parameter).
- **"Есть задачи" chip** — filters by `openTasks: true`.
- **Dropdown filters** — Филиал, Статус, Направление (discipline), Уровень (level), Категория; all from HollihopService + CRM branches.
- **Filter presets** — save named preset (current search + all filters); apply preset; delete preset; stored in `FlutterSecureStorage` under key `crm.lead_filter_presets.v1`.
- **Manage columns** — "Колонки" button opens `ManageStatusesDialog`: add/reorder (drag)/delete lead statuses with custom label and color.
- **Lead card** — shows: name, phone, discipline badge, level badge, branch badge, assigned user badge, open tasks count, comments count, trial lessons count, linked student indicator, source, created date.
- **Lead card actions** (popup menu and inline buttons):
  - Chat button — opens/creates direct chat with lead via `resolveLeadChatUser`.
  - Status move — moves lead to any other status from menu (also triggerable from popup).
  - Add comment (quick inline dialog, text only).
  - Create task (quick inline dialog, title only).
  - Schedule trial lesson — select teacher, room, date+time; calls `createLesson(isTrial: true)`.
  - Convert to student — opens `ConvertLeadDialog` (branch + discipline picker); hides lead from board optimistically; undo snackbar (visual only, student not deleted).
  - Delete lead — confirm dialog; optimistic hide; API call.
- **"Без статуса" column** — leads with no status; drag to this column sends `clearStatus: true` (not a UUID).
- **Create lead FAB** — opens `_LeadDialog` (name, phone with Russian mask or international toggle, source).

#### 2.5.2 Ученики Kanban (`StudentsBoardWidget`)

- **Per-branch discipline columns** — columns are discipline names; filtered by selected branch.
- **Read-only kanban** (no drag-and-drop in v1).
- **Branch selector** dropdown; auto-selects first branch on load.
- **Student card** — shows: name, phone, discipline badge, branch badge, open tasks count, lesson count, group count.
- **Student detail popup** — modal bottom sheet with phone, branch, discipline, status, task/lesson/group counts.

### 2.6 Lead Detail Dialog (`LeadDetailDialog`)

- **Unsaved-changes guard** — `_edited` flag; `PopScope(canPop: !_edited)` + confirm dialog on close.
- **Fields (editable):** Имя (`name`), Фамилия (`last_name`), Phone (with RU mask / international toggle), Email, Status (color-coded dropdown), Заметки (textarea), Основной филиал (dropdown), custom CRM fields.
- **Custom CRM fields** — loaded from `getCrmCustomFields()`; types: `text`, `number`, `phone`, `email`, `url`, `select` (dropdown), `boolean` (switch), `date` (date picker); `required` flag shown with asterisk; `hint` shown as helper text; `branchId`, `hollihopId`, `sourceLeadId` excluded from display.
- **Связи и активность section** — calls `getLeadCard()` to load: linked students, tasks (with status), trial lessons (with teacher/room), other leads, timeline (up to 8 entries shown).
- **Семья (family) section** — calls `getFamilyForEntity('lead', id)`; shows family name, member roles (parent/child/guardian/payer/sibling), primary contact and primary payer flags.
- **История статусов** — calls `getLeadStatusHistory(id)`; shows up to 12 status transitions with old→new labels, timestamp, optional comment.
- **Комментарии** — `_CommentsList` widget: `listComments(entityType: 'lead')`; inline comment input with send button; `refreshKey` integer to trigger re-fetch without invalidating provider.
- **Кандидаты на связь (duplicate detection)** — `listDuplicateCandidates(leadId)`: shows up to 4 lead↔student candidate pairs with match value and confidence %; "Связать" button calls `decideDuplicateCandidate(id, status: 'attached')`.
- **Summary chips** — counts for linked students, tasks, trials, other leads, candidates.
- **Actions:** Создать ученика (direct conversion, bypasses ConvertLeadDialog), Сохранить (PATCH lead), Отмена.
- **HollihopID** displayed in subtitle (read-only, from `lead.hollihop_id`).

### 2.7 Convert Lead Dialog (`ConvertLeadDialog`)

- Branch dropdown (pre-filled from lead's `branch_id`); validates against actual branch list.
- Discipline dropdown (per-branch, from `listBranchDisciplines`); discipline cleared if branch changes and discipline not in new branch list.
- Calls `createStudent(leadId: ..., customDataPatch: {branchId, discipline, sourceLeadId})`.
- Disabled if disciplines list is non-empty but no discipline selected.

### 2.8 Manage Entities (Admin — ManageEntitiesWidget)

7-tab tabbed view with global search and per-entity search providers:

- **Ученики tab** — `searchStudents` API; card shows: name, phone, branch, groups/lessons/tasks counts, payments total, app account status + email; tap navigates to `/student/:id` (full student detail screen via GoRouter).
- **Преподаватели tab** — `listTeachers`; card shows: name, specialization (from `disciplines` list), branches, students/lessons counts, rating, app account status.
- **Группы tab** — `listGroups`; card shows name, teacher, branch; opens `GroupDetailDialog`.
- **Занятия tab** — `listLessons(limit:50)`; card shows date/time, student or group name, teacher, room, status badge; popup: cancel / reschedule (date+time pickers → `updateLesson`).
- **Аудитории tab** — `listRooms`; card shows name, capacity, branch; edit via `CreateRoomDialog(room: item)`.
- **Сотрудники tab** — `listStaff`; card shows name, email, phone, role, position, status, branches, app account/role; opens `StaffDetailDialog`.
- **Филиалы tab** — `listBranches`; card shows name, address, UTC offset label (Moscow / CET / UTC / custom); edit via `BranchFormDialog`.
- **FAB** — opens create dialog for current tab (CreateStudentDialog / CreateTeacherDialog / CreateGroupDialog / CreateRoomDialog / CreateEmployeeDialog / BranchFormDialog); Занятия tab shows snackbar redirecting to Schedule.
- **Search** — live filter for all tabs; API-side for students/teachers/staff; client-side for groups/rooms/branches.

### 2.9 Users / Roles (Tab 4 — Пользователи, `UserRolesWidget`)

- **Profile list** — `magicProfileAdminService.listProfiles(limit: 100)`; cards show name, email, role badge (colored), phone, linked CRM entity.
- **Role filter** — chips: Все / Клиент / Преподаватель / Управляющий / Администратор / Администратор системы.
- **Search** — 350 ms debounce; `initialSearch` prop for deep-link pre-fill from "open contact" in other parts of the app.
- **Role assignment** — dropdown in profile card; roles: `client, teacher, manager, admin, system_admin`; calls `updateProfileRole`; pending indicator.
- **Link CRM entity** — "Связать с CRM" action; opens picker dialog for students/teachers; calls `linkProfileToCrmEntity`.
- **Unlink CRM entity** — removes the link.
- **Broadcast push notification** (`BroadcastDialog`) — target: all / students (role:client) / teachers (role:teacher); `adminSend` via `MagicNotificationsService`; returns recipient count.
- **Mass notification widget** (`MassNotificationWidget`) — separate widget loaded elsewhere in admin area for channel push.

### 2.10 Finance (Tab 5, desktop only — `FinanceWidget`)

- **Headline aggregate** — total received amount over period from `listPaymentsWithTotal` (server-side aggregate, not a fold over the returned page).
- **Period filter** — SegmentedButton: Нед. / Мес. / Год; triggers re-fetch.
- **Payment list** — up to 100 payments; card shows student name (tappable → `/student/:id`), payment type label, date (`payment_date` field preferred over `created_at`), note/description, amount.
- **Payment types** — subscription (Абонемент), extra_lesson (Доп. занятие), other (Прочее).
- **Add payment FAB** — `_PaymentDialog`: pick student from `listStudents(100)`, enter amount, select type; calls `createPayment(studentId, amount, paymentDate: now, method: type)`.
- **Debtors (`DebtorsWidget`)** — `listStudentBalances(debtOnly: true, limit: 100)`; shows students with negative balance; detail dialog loads payments, expected payments, and timeline for the student; "top up" button via `TopUpDialog`.
- **Conversion tracking (`ConversionTrackingWidget`)** — widget present in codebase but exact load point not confirmed in main navigation.

### 2.11 Tasks (Tab 6, desktop only — `TasksWidget`)

- **Task list** — `listTasks(q, status, entityType, assignedTo, branchId, priority, from, to, limit:100)`.
- **Status filter chips** — Все / К выполнению (open) / В работе (in_progress) / Завершены (done) / Отменены (cancelled).
- **Dropdown filters** — Объект (entity type: student/lead/group/teacher/profile/lesson), Срок (overdue/today/7 days), Приоритет (high/medium/low), Филиал, Ответственный (by user_id from profiles).
- **Search** — 350 ms debounce.
- **Overdue highlight** — due date tag rendered in danger color if `dueAt < now` and status not done/cancelled.
- **Task card** — title, description, status, due date, assignee, creator, branch, entity label (tappable for student → `/student/:id`).
- **Task status changes** (popup menu) — In work / Complete / Reopen / Cancel (cancel requires confirm dialog); optimistic update with rollback.
- **Reassign task** — popup menu → `_TaskAssigneeDialog` picker → `updateTask(id, assignedTo)`.
- **Entity timeline sheet** — `_TaskTimelineSheet`: modal bottom sheet showing timeline for `task.entity_type/entity_id`; entries typed as payment/task/comment/lesson/audit; add comment from sheet (`createComment`).
- **Create task FAB** — `_TaskDialog`: prefetches employees + students + leads + groups + teachers; fields: title, description, entity type + entity picker, assignee (optional), due date (date picker); calls `createTask(entityType, entityId, title, description?, assignedTo?, dueAt?, status: 'open')`.

### 2.12 Reports (Tab 7, desktop only — `ReportsWidget`)

4 sub-tabs:

**Аналитика tab:**
- Period selector — 3/6/12 months SegmentedButton.
- 3 KPI cards: Посещаемость (%), Выручка (₽), Занятий (count).
- Bar chart: lessons by month (planned vs completed stacked).
- Bar chart: revenue by month.
- Teacher revenue ranking table.
- Monthly detail table (lessons, new students, revenue per month).
- Data from `getFinanceReport(from, to)` → `monthly[]`, `summary`, `teachers[]`, (implicitly `rooms[]` used in financial dashboard).

**Финансы tab (`FinancialDashboardWidget`):**
- 6-month financial dashboard using `fl_chart` library.
- Monthly financials line/bar chart.
- Teacher efficiency table (name, completed lessons, revenue).
- Room load bar/table (room name → lesson count).
- Data from same `getFinanceReport` endpoint.

**Активность tab (`_ActivityLogTab`):**
- Activity audit log from `listActivityLog(q, entityType, from, to, limit:100)`.
- Period filter: 7 days / month / quarter.
- Entity type filter: all/student/lead/teacher/staff/lesson/task.
- Search field (350 ms debounce).
- Tiles show: action icon (create/update/delete), description, actor name, actor role, entity type, history type tags, timestamp.

**Управление tab (`ManagementDashboardWidget`):**
- Funnel section — from `getAnalyticsFunnel()`: conversion rates between funnel stages.
- Debts section — from `getAnalyticsDebts()`: aggregate debt metrics.
- Forecast section — from `getAnalyticsForecast()`: revenue forecast.
- Branches section — from `getAnalyticsBranches()`: per-branch performance.
- Churn section — from `getAnalyticsChurn()`: churn rate / at-risk students.
- Chat SLA section — from `getAnalyticsChatSla()`: response time metrics.
- Loss reasons section — from `getAnalyticsLossReasons()`: why leads were lost.

### 2.13 Lead Status Management (`ManageStatusesDialog`)

- List all lead statuses (from `leadStatusesProvider`).
- Add status: key (slug), label, color picker → `createLeadStatus(key, label, color, sortOrder)`.
- Edit status label/color in-place → `updateLeadStatus`.
- Reorder via `ReorderableListView` → calls `updateLeadStatusSortOrders` for all items.
- Delete status → `deleteLeadStatus`; invalidates `leadStatusesProvider`.

### 2.14 Custom Field Configuration (`CustomFieldConfigWidget`)

- Load fields from `getCrmCustomFields()`; stored under `magic_settings`.
- Entity scope selector — students / leads.
- Field types: text, number, phone, email, url, select, boolean, date.
- Required flag, label, key (slug), hint text, options (comma-separated for select type).
- Create new field, edit existing (in-place), delete field (removes from list).
- Save all → `updateCrmCustomFields(fields)`.
- Fields appear in LeadDetailDialog and student detail.

### 2.15 Admin-specific Widgets

- **`AdminChatDashboard`** — legacy/alternative chat view embedded in admin area; shows school inbox and per-student chat; includes file picker, voice recorder, lead card open, broadcast trigger.
- **`BroadcastDialog`** — push notification broadcast to all / students (role:client) / teachers (role:teacher); calls `adminSend`; shows recipient count.
- **`MassNotificationWidget`** — channel push notification widget (exact load location not confirmed).
- **`TopUpDialog`** — add payment/top-up from debtors widget; student and amount fields.
- **`StudentDetailScreen`** (`lib/features/admin/presentation/screens/student_detail_screen.dart`) — full student card screen accessed via `/student/:id` route.

### 2.16 Student Detail Screen (`/student/:id`)

- Accessed from: student list in ManageEntities, payment list, tasks, finance widget.
- Full-featured screen (separate from kanban card popup):
  - Personal info (name, phone, email, branch).
  - Groups membership.
  - Lesson history with attendance.
  - Payment history.
  - Task list.
  - Custom fields.
  - Timeline.
  - Comments.

### 2.17 Provider / Data Layer

- `leadBoardProvider(filters)` — `FutureProvider.family`; fetches board with cursor pagination.
- `leadsStreamProvider` — legacy alias; flattens board columns to a flat list.
- `leadStatusesProvider` — `FutureProvider`; list of all lead statuses.
- `LeadFilterPresetStore` — `FlutterSecureStorage`-backed preset persistence.
- `studentBoardProvider(branchId)` — `FutureProvider.family`; students grouped by discipline columns.
- `analyticsFunnelProvider`, `analyticsDebtsProvider`, `analyticsBranchesProvider`, `analyticsForecastProvider`, `analyticsChurnProvider`, `analyticsChatSlaProvider`, `analyticsLossReasonsProvider` — all `FutureProvider.autoDispose`.
- `entitiesProvider(table)` — `FutureProvider.family` for ManageEntities tabs.
- `studentSearchProvider(query)`, `teacherSearchProvider(query)`, `staffSearchProvider(query)` — `FutureProvider.family`.
- `appLeadsCountProvider` — drives the unread badge on the Clients nav tab.

---

## 3. Per-Role Behavior / Permissions

| Feature | system_admin | admin | manager | teacher | client |
|---|---|---|---|---|---|
| CRM nav rail (8 tabs) | Yes | Yes | Yes | No (3 tabs) | No |
| Finance / Tasks / Reports tabs | Yes (desktop) | Yes (desktop) | Yes (desktop) | No | No |
| Clients (Лиды + Ученики) | Yes | Yes | Yes | No | No |
| Manage entities (7-tab) | Yes | Yes | Yes | No | No |
| User roles management | Yes | Yes | Yes | No | No |
| Schedule (read+write) | Yes | Yes | Yes | Yes (read+write, own scope) | No |
| Post to channels | Yes | Yes | Yes | No | No |
| Broadcast push | Yes | Yes | No (widget hidden?) | No | No |
| Delete moderated messages | No (UI says own only) | No | No | No | No |
| Lead CRUD | Yes | Yes | Yes | No | No |
| Admin overview | Yes | Yes | No (manager overview) | No | No |
| Chat (direct + groups) | Yes | Yes | Yes | Yes | Yes (admin chat only) |
| Save contact from chat | Yes | Yes | Yes | Yes | No |
| Open CRM card from chat | Yes | Yes | Yes | Yes | No |

`_isAdminRole` = `admin || system_admin`; `_isManagerOrAdminRole` = admin + manager; `_isStaffRole` = admin + manager + teacher.

Teachers see only 3 tabs: Чат / Расписание / Ученики (`TeacherScheduleWidget`, `TeacherStudentsWidget`).

---

## 4. Data / Schema Touched

### Entities read and written

| Entity | Fields used |
|---|---|
| **Lead** | id, name, last_name, phone, email, status (UUID), branch_id, notes, source, assigned_name, linked_student_id, open_tasks_count, comments_count, trial_lessons_count, created_at, custom_data (discipline, level, branchId, hollihop_id, sourceLeadId + custom schema fields), hollihop_id |
| **Lead status** | id/key, label, color, sort_order |
| **Student** | first_name, last_name, phone, email, branch_id/branch_name, status, groups_count, lessons_count, open_tasks_count, payments_total, linked_user_id, linked_user_email, is_app_account, custom_data |
| **Teacher** | first_name, last_name, disciplines (list of {Name}), specialization, branches (list), students_count, lessons_count, rating, is_app_account, app_role |
| **Lesson** | student_id/student_name, teacher_id/teacher_name, room_id/room_name, group_id/group_name, scheduled_at, status (scheduled/completed/cancelled), notes, is_trial, lead_id |
| **Group** | name, teacher_id, branch_id |
| **Room** | name, capacity, branch_id |
| **Branch** | name, address, utc_offset_minutes |
| **Staff/Employee** | first_name, last_name, email, phone, role, position, status, branches (list), is_app_account, app_role |
| **Payment** | student_id, amount, type (subscription/extra_lesson/other), payment_date, notes/description |
| **Task** | title, description, entity_type, entity_id, entity_name, assigned_to, assigned_name, creator_name, status (open/in_progress/done/cancelled), due_date, priority (high/medium/low), branch_name |
| **Comment** | entity_type, entity_id, body, author_name, created_at |
| **Activity log** | action, description, entity_type, actor_name, actor_role, history_type, created_at |
| **Timeline entry** | type (payment/task/comment/lesson/audit), title, body, amount, status, occurred_at, actor_name |
| **Profile** | user_id, first_name, last_name, email, role, phone, linked CRM entity |
| **Duplicate candidate** | id, entity_type_a/b, entity_id_a/b, entity_a/b (embedded), match_value, confidence |
| **Family** | name, primary_payer_member_id; members: id, name, role, is_primary_contact |
| **Status history** | old_status, new_status, changed_at, comment |
| **Chat** | id, _item_type (direct/group/channel), _display_name, _partner_id, _last_message, unread_count, is_muted, is_pinned |
| **Message** | id, chat_id, sender_id, content, message_type (text/file/image/voice), attachment_file_id, attachment_name, attachment_size, attachment_mime_type, reply_to_id, forwarded_from_id, pinned_by, pinned_at, created_at, updated_at, deleted_at, is_read, reactions (list of {user_id, emoji}), profiles (embedded sender) |
| **CRM custom field definition** | entity (students/leads), key, label, type, required, hint, options (list) |

### External systems

- **HollihopService**: read-only; provides disciplines, levels, categories (used as filter metadata for lead board).

### Local persistence

- `FlutterSecureStorage` key `crm.lead_filter_presets.v1`: JSON array of `{name, filters}` objects.

---

## 5. Notable Business Rules / Edge Cases

1. **Lead status UUID validation**: The "Без статуса" column uses the sentinel string `"unassigned"` (not a UUID). `_moveStatus()` detects non-UUID column IDs via regex and sends `clearStatus: true` instead of a `statusId`. Sending the raw column ID to the server was a noted past bug ("statusId must be a UUID").

2. **Lead conversion undo is cosmetic only**: The "Отменить" SnackBar on lead→student conversion only re-shows the lead card in the UI. The created student record is not deleted. The snackbar explicitly warns users of this.

3. **Kanban auto-scroll is poll-based (16 ms timer)**: During drag, a `Timer.periodic(16ms)` fires while near screen edges. Timer is created only once but the `_autoScrollDir` float controls speed. If `onDragEnd` / `onDraggableCanceled` / `onDragCompleted` are all missed, the timer may not stop — `dispose()` cancels it as a fallback.

4. **Filter preset storage uses FlutterSecureStorage (not SharedPreferences)**: Presets are stored in the system keychain/keystore — deletion on app uninstall may not clear them on all platforms (iOS keychain survives reinstall by default).

5. **Cursor pagination on leads board is per-board, not per-column**: The `next_cursor` is a board-level cursor; loaded extra leads are sorted into columns client-side by `statusId`. Columns without more data will receive no new items on "load more" without showing per-column feedback.

6. **"Без статуса" column is server-generated**: The board endpoint returns a column keyed `"unassigned"` for leads without a status. Its presence depends on server logic, not client configuration. ManageStatusesDialog therefore cannot delete or reorder it.

7. **Student board is read-only (v1)**: `StudentsBoardWidget` explicitly documents "no drag-and-drop in v1". There is no context menu or status-change action on student cards.

8. **Mobile navigation hides Finance / Tasks / Reports**: The `_maxCrmTab(isDesktop)` returns `4` on mobile, cutting off tabs 5–7. These are unreachable on mobile except via `crmNavigationRequestProvider` deep-link or Overview card tap. The taps in Overview call `_handleOverviewTabChange` which maps to tab indices — but on mobile some mappings redirect to tab 4 (Users) instead of Finance/Tasks/Reports.

9. **Channel posting permission**: Only `_isManagerOrAdminRole` can call `createChannelPost`. The input bar is rendered for all roles but the send is guarded by `_canPostToChannel()`. No visible disabled state for non-managers reading a channel — they can type but send will silently fail if the guard is enforced server-side (UI does not show a "read-only" label).

10. **Duplicate candidate auto-detection**: `listDuplicateCandidates` is called on every lead card open. The `_isCurrentLeadDuplicateCandidate` filter on client side means the server may return candidates for other leads in batch; only those matching the current lead are displayed. No deduplication after `decideDuplicateCandidate` except via re-fetch.

11. **HollihopID exposed in lead card subtitle**: `lead.hollihop_id` is displayed read-only in the lead detail dialog header. No field validation or mapping is performed client-side; an empty string renders as "—".

12. **Family roles**: Recognized: parent, child, guardian, payer, sibling. Unknown roles fall through to the raw string. No CRUD for family from the lead card — the section is read-only (no add/remove member button).

13. **Status history capped at 12 entries**: `_statusHistory.take(12)` — older transitions silently hidden; no "load more" button.

14. **Finance headline uses server aggregate, not client fold**: `listPaymentsWithTotal` returns both a `totalAmount` (server-side, full period) and a capped `items` list (up to 100). If total count > 100, a note is shown. The headline is always accurate; individual rows may be truncated.

15. **Task cancellation requires confirmation; other status changes do not**: `cancelled` status triggers an `AlertDialog`; moving to `in_progress` or `done` does not. This asymmetry may surprise power users.

16. **Payment date vs created_at**: `FinanceWidget` explicitly prefers `payment_date` over `created_at` to avoid late-entered payments appearing in the wrong period — correctly handling back-dated payment entry.

17. **Branch UTC offset is fixed (no DST)**: `_branchOffsets` stores `utc_offset_minutes`; applied as a fixed offset. Russia abolished DST in 2014, so this is correct for Russian branches. International branches using DST-observing zones would display incorrect times.

18. **Auto-branch retry for empty schedule**: `ScheduleWidget` has a `_autoBranchRetried` boolean guard to prevent an infinite re-fetch loop when all branches genuinely have no lessons.

19. **LeadDetailDialog `_edited` flag is set on any field change, including toggling the international phone mode**: A user toggling the international checkbox without changing any actual data will trigger the "unsaved changes" confirmation on close.

20. **XLSX export**: No XLSX export was found in the admin or manager feature code. The audit scope did not reveal any export-to-Excel functionality within `lib/features/admin` or `lib/features/manager`.
