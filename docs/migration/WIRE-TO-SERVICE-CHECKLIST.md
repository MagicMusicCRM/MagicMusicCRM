# Wire-to-Service Checklist — v7 Reskin (per-screen API gate)

**Phase:** P0-4 (KVA-193) · **Source:** `REDESIGN-MIGRATION-PLAN.md` §2 (coverage matrix) + §4 phase file-lists + §5a strategy
**Status:** SEEDED — one row per v7 screen/component. Every row must be **filled and verified** before that screen's reskin PR opens.

---

## Why this exists (§5a)

> A reskin is a screen that **issues the exact same API calls** as the screen it replaces. The single biggest risk is a reskinned screen quietly changing its calls. Before writing any UI for a v7 screen, fill its row here: **{v7 screen → existing Flutter widget it replaces → exact service methods → exact endpoints → RBAC roles}**, all derived from the §2 matrix.

**Rules:**
- A screen may **not** be reskinned until its row is complete and its network baseline is captured (`test/baseline/<screen>.json`, §5b).
- A service method **not already in the §2 matrix** means the screen is doing something new → **escalate** (likely an orphan or a contract change; see §3 of the plan).
- Pure-frontend phases (P1, P3, P4, P5-UI) must keep `git diff server/` **empty** (§5e). Service request/response code in `lib/core/services/*` must **not** change — only call sites move.

**Status legend:** `☐ seeded` (row drafted from matrix) · `◑ baseline` (network trace captured) · `☑ wired` (reskin merged, diff empty-or-additive, RBAC matrix green).

