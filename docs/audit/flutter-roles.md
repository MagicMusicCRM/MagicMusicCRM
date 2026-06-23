# Flutter Roles & Features Audit
**Scope:** `lib/features/teacher`, `lib/features/client`, `lib/features/profile`, `lib/features/auth`, plus the shared messenger shell (`lib/features/messenger`), app router (`lib/core/router/app_router.dart`), and CRM service (`lib/core/services/magic_crm_service.dart`).

---

## 1. Overview

MagicMusicCRM is a Flutter app (Riverpod + go_router) that serves multiple roles through a single unified codebase. After login, a "release gate" check fetches `ReleaseGateStatus` from `/legal/gate` and routes the user into a role-specific shell. All roles share the same Telegram-style `MessengerScreen` as their root widget; role-specific CRM panels are tabs inside that shell. The four in-scope roles are: `client`, `teacher`, `manager` (partially in scope via the shell), and `admin`/`system_admin`.

Authentication is custom (not Supabase directly): all auth calls go to a REST backend (`/auth/*`). Sessions are stored as token pairs (access + refresh) on device. The gate check and profile completion are blocking — users cannot reach their dashboard until the gate passes.

---

## 2. Features — Exhaustive Inventory

### Auth / Login
- **Login screen** (`/login`) — email + password form; shows error messages mapped from backend codes; navigates to `/email-otp` if MFA is required or if email is unverified.
- **Registration screen** (`/register`) — collects full name, email, password (min 6 chars), confirm password; sends to `POST /auth/signup`; redirects to `/email-otp` for signup OTP verification if no session is returned immediately.
- **Email OTP screen** (`/email-otp`) — dual-purpose: verifies signup email (`EmailOtpPurpose.signup`) or satisfies 2FA after password login (`EmailOtpPurpose.passwordMfa`); 6-digit numeric code; resend capability; back-to-login link.
- **Password reset screen** (`/password-reset`) — two-phase: (1) enter email → `POST /auth/password-reset/request`; (2) enter token from email + new password (min 10 chars) → `POST /auth/password-reset/confirm`; both phases on one screen with conditional field reveal.
- **Sign-out** — clears tokens locally, notifies Sentry, emits `null` on session stream.
- **Logout all devices** — `POST /auth/logout-all` then clears local tokens.
- **Sentry integration** — auth breadcrumbs for `password_login` and `signup` flows; Sentry user set/cleared on session change with role tag.

### Release Gate / Onboarding
- **App gate loading screen** (`/`) — spinner while `ReleaseGateStatus` loads; shows retry + sign-out buttons if gate returns a non-401 error.
- **Onboarding screen** (`/onboarding`) — collects first name, last name, phone via `PATCH /profile/me`; also calls `POST /messenger/chats/direct` with `type: 'administration'` to pre-create the admin chat thread; blocks access until profile is complete.
- **Legal consent screen** (`/legal-consent`) — fetches all current legal documents from `GET /legal/documents/current`; user must individually tick every document; calls `POST /legal/consents/current` with document IDs; then redirects to role route.
- **Legal documents viewer** (`/legal-documents`) — same screen in read-only mode (no checkboxes, no accept button); accessible from profile at any time.
- **Gate status fields:** `role`, `profileComplete`, `legalAccepted`, `deletionPending` — all checked on every navigation event.

### Router / RBAC
- **Role-to-route mapping:** `admin`/`system_admin` → `/admin`; `manager` → `/manager`; `teacher` → `/teacher`; everything else → `/client`.
- **Proactive role enforcement:** any attempt to navigate to `/admin`, `/manager`, `/teacher`, or `/client` while logged in as a different role is redirected to the correct role route.
- **Gate redirect chain:** `deletionPending` → `/account-deletion-status` (locked out); `!profileComplete` → `/onboarding`; `!legalAccepted` → `/legal-consent`; all three must pass before the role shell loads.
- **Auth-only routes:** `/login`, `/register`, `/email-otp`, `/password-reset` — accessible only when signed out; signed-in users are redirected to their role route.
- **Shared authenticated routes:** `/profile`, `/auth-methods`, `/delete-account`, `/account-deletion-status`, `/legal-documents`, `/student/:id` — accessible to any authenticated role without role restrictions in the router (no per-route RBAC enforcement beyond the gate).
- **`/student/:id`** — `StudentDetailScreen` is linked from the router and is accessible to any authenticated user with the URL (no role check at the route level).