**RBAC shorthand:** `C`=client `T`=teacher `A`=admin (Администратор) `M`=manager (Управляющий) `S`=system_admin. Writes default to `M/A/S` via `assertCanWriteCrm`. After P1, **`A` loses manager-only nav** (Пользователи/Отчёты/Финансы/Настройки/Задачи) — see [§ RBAC enforcement](#rbac-enforcement-a1--p1).

---

## P1 — RBAC + nav shell + auth (`backend-platform.md` §J)

| v7 screen / component | Replaces (Flutter file) | Service method(s) | Endpoint(s) | RBAC | Status |
|---|---|---|---|---|---|
| Login | `auth/.../login_screen.dart` | `MagicAuthService.login` | `POST /auth/login` | all | ☐ seeded |
| Signup → OTP (v7p2-1) | `registration_screen.dart`, `email_otp_screen.dart` | `signup`, `requestOtp`, `verifyOtp` | `POST /auth/signup`, `/auth/otp/request`, `/auth/otp/verify`, `/auth/verify-email` | all | ☐ seeded |
| 2FA / OTP boxes | `email_otp_screen.dart` | `requestOtp`, `verifyOtp` | `POST /auth/otp/{request,verify}` | all | ☐ seeded |
| Forgot → code → new pass | `password_reset_screen.dart` | `requestPasswordReset`, `confirmPasswordReset`, `setPassword` | `POST /auth/password-reset/{request,confirm}`, `/auth/password` | all | ☐ seeded |
| Auth methods (MFA toggle, identities, logout-all) | auth-methods screen | `listIdentities`, `refresh`, `logoutAll` | `GET /auth/identities`, `POST /auth/{refresh,logout-all}` | self | ☐ seeded |
| Onboarding slides → consent (v7p2-2) | `onboarding_screen.dart`, `legal_consent_screen.dart` | legal gate + consent | `GET /legal/documents/current`, `POST /legal/consents/current` | all | ☐ seeded |
| Splash + boot skeleton (E4) | release-gate router | release-gate | `GET /legal/gate`, `GET /profile/me` | all | ☐ seeded |
| Nav shell (rail / bottom-bar + «Ещё») — **5-role aware** | `app_router.dart`, `adaptive_messenger_shell.dart`, role dashboard wrappers | role from `currentProfile` | `GET /profile/me` (role) | all (per-role items) | ☐ seeded |

**P1 gate:** baseline of `login → gate → role-route` identical before/after; all 5 roles land on correct route; `system_admin` `RolesGuard` bypass intact; release-gate funnel order preserved (`deletionPending → /onboarding → /legal-consent`); `git diff server/` empty.

---

## P2 — Schedule (`backend-crm.md` §D Lessons)

| v7 screen / component | Replaces (Flutter file) | Service method(s) | Endpoint(s) | RBAC | Status |
|---|---|---|---|---|---|
| Day grid (sticky time-col + room/teacher headers) | `schedule_widget.dart` | `listLessons`, `getScheduleMatrix` | `GET /crm/lessons`, `GET /crm/schedule/matrix` | M/A/S (T: own) | ☐ seeded |
| Month view (month-first default) | `schedule_widget.dart` | `getMonthSummary` | `GET /crm/schedule/month-summary` | M/A/S (T: own) | ☐ seeded |
| Block-drag booking sheet (span → duration) | `create_lesson_dialog.dart` | `createLesson` | `POST /crm/lessons` | M/A/S | ☐ seeded |
| Conflict warning in booking sheet | `_scheduleConflicts` | `getScheduleMatrix` | `GET /crm/schedule/matrix` (4 types, pair-dedup) | M/A/S | ☐ seeded |
| Lesson attendance UI (v7p2-3) | `lesson_attendance_dialog.dart` | `getLessonAttendance`, `saveLessonAttendance` | `GET/PATCH /crm/lessons/:id/attendance` | M/A/S; T own | ☐ seeded |
| Reschedule / cancel | lesson sheet | `updateLesson`, `deleteLesson` | `PATCH/DELETE /crm/lessons/:id` | M/A/S (T: status/notes only) | ☐ seeded |
| Teacher schedule (read + complete + notes) | `teacher_schedule_widget.dart` | `listLessons`, `updateLesson` | `GET /crm/lessons`, `PATCH /crm/lessons/:id` (status/notes) | T (own) | ☐ seeded |

**P2 note:** P2-8 (real grid render) depends on **P6-4** data fix (1 imported lesson = 1 row). Booking body must stay `{scheduledAt, durationMinutes, one-of student/group/lead}`.

---

## P3 — Clients / Leads (KVA-181) (`backend-crm.md` §A/B/G)

| v7 screen / component | Replaces (Flutter file) | Service method(s) | Endpoint(s) | RBAC | Status |
|---|---|---|---|---|---|
| Лиды kanban (in-column drag, load-more) | `leads_widget.dart` | `getLeadBoard`, `moveStatus` | `GET /crm/leads/board`, `PATCH /crm/leads/:id` (statusId/clearStatus) | M/A/S | ☐ seeded |
| Lead→student transfer (dwell → branch → discipline) | `convert_lead_dialog.dart` | `createStudent` | `POST /crm/students` `{branchId, discipline, sourceLeadId}` | M/A/S | ☐ seeded |
| Slide-out filters + persistent search (D1/D2) | `leads_widget.dart` filters | `searchLeads`, `listLeadSources`, `HollihopService` | `GET /crm/leads`, `/crm/lead-sources`, `/crm/hollihop/*` | M/A/S | ☐ seeded |
| Filter presets + pagination (v7p2-7) | `LeadFilterPresetStore` | (local) + `getLeadBoard` cursor | local `crm.lead_filter_presets.v1` + board cursor | M/A/S | ☐ seeded |
| Dual-target column editor (C5) | `manage_statuses_dialog.dart` | lead-statuses CRUD/order, branch-disciplines order | `GET/POST/PATCH/DELETE /crm/lead-statuses`, `/crm/disciplines` order | M/A/S | ☐ seeded |
| Card drawer (Инфо/Задачи/Комм./Семья/История) | `lead_detail_dialog.dart` | `getLeadCard`, `getLeadStatusHistory`, `listComments`, `getFamilyForEntity`, `listDuplicateCandidates`, `getCrmCustomFields` | `GET /crm/leads/:id/card`, `/status-history`, `/crm/comments`, families, `/crm/duplicates`, `/settings/crm-custom-fields` | M/A/S | ☐ seeded |
| Loss-reason on terminal drop | drop pop-menu | `listLossReasons`, `moveStatus` | `GET/POST /crm/loss-reasons`, status update | M/A/S | ☐ seeded |
| Students board | `students_board` / `manage_entities_widget.dart` | `searchStudents`, `updateStudent` | `GET /crm/students(/search)`, `PATCH /crm/students/:id` | M/A/S | ☐ seeded |
| Family member add/remove (write) | card Семья tab | family member writes (backend exists) | `POST /crm/families/:id/members`, `DELETE /crm/family-members/:id` | M/A/S | ☐ seeded |

**P3 gate:** drag still sends `statusId` (UUID) or `clearStatus:true`; keyset cursor `{iso8601}|{uuid}` ≤50/col; convert enforces one-student-per-lead; presets under `crm.lead_filter_presets.v1`.

---

## P4 — Chat parity + bug fixes (`backend-messaging.md` §H/I)

| v7 screen / component | Replaces (Flutter file) | Service method(s) | Endpoint(s) | RBAC | Status |
|---|---|---|---|---|---|
| Two-pane conversation + bubbles + skeleton (K14) | `messenger`, `message_bubble.dart`, `chat_list_tile.dart` | `listChats`, `getMessages` | `GET /messenger/chats(/:id)/messages/members` | members | ☐ seeded |
| Composer (attach/emoji/mic — **real**, not stub) | `message_input.dart` | `sendMessage`, `ChatAttachmentService` | `POST /messenger/chats/:id/messages`, `POST /files` | members | ☐ seeded |
| Message ⋯ menu (edit/reply/forward/react/pin) | `message_bubble.dart` | `updateMessage`, `deleteMessage`, `setReaction`, `pinMessage` | reactions/pin/edit/delete | members | ☐ seeded |
| **E2 voice playback fix** | `voice_player_widget.dart` | download-token + `just_audio` | `POST /files/:id/download-token` | members | ☐ seeded |
| **E3 gallery/file attachments fix** | `file_attachment_widget.dart`, `send_file_dialog.dart` | `ChatAttachmentService` (image vs file) | `POST /files`, download-token | members | ☐ seeded |
| Groups (create / members) | `create_group_dialog.dart`, `chat_info_dialog.dart` | `createGroup`, member mgmt | `POST /messenger/groups`, `PATCH /groups/:id/members` | M/A/S | ☐ seeded |
| **Channels (keep — orphan §H)** | channel list/posts | `listChannels`, `createChannelPost` | `GET/POST/PATCH /messenger/channels*` | post: M/A/S | ☐ seeded |
| **Administration chat (keep — auto-lead §A)** | chat list | `openDirectChat`, `ensureAdministrationChat` | `POST /messenger/chats/direct` (administration) | all | ☐ seeded |
| Notification center list (close orphan §I) | `notification_bell_widget.dart` | `MagicNotificationsService` | `GET /notifications`, read | self | ☐ seeded |
| Realtime presence/typing | `MagicRealtimeService` | join/typing/presence | WS `/realtime` | members | ☐ seeded |

**P4 gate:** send/edit/delete/react/pin identical; administration-chat singleton + auto-lead on first non-staff msg still fires (integration test); channel posting M/A/S only; file purpose validation (`chat_attachment`/`chat_voice`, 25MB, MIME) intact.

---

## P5 — Reports / Finance / Tasks / Users / Settings (+ expense write) (§E/F/G/I/J/K)

| v7 screen / component | Replaces (Flutter file) | Service method(s) | Endpoint(s) | RBAC | Status |
|---|---|---|---|---|---|
| Reports — Аналитика/Финансы/Активность(v7p2-4)/Управление | `reports_widget.dart`, `financial_dashboard_widget.dart`, `_ActivityLogTab` | `getFinanceReport`, `getManagerDashboard`, `analytics*Provider`, `listActivityLog` | 14× `GET /analytics/*`, `/crm/reports/finance`, `/crm/dashboard/manager`, `/crm/activity` | M/A/S | ☐ seeded |
| Tasks board | `tasks_widget.dart` | `listTasks`, `createTask`, `updateTask` | `GET/POST/PATCH /crm/tasks` | M/A/S (C: own) | ☐ seeded |
| Users list + link-to-CRM (v7p2-6) + role change | `user_roles_widget.dart` | `MagicProfileAdminService` (list/detail/notes/link/auto-link/manual-link/role) | `GET/POST /admin/profiles*` | **A+** (role: last-`system_admin` guard) | ☐ seeded |
| Broadcast | `broadcast_dialog.dart`, `mass_notification_widget.dart` | `adminSend` | `POST /admin/notifications` | M/A/S | ☐ seeded |
| Admin deletion-request queue (close orphan §J) | new admin sub-panel | deletion-request admin | `GET/PATCH /admin/deletion-requests` | **A only** | ☐ seeded |
| Settings — custom fields / avatar / branch/room/discipline | `custom_field_config_widget.dart`, `manage_entities_widget.dart`, `MagicSettingsService` | settings read + admin write, `listBranches/Rooms/Disciplines` | `GET/PATCH /settings/*`, `/crm/{branches,rooms,disciplines}` | read M/A/S; write A | ☐ seeded |
| Finance — payments + add-payment | `finance_widget.dart`, `top_up_dialog.dart` | `listPaymentsWithTotal`, `createPayment` | `GET/POST /crm/payments` | M/A/S | ☐ seeded |
| Debtors | `debtors_widget.dart` | `listStudentBalances`, `listExpectedPayments` | `GET /crm/student-balances`, `/crm/expected-payments` | M/A/S | ☐ seeded |
| **«Добавить расход» (NEW-BE §3.3)** | new sheet | `listExpenses`, `createExpense` | **NEW** `GET/POST/PATCH/DELETE /crm/expenses` | M/A/S | ☐ seeded |
| CSV/XLSX export (close orphan §K) | report buttons | finance monthly export | `GET /analytics/finance/monthly.{csv,xlsx}` | M/A/S | ☐ seeded |
| «Качество данных» panel (close orphans §G) | Settings sub-panel | `getPhoneReviewQueue`, `getMergeCandidates`, `mergeLeads`, `undoMerge` | `GET /crm/phone-review-queue`, `/crm/merge-candidates`, merge, merge-undo | M/A/S | ☐ seeded |

**P5 gate:** analytics/finance/tasks calls unchanged; writes M/A/S only; staff-create A-only; expense endpoints are **purely additive** (finance report read path unchanged → `server/` diff shows only new expense files).

---

## P5b/P5c — new-backend flows (own PRs, contract-tested)

| Flow | Replaces / Host | Service method(s) | Endpoint(s) | RBAC | Status |
|---|---|---|---|---|---|
| Subscription packages catalog (KVA-153) | Settings | `listSubscriptionPackages`, package CRUD | **NEW** `GET/POST/PATCH/DELETE /crm/subscription-packages` | M/A | ☐ seeded |
| «Выдать абонемент» | `/student/:id`, client portal | `issueSubscription` | **NEW** `POST /crm/students/:id/subscriptions/issue` (txn) | M/A | ☐ seeded |
| Homework + files (KVA-157) | replaces thin `HomeworkWidget` | homework assign/submit/attachments | **NEW** `GET/POST/PATCH /crm/homeworks*` + reuse `POST /files` | T assign; C submit own; M/A all | ☐ seeded |

---

## Orphan-risk watchlist (must keep a home — never drop) §2

1. Administration chat / auto-lead trigger (P4) — keep administration chat in list.
2. Student invite `POST /crm/students/:id/invite` (P3) — keep on `/student/:id`.
3. Merge + merge-undo (P5) — «Качество данных» panel.
4. Phone-review-queue (P5) — «Качество данных» panel.
5. Family write paths (P3) — Семья tab add/remove.
6. Channels sub-system (P4) — keep reskinned list/posts.
7. Notification center/list (P4) — wire `GET /notifications`.
8. Admin deletion-request queue (P5) — Users/Settings sub-panel, `A`-only PATCH.
9. Analytics `sources`/`data-quality`/`responsible` (P5) — report cards.
10. CSV/XLSX export (P5) — report buttons.

**Reverse-orphan (v7 UI needs missing endpoint):** expense write API (§3.3) — the only one.

---

## RBAC enforcement (A1 → P1)

Business hierarchy **`manager` (Управляющий) > `admin` (Администратор)**, but the backend is **set-based `@Roles(...)`**, not linear. Today `isStaff = admin||manager||system_admin` over-privileges `admin` (bug A1). **P1 enforces:** `admin` → only **Чат / Расписание / Клиенты**; drop `'admin'` from manager-only `@Roles` (backend) + from nav (frontend); no role-edit for `admin`. Keep all 5 roles, the `system_admin` `RolesGuard` bypass, and the last-`system_admin` demotion guard. A **5-role role-matrix test** asserts visible actions == backend-permitted actions per screen (catches v7's 4-role simplification before ship).