### Teacher Role
- **Messenger shell (tab 0)** — teacher sees the same Telegram-style chat list as other roles; can send text, voice, file messages; can reply to and forward messages; can delete own messages; reactions; typing indicators; online presence.
- **Teacher schedule (tab 1)** — Syncfusion calendar showing only this teacher's lessons (fetches `GET /crm/teachers?limit=1` to get own teacher record, then `GET /crm/lessons?teacherId=...`); supports day/week/month/schedule views; per-appointment status colour (gold=scheduled, green=completed, red=cancelled); lesson detail popup on tap.
  - **Mark lesson completed** — calls `updateLesson(id, status: 'completed')`.
  - **Edit lesson plan** — text dialog writes `notes` field via `updateLesson(id, notes: ...)`.
  - **Mark attendance** — opens `LessonAttendanceDialog` (shared admin widget) from both the calendar card shortcut and the detail popup; backend permits teacher role (KVA-152).
  - **UTC+3 hardcoded offset** — `scheduled_at` from DB is treated as UTC and shifted +3 h on display; no timezone configuration.
  - **Duration parsing bug guard** — `duration_minutes` may arrive as int, double, or string; fallback to 60 min (KVA-166).
- **Teacher students (tab 2)** — list of all students (not filtered to this teacher's students — calls `GET /crm/students?limit=100` globally); annotated with lesson count derived from join of `listLessons(teacherId=...)` and `listStudents`; expandable card shows phone and `custom_data.notes` / `custom_data.level`; pull-to-refresh.
- **Teacher chat contacts** — separate `TeacherChatWidget` (used by an older entry point, not the main messenger shell); lists all students (again globally unfiltered) who have a `profile_user_id`; per-chat unread badge; real-time via `MagicRealtimeConnection`.
- **What a teacher CANNOT do (enforced by nav/UI):**
  - No access to Overview, Clients, Finance, Tasks, Reports, or User Management tabs (max tab index = 2).
  - No "Save as lead" or "Save as student" CRM actions from chat (those helpers are only invoked for `_isManagerOrAdminRole`).
  - No group/channel creation (only `_isManagerOrAdminRole` can create groups; channel posting requires `_isManagerOrAdminRole`).
  - Cannot access `/admin` or `/manager` routes (router redirects).
  - No access to student detail screen from within the teacher shell (no link provided in teacher tabs — but the URL `/student/:id` is not role-gated in the router, so a teacher who knows the URL can reach it).

### Client Role
- **Client dashboard screen** (`/client`) — thin wrapper that renders `MessengerScreen(role: 'client')`; no CRM tabs; clients only see the chat shell.
- **Client chat widget (`ChatWidget`)** — dropdown to select recipient: "Администрация" (group chat) or any teacher (direct chat); sends text, voice (mic recording), file (up to 25 MB); read receipts (double-tick); real-time via websocket; unread badge per contact.
- **Client portal screen (`ClientPortalScreen`)** — accessible as a tab panel inside the messenger shell for the client role:
  - **Child switcher** — horizontal chip row, hidden when ≤1 linked student; appears for parent accounts with 2+ students (KVA-156); selection drives `selectedStudentIdProvider` which all portal data providers derive from.
  - **Subscription status card (`SubscriptionStatusCard`)** — fetches `GET /crm/subscriptions?studentId=...&limit=1`; shows subscription type (uppercased), remaining lesson count, expiry date, and a warning banner when ≤7 days or ≤2 lessons remaining or exhausted; shows "contact admin" prompt when no subscription.
  - **Upcoming lessons list (`UpcomingLessonsList`)** — two tabs: "Предстоящие" (future lessons, limit 20) and "История" (past lessons, limit 50); each card shows date/time, teacher name, branch, room, duration, status badge; pull-to-refresh.
  - **Next lesson countdown (`NextLessonCountdown`)** — live countdown widget updating every 30 seconds; shows teacher name and time remaining; auto-hides when no upcoming lesson or the next one is in the past.
  - **Progress notes (`ProgressNotesWidget`)** — fetches lesson comments tagged `[PROGRESS]` from `GET /crm/progress-notes?studentId=...`; strips the prefix tag before display; read-only for clients.
  - **Homework widget (`HomeworkWidget`)** — fetches tasks from `GET /crm/tasks` (no studentId filter — returns tasks assigned to the current user); checkbox to toggle status between `open` and `done` via `updateTaskStatus`; clients CAN mark their own homework done.
- **What a client CANNOT do:**
  - No CRM tabs (Overview, Schedule, Clients, Finance, Tasks, Reports, User Management).
  - Cannot create group chats or post to channels.
  - Cannot access any `/admin`, `/manager`, or `/teacher` routes.
  - Cannot modify subscriptions, lessons, or student records.

### Profile
- **Profile screen (`/profile`)** — editable fields: first name (required), last name, phone, date of birth (date picker); avatar upload (via `AvatarCropperDialog`, then `chatAttachmentServiceProvider.uploadAvatar`); old avatar deleted on replacement; role displayed as read-only label (mapped to Russian strings); save button appears only when changes detected; responsive (FAB on desktop, AppBar action on mobile); skeleton loading state.
- **Auth methods screen (`/auth-methods`)** — shows current user email; toggle for email OTP MFA (enabled/disabled via `PATCH /profile/me { emailOtp2faEnabled }`); list of login identities (currently only `email` provider shown); form to set or update password (min 10 chars); MFA toggle disabled until `email` identity is present.
- **Legal documents screen (`/legal-documents`)** — read-only view of current legal docs (same `LegalConsentScreen` with `requireAcceptance: false`); each document is an expandable tile with a link to the public URL on `magicmusiccrm-legal.vercel.app`.
  - Legal doc types with public URLs: `privacy_policy`, `terms_of_use`, `account_deletion`.
- **Account deletion screen (`/delete-account`)** — user enters optional reason text; must tick acknowledgement checkbox; submits `POST /profile/deletion-request { acknowledgement: true, reason? }`; redirects to deletion status screen.
- **Account deletion status screen (`/account-deletion-status`)** — watches `pendingDeletionRequestProvider`; shows request status (`pending` / `processing`); sign-out button; if `deletionPending` is true in gate status, user is hard-locked to this route and cannot reach any other screen.
- **Logout (via popup menu in messenger shell)** — calls `magicAuthService.signOut()` which clears tokens and emits null session, triggering router redirect to `/login`.

### Messenger Shell (shared by all roles)
- **Chat list** — lists direct chats, group chats, and channels; pinned chats sort first; sorted by last message time; search by name; unread count badges; muted chat indicator.
- **Real-time messaging** — websocket connection via `MagicRealtimeService`; events: `message.created`, `message.updated`, `channel_post.created`, `chat.updated`, `typing.start`, `typing.stop`, `presence.updated`.
- **Typing indicators** — broadcast on input; auto-stop after 3 seconds of inactivity.
- **Online presence** — per-chat user presence tracking.
- **Message features:** text, voice (recording + playback), file/image attachments (up to 25 MB); reply to message; edit own messages; delete own messages (soft-delete with confirmation); forward messages to any chat; emoji reactions (optimistic update); pinned messages bar per chat.
- **In-chat search** — search within message history of selected chat.
- **Notification deep links** — `messengerNavigationProvider` carries pending navigation; checked on mount and after chat list load; opens correct chat from push notification tap.
- **Local push notifications** — `NotificationService.showLocalNotification` fires for incoming messages in non-selected, non-muted chats.
- **Group chat creation** — available to `manager` and `admin`/`system_admin` roles only.
- **Channel posting** — available to `manager` and `admin`/`system_admin` roles only; teachers and clients can read channels but not post.
- **CRM actions from chat header (staff only):** "Save as lead", "Save as student" (`POST /crm/contacts/from-chat`); "Open contact card" (resolves to `/student/:id` or `LeadDetailDialog`).
- **Profile panel** — `ChatInfoDialog` on right side; shows chat info, mute toggle, member list, shared media navigation.
- **Theme toggle** — dark/light via popup menu; persisted via `themeProvider`.
- **Desktop drag-and-drop** — file drop onto chat window via `desktop_drop` package.

---

## 3. Per-Role Behaviour / Permissions

| Capability | client | teacher | manager | admin/system_admin |
|---|---|---|---|---|
| Chat (direct/group/channel read) | Yes | Yes | Yes | Yes |
| Send text/voice/file | Yes | Yes | Yes | Yes |
| Delete own messages | Yes | Yes | Yes | Yes |
| Create group chats | No | No | Yes | Yes |
| Post to channels | No | No | Yes | Yes |
| CRM Overview tab | No | No | Yes | Yes |
| Schedule tab | No | Yes (own lessons) | Yes (all) | Yes (all) |
| Students/Clients tab | No | Yes (view-only list, globally unfiltered) | Yes | Yes |
| Finance tab | No | No | Yes (desktop only) | Yes (desktop only) |
| Tasks tab | No | No | Yes (desktop only) | Yes (desktop only) |
| Reports tab | No | No | Yes (desktop only) | Yes (desktop only) |
| User Management tab | No | No | Yes | Yes |
| Save contact as lead/student | No | No | Yes | Yes |
| Mark lesson completed | No | Yes | Yes | Yes |
| Edit lesson plan/notes | No | Yes | Yes | Yes |
| Mark attendance | No | Yes (KVA-152) | Yes | Yes |
| Subscription portal | Yes (view) | No | Yes (manage) | Yes (manage) |
| Homework completion | Yes (own) | No | Yes (manage) | Yes (manage) |
| Progress notes | Yes (read-only) | No | Yes | Yes |
| Account deletion request | Yes | Yes | Yes | Yes |
| Legal docs acceptance | Yes (all users) | Yes | Yes | Yes |
| MFA toggle | Yes (all users) | Yes | Yes | Yes |
| Password management | Yes (all users) | Yes | Yes | Yes |
| Profile edit | Yes (all users) | Yes | Yes | Yes |

---

## 4. Data / Schema Touched

### Auth & Profile endpoints
- `POST /auth/login` — `{ email, password }` → `{ session, user, emailOtpRequired }`
- `POST /auth/signup` — `{ email, password, fullName }` → `{ user, emailVerificationRequired }`
- `POST /auth/logout-all`
- `POST /auth/otp/request` — `{ email }`
- `POST /auth/otp/verify` — `{ email, code }` → `{ session, user }`
- `POST /auth/password-reset/request` — `{ email }`
- `POST /auth/password-reset/confirm` — `{ token, password }`
- `POST /auth/password` — `{ password }` (set password for authenticated user)
- `GET /auth/identities` → `{ items: [{ provider }] }`
- `GET /profile/me` → `MagicAuthProfile { userId, email, role, firstName, lastName, phone, dob, avatarFileId, emailOtp2faEnabled }`
- `PATCH /profile/me` — updates any subset of profile fields including `emailOtp2faEnabled`

### Release Gate endpoints
- `GET /legal/gate` → `ReleaseGateStatus { role, profileComplete, legalAccepted, deletionPending }`
- `GET /legal/documents/current` → `LegalDocument[] { id, document_type/documentType/type, title, version, content }`
- `POST /legal/consents/current` — `{ documentIds: string[] }`
- `POST /profile/deletion-request` — `{ acknowledgement: true, reason? }` → `{ id }`
- `GET /profile/deletion-request` → `AccountDeletionRequest? { id, status, reason, requested_at/requestedAt }`

### CRM endpoints (client + teacher)
- `GET /crm/me` → `{ students: [...] }` (parent/client's linked students)
- `GET /crm/students?limit=N` → all students (teacher accesses this globally)
- `GET /crm/students/search?q=...` — multiple filter params
- `GET /crm/teachers?limit=N` — teacher fetches own record via this
- `GET /crm/lessons?teacherId=...&studentId=...&from=...&to=...&limit=N`
- `PATCH /crm/lessons/:id` — `{ status?, notes? }` (teacher: mark completed, edit plan)
- `GET /crm/subscriptions?studentId=...&limit=1`
- `GET /crm/tasks` — returns tasks for current user (no studentId param in client code)
- `PATCH /crm/tasks/:id/status` — `{ status: 'done'|'open' }`
- `GET /crm/progress-notes?studentId=...`
- `POST /crm/contacts/from-chat` — `{ userId, as: 'lead'|'student' }` (staff only)
- `GET /crm/contacts/resolve?userId=...` — resolves userId to studentId or leadId (staff only)

### Messenger endpoints
- `GET /messenger/chats?limit=N`
- `GET /messenger/channels`
- `POST /messenger/chats/direct` — `{ type: 'administration' }` or `{ targetUserId }` for teacher–student direct chats
- `GET /messenger/chats/:id/messages?limit=N`
- `POST /messenger/chats/:id/messages` — `{ content, messageType?, attachmentFileId?, replyToId?, forwardedFromId? }`
- `PATCH /messenger/messages/:id` — `{ content }` (edit)
- `DELETE /messenger/messages/:id?mode=own|moderated`
- `POST /messenger/chats/:id/read` — `{ lastReadMessageId }`
- `PATCH /messenger/chats/:id/mute` — `{ isMuted }`
- `POST /messenger/messages/:id/reactions` — `{ emoji }`
- `DELETE /messenger/messages/:id/reactions/:emoji`
- `GET /messenger/chats/:id/pinned`
- `GET /messenger/channels/:id/posts`
- `POST /messenger/channels/:id/posts` — `{ content }` (staff only)
- Realtime websocket events: `message.created`, `message.updated`, `channel_post.created`, `chat.updated`, `typing.start`, `typing.stop`, `presence.updated`

### Entity models
- `MagicAuthSession` — `{ accessToken, refreshToken }`
- `MagicAuthUser` — `{ id, email, role, emailVerified }`
- `MagicAuthProfile` — `{ userId, email, role, firstName, lastName, phone, dob, avatarFileId, emailOtp2faEnabled }`
- `MagicAuthIdentity` — `{ provider }`
- `ReleaseGateStatus` — `{ role, profileComplete, legalAccepted, deletionPending }`
- `LegalDocument` — `{ id, type, title, version, content }` (with hardcoded public URLs per type)
- `AccountDeletionRequest` — `{ id, status, reason, requestedAt }`
- Student (Map) — `first_name, last_name, phone, email, id, profile_user_id, custom_data.{ notes, level }`
- Lesson (Map) — `id, scheduled_at, duration_minutes, status, notes, student_id, student_name, teacher_id, room_name, branch_name`
- Subscription (Map) — `type, lessons_total, lessons_used, valid_until`
- Task (Map) — `id, title, description, status, created_at`
- Progress Note (Map) — `content, created_at` (content prefixed with `[PROGRESS] `)

---

## 5. Notable Business Rules / Edge Cases

1. **Release gate is a strict sequential funnel.** `deletionPending` wins over all other checks — a user with a pending deletion request is immediately locked out to `/account-deletion-status` and cannot navigate anywhere else until an admin processes the request. A user with `!profileComplete` cannot see legal docs until onboarding is done. A user with `!legalAccepted` cannot reach their dashboard.

2. **Unauthorized gate error triggers auto-signout.** If `/legal/gate` returns a 401, the router listener calls `signOut()` automatically, preventing a stuck loading state.

3. **Teacher student list is not scoped to the teacher.** `TeacherStudentsWidget` calls `listStudents(limit: 100)` globally, not filtered to this teacher's assigned students. A teacher sees all students in the school. The lesson-count annotation is teacher-scoped, but the list itself is not. This is a data exposure risk.

4. **UTC+3 timezone offset is hardcoded** in `TeacherScheduleWidget` and `UpcomingLessonsList` (`dt.toUtc().add(Duration(hours: 3))`). Schools in other timezones will show incorrect times.

5. **Password minimum length differs between screens.** Registration requires min 6 characters; password reset and auth-methods screens require min 10. These are not consistent.

6. **Homework provider has no student-scope filter.** `HomeworkWidget` calls `listTasks()` with no `studentId` parameter. For a parent with multiple children, the switcher selection has no effect on homework shown. All tasks for the logged-in user account are returned.

7. **`/student/:id` route is accessible to any authenticated role.** The router applies no role guard on `/student/:id`. A teacher or client who knows a student ID can navigate directly to the admin student detail screen.

8. **Email validation differs between login and registration screens.** Login uses a proper regex (`^[^@\s]+@[^@\s]+\.[^@\s]+$`); registration uses a simple `v.contains('@')` check, which would pass invalid addresses.

9. **Account deletion is soft (admin-processed).** The app submits a request; an admin must manually process it. The user retains read access to chat messages during the pending period but is locked out of the rest of the app.

10. **Child switcher defaults to first student, not persisted.** `selectedStudentIdProvider` is a `StateProvider` in memory; switching children is lost on app restart or session refresh.

11. **Chat OTP MFA is per-account, not per-role.** Any role can enable/disable email OTP MFA from the auth methods screen. There is no policy enforcement requiring MFA for higher-privilege roles (admin/manager).

12. **Onboarding also creates the admin chat thread.** `ensureAdminChatThread()` is called silently on onboarding completion; failure is swallowed (`debugPrint` only), so if it fails the client may not have an administration chat pre-created and will have it created on first chat load instead.

13. **Teacher lesson scheduling and cancellation are not available.** Teachers can mark lessons complete, edit notes/plan, and mark attendance, but cannot create, reschedule, or cancel lessons from the teacher shell. Those operations exist only in admin/manager widgets.

14. **Legal document public URLs are hardcoded** in `LegalDocument.publicUrl` for three known types (`privacy_policy`, `terms_of_use`, `account_deletion`). Any other document type returns `null` and shows an error snackbar.

15. **Duration_minutes defensive parsing (KVA-166).** The backend inconsistently returns this field as int, double, or string. The teacher schedule defensively parses it; the client upcoming lessons assumes it is always `int?` and defaults to 60. If the backend sends a non-int for clients, the display still works (Dart's null-safe cast returns null → fallback to 60 min).

16. **Realtime connection is not reconnected on network interruption.** `MessengerScreen._connectRealtime()` connects once on mount; there is no reconnect-on-drop logic visible in the client code. Dropped connections leave the UI stale until the user navigates away and back.
