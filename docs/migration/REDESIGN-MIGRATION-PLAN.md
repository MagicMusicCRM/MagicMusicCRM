# MagicMusicCRM — v7 Redesign Migration Plan

**Date:** 2026-06-21
**Author:** Lead architect (automated synthesis)
**Approved design:** `docs/prototypes/crm-redesign-v7.html` (owner-signed-off)
**Source material:** `docs/audit/REDESIGN-COVERAGE-REPORT.md` + 8 area inventories in `docs/audit/`
**Target:** Port the v7 redesign onto the EXISTING Flutter app (`lib/features/*`) + NestJS/PostgreSQL backend (`server/src/*`) — reskin/reflow, not rewrite.

---

## 1. Guiding principle + non-negotiables

> **The backend is the source of truth and it stays. We RESKIN/REFLOW the existing Flutter app to match v7. We do NOT rewrite the backend and we do NOT build greenfield.**

The v7 prototype is a 100% in-memory mock (`docs/prototypes/crm-redesign-v7.html`, ~340 KB, JS `ST` state object). It is an **approved design and interaction blueprint covering ~40% of functionality and ~85% of the desired UX** — not an application. The correct move is to re-bind every interaction in the prototype to the Flutter services that **already exist and are already wired to the backend** (`MagicCrmService`, `MagicMessengerService`, `MagicRealtimeService`, `MagicProfileAdminService`, `MagicSettingsService`, `MagicNotificationsService`, `ChatAttachmentService`, `HollihopService`), and to fix the real bugs the mockup can only depict.

**Non-negotiables (every PR is measured against these):**

1. **No backend regressions.** Pure-frontend phases (1, 3, 4, 5-UI) touch **zero** files under `server/`. New backend work is isolated to its own phase/PRs (subscriptions, homework, expense-write, data cleanup) and gated behind contract + integration tests.
2. **Full backend coverage.** Every backend endpoint/service group listed in the four backend inventories must remain reachable from a UI home in the new design. The redesign must not drop or orphan any backend capability. The matrix in §2 is the proof.
3. **Reskin, not rewrite.** We change widgets, layout, theme tokens, gestures, and navigation — not the REST/RPC call sites. A reskinned screen issues the **same** API calls (same endpoint, same verb, same params, same body shape) as the screen it replaces.
4. **Preserve the API contract.** The Flutter services already encode the contract (see `flutter-*.md`). No reskin PR may change the request/response shape any service emits or expects. New endpoints are additive only.
5. **Every endpoint keeps a UI home.** A backend capability with no v7 screen is an **orphan risk** and must get an explicit home (existing screen retained, or new shell) — flagged in §2.
6. **RBAC.** 5 backend roles: `client`, `teacher`, `admin` (**Администратор**), `manager` (**Управляющий**), `system_admin` (**Администратор системы**). **Business hierarchy: `manager` (Управляющий) > `admin` (Администратор)** — Управляющий круче. ⚠️ The backend is NOT hierarchical — it is **set-based `@Roles(...)`**, and today `manager`/`admin` are near-equal "staff" (`isStaff = admin||manager||system_admin`), which is the **A1 bug** (Администратор over-privileged: reaches Пользователи/role-edit). **P1 ENFORCES the hierarchy** (a deliberate change, not "parity"): restrict `admin` to Чат/Расписание/Клиенты — drop `'admin'` from manager-only `@Roles` on the backend + from nav on the frontend, no role-edit for admin. Keep all 5 roles, the `system_admin` `RolesGuard` bypass, and the last-`system_admin` guard. (The v7 prototype models 4 roles; the real app keeps 5 — §5d.)

---

## 2. Backend-coverage matrix (THE core deliverable)

Every backend endpoint/service **group** from `backend-crm.md`, `backend-messaging.md`, `backend-platform.md`, `backend-analytics.md` → the existing Flutter service that calls it → the v7 redesign screen/component that will host it → status.

**Status legend:** `keep` = screen/logic survives, theme only · `reskin` = re-laid-out to v7, same calls · `new-wire` = backend exists but needs a NEW UI home in v7 · `NEW-BE` = backend endpoint does not exist yet · ⚠️ = orphan risk flagged.

### A. CRM — Leads (`backend-crm.md` §Leads)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET /crm/leads/board` (cursor pagination, filters, quick-filter) | `leadBoardProvider`, `MagicCrmService.getLeadBoard` | Клиенты → Лиды kanban (v7 columns + load-more + filter presets) | reskin |
| `GET /crm/leads`, `GET /crm/leads/app-count` | `MagicCrmService.searchLeads`, `appLeadsCountProvider` | Лиды search + Clients-tab unread badge | reskin |
| `GET /crm/leads/:id/card` | `MagicCrmService.getLeadCard` | Карточка клиента drawer → Инфо/Задачи/Связи | reskin |
| `GET /crm/leads/:leadId/status-history` | `getLeadStatusHistory` | Card drawer → История статусов tab | reskin |
| `GET /crm/leads/:id/chat-user` | `resolveLeadChatUser` | Card → "Чат" button → opens messenger | keep |
| `POST/PATCH/DELETE /crm/leads`, `clearStatus` | `createLead`, `updateLead`, `moveStatus`, `deleteLead` | Лиды FAB + drag-to-column + card save | reskin |
| `GET/POST/PATCH(order)/DELETE /crm/lead-statuses` | `leadStatusesProvider`, `ManageStatusesDialog` | "Колонки" column-editor drawer (v7 dual-target editor) | reskin |
| `GET/POST /crm/loss-reasons` | `MagicCrmService.listLossReasons` | Loss-reason pop-menu on drop into terminal column | reskin |
| `GET /crm/lead-sources` | `MagicCrmService.listLeadSources` | Lead filter drawer (Источник chips) + card source pill | reskin |
| `autoCreateLeadFromChat` (internal, advisory-lock) | — (server-triggered by messenger) | No UI; verify still fires on admin-chat first msg | keep ⚠️ (see note) |
| `POST /crm/contacts/save-from-chat` | `saveContactFromChat` | Chat header ⋯ → "Сохранить как лид/ученик" | reskin |

> ⚠️ **Orphan note (auto-lead):** The v7 prototype has NO administration-chat / auto-lead concept (coverage report row 10). The backend fires `autoCreateLeadFromChat` server-side on the first non-staff message in an `administration` chat. This is **server-driven, not a UI feature** — but the redesign must keep the administration chat type alive in the messenger (Phase 4), or the trigger never fires. **Keep the administration chat in the chat list.**

### B. CRM — Students / Clients (`backend-crm.md` §Students)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET /crm/students`, `/students/search` (rich filters + stats) | `searchStudents`, `studentSearchProvider` | Клиенты → Ученики board + ManageEntities Ученики tab | reskin |
| `POST/PATCH /crm/students` | `createStudent`, `updateStudent` | Convert dialog, student detail edit, create FAB | reskin |
| `GET /crm/students/:id`, `/students/:id/card` | `getStudentCard` | `/student/:id` full detail screen (v7 styling) | reskin |
| `POST /crm/students/:id/invite` | `inviteStudent` | Student detail → "Пригласить" action | new-wire ⚠️ (no v7 home — see note) |
| `GET /crm/students/:id/groups` | `listStudentGroups` | Student detail → Groups section | reskin |
| `GET /crm/student-balances` (debtOnly) | `listStudentBalances` | Finance → Должники (DebtorsWidget) | reskin |
| `GET /crm/subscriptions` | `listSubscriptions` | Client portal subscription card + student detail | reskin |
| `GET /crm/me` (client self-summary + family) | `getMySummary` | Client portal / Моя школа | reskin |

> ⚠️ **Orphan note (invite):** `POST /crm/students/:id/invite` has no analog in the v7 mock. Keep it as an action on the existing `/student/:id` detail screen — do not drop it.

### C. CRM — Teachers / Staff / Branches / Disciplines / Rooms / Groups

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET/POST/PATCH /crm/teachers` | `listTeachers`, `teacherSearchProvider` | ManageEntities Преподаватели tab + Настройки Преподаватели | reskin |
| `GET/POST/PATCH /crm/staff` (admin-only) | `listStaff`, `staffSearchProvider` | ManageEntities Сотрудники tab | reskin |
| `GET/POST/PATCH /crm/branches` (utcOffsetMinutes) | `listBranches` | Настройки → Филиалы set-cards + ManageEntities Филиалы | reskin |
| `GET/POST /crm/disciplines`, branch-disciplines + order | `listDisciplines`, `listBranchDisciplines` | Настройки → per-branch funnel column editor | reskin |
| `GET/POST/PATCH/DELETE /crm/rooms`, `/rooms/availability` | `listRooms`, room availability | Настройки → Комнаты + Schedule slot greying | reskin |
| `GET/POST /crm/groups`, group-students add/remove | `listGroups`, `GroupDetailDialog` | ManageEntities Группы tab | reskin |

### D. CRM — Lessons / Schedule (`backend-crm.md` §Lessons)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET /crm/lessons` (role-scoped) | `listLessons` | Schedule day/month, teacher schedule, client portal | reskin |
| `GET /crm/schedule/matrix` (4 conflict types, pair-dedup) | `getScheduleMatrix`, `_scheduleConflicts` | Schedule day view conflict badges + booking-sheet warning | reskin |
| `GET /crm/schedule/month-summary` | `getMonthSummary`, `_monthDaySummary` | Schedule Месяц view per-day counts | reskin |
| `POST /crm/lessons` | `createLesson` | v7 block-drag booking sheet + tap-cell + trial-from-lead | reskin |
| `PATCH /crm/lessons/:id` (teacher status/notes only) | `updateLesson` | Lesson sheet edit / reschedule / teacher complete | reskin |
| `DELETE /crm/lessons/:id` | `deleteLesson` | ManageEntities Занятия → cancel | keep |
| `GET/PATCH /crm/lessons/:id/attendance` | `getLessonAttendance`, `LessonAttendanceDialog` | v7 attendance UI (v7p2-3-lesson-attendance) | reskin |

### E. CRM — Tasks / Comments / Timeline (`backend-crm.md` + `backend-analytics.md` §Tasks)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET/POST/PATCH /crm/tasks` (full filters) | `listTasks`, `TasksWidget` | Задачи board (v7) + card Задачи tab + client homework | reskin |
| `GET/POST /crm/comments` (`[PROGRESS]` filter) | `listComments`, `_CommentsList` | Card Комментарии tab + teacher progress note + client progress notes | reskin |
| `GET /crm/timeline` | `getTimeline` | Card activity + task entity-timeline sheet | reskin |

### F. CRM — Finance / Payments / Dashboard (`backend-crm.md` + `backend-analytics.md` §Finance)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET /crm/payments`, `POST /crm/payments` | `listPaymentsWithTotal`, `createPayment` | Finance → payment list + add-payment FAB (v7 Финансы) | reskin |
| `GET /crm/expected-payments` | `listExpectedPayments` | Debtors detail + student detail | reskin |
| `GET /crm/reports/finance` | `getFinanceReport` | Reports → Аналитика + Финансы (fl_chart) | reskin |
| `GET /crm/dashboard/manager` | `getManagerDashboard` | Reports → Управление dashboard | reskin |
| `GET /crm/overview` | `getOverviewStats` | Обзор KPI cards | reskin |
| **expenses (read in finance report; NO write API)** | — (read-only via finance report) | v7 "Добавить расход" sheet | **NEW-BE** ⚠️ |

> ⚠️ **Reverse-orphan (expense write):** The v7 Финансы tab has an **"Добавить расход" sheet**, but `app.expenses` has **no create/update/delete endpoint** (`backend-analytics.md` rule 4). This is the one place a v7 UI needs an endpoint that does not exist → new backend work (§3.3).

### G. CRM — Dedup / Merge / Phone / Families / HolliHop / Activity

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET /crm/duplicates`, `PATCH /crm/duplicates/:id` | `listDuplicateCandidates`, `decideDuplicateCandidate` | Card → "Кандидаты на связь" section ("Связать") | reskin |
| `GET /crm/merge-candidates`, merge, merge-undo | `getMergeCandidates`, `mergeLeads`, `undoMerge` | Card → duplicates + merge action | new-wire ⚠️ |
| `GET /crm/phone-review-queue(/count)` | `getPhoneReviewQueue` | Settings/data-quality surface | new-wire ⚠️ |
| `POST /crm/families`, members, by-entity, primary-payer | `getFamilyForEntity` (+ writes) | Card → Семья tab (read today; writes new-wire) | new-wire ⚠️ |
| `GET /crm/contacts/by-user/:userId` | `resolveContactForUser` | Chat → "Открыть карточку" | keep |
| `GET /crm/hollihop/{disciplines,levels,categories,lead-statuses}` | `HollihopService` | Lead filter dropdowns (discipline/level/category) | keep |
| `GET /crm/activity` (audit log) | `listActivityLog`, `_ActivityLogTab` | Reports → Активность tab (v7p2-4) | reskin |

> ⚠️ **Orphan notes (data-quality cluster):** merge/merge-undo, phone-review-queue, and **family write** paths exist in the backend but are NOT in v7. They have partial homes today (duplicate "Связать", read-only Семья). The redesign must **retain these surfaces** and give phone-review-queue + merge a small home (Settings → "Качество данных" panel) so the capability is not orphaned. Family member add/remove is a small write gap (§3.4).

### H. Messenger / Channels / Files (`backend-messaging.md`)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET /messenger/chats`, `/chats/:id`, `/messages`, `/members` | `MagicMessengerService.listChats/getMessages` | Чат list + conversation (v7 two-pane) | reskin |
| `POST /messenger/chats/:id/messages` (text/file/voice, reply/forward) | `sendMessage` | v7 composer (attach/emoji/mic are real, not stubs) | reskin |
| `POST /messenger/chats/direct` (incl. `administration`) | `openDirectChat`, `ensureAdministrationChat` | Чат new-chat + client admin chat | keep ⚠️ |
| `POST /messenger/groups`, `PATCH /groups/:id/members` | `createGroup`, member mgmt | CreateGroupDialog + ChatInfoDialog | reskin |
| `POST /chats/:id/read`, `PUT /chats/:id/mute` | `markRead`, `setChatMute` | conversation open + chat menu | keep |
| reactions add/remove, pin/unpin, edit, delete | `setReaction`, `pinMessage`, `updateMessage`, `deleteMessage` | message ⋯ menu + reaction pills (v7 adds full menu) | reskin |
| `GET/POST/PATCH /messenger/channels`, access, perms, posts | `listChannels`, `createChannelPost` | Channels in chat list (v7 lacks channels → **new-wire home**) | new-wire ⚠️ |
| WebSocket `/realtime` (join/typing/presence + push events) | `MagicRealtimeService` | conversation presence/typing, chat-list live update | keep |
| `POST /files`, download-token, `GET/DELETE /files/:id` | `ChatAttachmentService`, `uploadAvatar` | attachments, voice, avatar, gallery (E3 fix) | reskin |

> ⚠️ **Orphan note (channels):** Channels are an entire messenger sub-system in the backend and Flutter, but the v7 prototype has **no channel design at all** (coverage report row 8). The redesign must **keep the existing channel list/posts UI** reskinned to v7 tokens — do not drop channels.

### I. Notifications (`backend-messaging.md` §Notifications)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `GET /notifications`, read, read-all | `MagicNotificationsService` | Profile pop-menu "Уведомления" (toast stub in v7 → new-wire) | new-wire ⚠️ |
| `POST/DELETE /notifications/devices` | device register (push) | bootstrap (no UI) | keep |
| `POST /admin/notifications` (broadcast) | `adminSend`, `BroadcastDialog` | Users → broadcast action | reskin |
| local push on incoming | `NotificationService` | messenger | keep |

> ⚠️ **Orphan note (notification center):** v7 only toasts "Уведомления". The backend has a real notification list + read state. Keep a notification list screen (existing or minimal) wired to `GET /notifications`.

### J. Platform — Auth / Legal / Profile / Settings (`backend-platform.md`)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `POST /auth/{signup,login,verify-email}` | `MagicAuthService` | v7 login + signup→OTP (v7p2-1) | reskin |
| `POST /auth/otp/{request,verify}` (2FA + email verify) | OTP screen | v7 OTP boxes (auto-advance) | reskin |
| `POST /auth/password-reset/{request,confirm}`, `/auth/password` | password reset / auth-methods | v7 "forgot → code → newpass" | reskin |
| `GET /auth/identities`, `POST /auth/{refresh,logout-all}` | identities, refresh-rotation | Auth-methods screen | keep |
| `GET /legal/gate` | release-gate router | gate → onboarding/consent/role route | keep |
| `GET /legal/documents/current`, `POST /legal/consents/current` | legal consent | v7 onboarding consent rows (v7p2-2) | reskin |
| `POST/GET /profile/deletion-request`, `GET/PATCH /admin/deletion-requests` | deletion request + admin processing | Profile → delete request; admin queue (new-wire) | reskin / new-wire ⚠️ |
| `GET/PATCH /profile/me` (+ avatar) | `currentProfile`, profile edit | v7 profile edit + avatar crop (v7p2-5) | reskin |
| `GET/POST /admin/profiles*` (list/detail/notes/link-candidates/auto-link/manual-link/role) | `MagicProfileAdminService` | Users list + link-to-CRM (v7p2-6) + role change | reskin |
| `GET /settings/{admin-chat-avatar,crm-custom-fields}` + admin PATCH | `MagicSettingsService` | Настройки (avatar, custom-field editor) | reskin |
| Audit write (`AuditService`, no read API) | — | n/a (write-only; surfaced via `/crm/activity`) | keep |

> ⚠️ **Orphan note (admin deletion queue):** `GET/PATCH /admin/deletion-requests` (admin processes account deletion) has no v7 home. Keep/add a small admin queue (Settings or Users sub-panel). RBAC: `admin`-only PATCH (`backend-platform.md`).

### K. Analytics (`backend-analytics.md` — 14 `/analytics/*`)

| Backend group | Existing Flutter service | v7 home | Status |
|---|---|---|---|
| `/analytics/{overview,dashboard}` | `getOverviewStats`, dashboard providers | Обзор + Reports Управление | reskin |
| `/analytics/{funnel,branches,loss-reasons,debts,forecast,churn-risk,chats/sla,sources,data-quality,responsible}` | `analytics*Provider` (7 wired) + sources/data-quality/responsible | Reports → Управление + Аналитика cards | reskin / new-wire ⚠️ |
| `/analytics/weekly-report` | weekly report | Reports → Недельный отчёт card | reskin |
| `/analytics/finance/monthly{,.csv,.xlsx}` | finance monthly | Reports → Финансы + **export buttons (new-wire)** | new-wire ⚠️ |

> ⚠️ **Orphan notes (analytics):** `sources`, `data-quality`, `responsible` analytics endpoints and **CSV/XLSX export** are backend-present but thinly surfaced in Flutter and absent from v7. Add report cards/buttons so they are not orphaned.

### Coverage tally

- **Backend endpoint-groups covered:** ~58 groups across CRM (≈40), Messenger/Files (≈9), Notifications (≈4), Platform (≈14 incl. auth/legal/profile/settings — counted as groups), Analytics (≈15). **Every group has a UI home** in the plan.
- **Orphan risks flagged (must be given/kept a home, not dropped):** (1) administration chat / auto-lead trigger, (2) student invite, (3) merge + merge-undo, (4) phone-review-queue, (5) family write paths, (6) channels sub-system, (7) notification center/list, (8) admin deletion-request queue, (9) analytics sources/data-quality/responsible, (10) CSV/XLSX export.
- **Reverse-orphans (v7 UI needs a missing endpoint):** expense write API (the only true one). Subscription packages + homework files are net-new flows the owner explicitly asked for (KVA-153/157), not orphans.

---

## 3. Genuinely-new backend work

This is the **complete** list of new backend work. Everything else is reskin of existing, already-wired endpoints. All new tables live in the `app` schema and follow the existing conventions: `deleted_at` soft-delete, `created_at/updated_at`, `JwtAuthGuard` + `CrmPolicy.assertCanWriteCrm()` (manager/admin/system_admin) on writes, audit event on every mutation, dual-path `branch_id` resolution where relevant.

### 3.1 Subscription packages catalog + issuance (KVA-153)

**Why new:** today `app.subscriptions` exists (lessons_total/used/starts/expires) and is read by `GET /crm/subscriptions`, but there is **no catalog of purchasable packages** and **no "issue subscription" flow** that creates a subscription + payment atomically and decrements `lessons_used` on attendance.

**Migration sketch (`0033_subscription_packages.up.sql`):**
```sql
CREATE TABLE app.subscription_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  discipline_id uuid REFERENCES app.disciplines(id),
  branch_id uuid REFERENCES app.branches(id),
  lessons_total int NOT NULL CHECK (lessons_total > 0),
  price numeric(12,2) NOT NULL,
  validity_days int,                 -- null = no expiry
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
-- link a sale to the catalog row it came from (existing app.subscriptions gets a FK)
ALTER TABLE app.subscriptions
  ADD COLUMN package_id uuid REFERENCES app.subscription_packages(id),
  ADD COLUMN payment_id uuid REFERENCES app.payments(id);
```
**New endpoints (CrmController):**
- `GET /crm/subscription-packages` — list active packages (manager/admin/teacher read).
- `POST/PATCH/DELETE /crm/subscription-packages` — CRUD (manager/admin); audited `crm.subscription_package_*`.
- `POST /crm/students/:id/subscriptions/issue` — «Выдать абонемент»: in one transaction insert `subscriptions` (from package: lessons_total, expires_at = now()+validity_days), insert a `payments` row (amount = package.price), link both. Audited `crm.subscription_issued`.
- Wire **`lessons_used` decrement** into the existing `PATCH /crm/lessons/:id/attendance` path: when a participant is marked `present`, decrement the student's active subscription `lessons_used` (idempotent — guard against double-count per `lesson_participation` row).

**Flutter:** new `MagicCrmService.listSubscriptionPackages / issueSubscription`; package catalog in Настройки; «Выдать абонемент» button on `/student/:id` and client portal subscription card (reskin host already exists).

### 3.2 Homework with file attachments (KVA-157)

**Why new:** homework today is just `tasks` toggled by clients (`HomeworkWidget`). The owner wants real homework with teacher-attached files and client submissions.

**Migration sketch (`0034_lesson_homeworks.up.sql`):**
```sql
CREATE TABLE app.lesson_homeworks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid REFERENCES app.lessons(id),
  student_id uuid REFERENCES app.students(id),
  assigned_by uuid REFERENCES app.users(id),
  title text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'assigned',   -- assigned|submitted|reviewed
  due_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
CREATE TABLE app.homework_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  homework_id uuid NOT NULL REFERENCES app.lesson_homeworks(id),
  file_id uuid NOT NULL REFERENCES app.file_objects(id),
  uploaded_by uuid REFERENCES app.users(id),
  kind text NOT NULL DEFAULT 'assignment',   -- assignment|submission
  created_at timestamptz NOT NULL DEFAULT now()
);
```
**Reuse the existing Files subsystem** (`POST /files` + download-token) — add a new file purpose `homework_attachment` (mirror the `chat_attachment` MIME allowlist + 25 MB cap in the Files purpose table). No new storage code.
**New endpoints:** `GET/POST/PATCH /crm/homeworks` (+ `:id/attachments` upload-link, `:id/submit` for clients). RBAC: teacher assigns on own students, client submits own, manager/admin all. Audited.
**Flutter:** teacher UI (assign + attach) on lesson sheet / student detail; client UI replaces the thin `HomeworkWidget` with assignment + submission + file download.

### 3.3 Expense write API (v7 «Добавить расход»)

**Why new:** `app.expenses` table exists (migration 0007, `id, amount, category, description, branch_id, created_at...`) and is **read** in the finance report, but `backend-analytics.md` rule 4 confirms **no write endpoint**. The v7 Финансы tab invents the add-expense UX.

**No migration needed** (table already exists). **New endpoints (CrmController, manager/admin):**
- `GET /crm/expenses` — list expenses (filters: branchId, category, from/to), totals.
- `POST /crm/expenses` — create (amount > 0, category from a fixed list, description, paymentDate, branchId via `extractBranchId`). Audited `crm.expense_created`.
- `PATCH/DELETE /crm/expenses/:id` — edit / soft-delete. Audited.

**Flutter:** `MagicCrmService.listExpenses / createExpense`; wire the v7 add-expense sheet (mock array → real call). Finance report's expense total continues to read the same table — no contract change there.

### 3.4 Custom-field & small write paths (write-completeness)

These close write gaps the redesign exposes; all are small and additive:
- **Family member write** — `POST /crm/families/:familyId/members` + `DELETE /crm/family-members/:memberId` **already exist** in the backend (`backend-crm.md` §Families) but the Flutter Семья tab is read-only. **No new backend; Flutter wiring only** (add/remove member in the card Семья tab).
- **Custom CRM fields** — read (`GET /settings/crm-custom-fields`) + admin write (`PATCH /admin/settings/crm-custom-fields`) **already exist**. The v7 custom-field schema editor is a **reskin of the existing `CustomFieldConfigWidget`**, no new endpoint.
- **Lesson reschedule / cancel** — `PATCH/DELETE /crm/lessons/:id` already exist; v7 just needs to wire the lesson sheet "Изменить" stub to them (no new backend).

> **Bottom line — new backend surface is small and bounded:** 2 new migrations (subscription_packages, lesson_homeworks + homework_attachments), 1 new file purpose (`homework_attachment`), and ~3 new endpoint clusters (subscription-packages + issue, homeworks, expenses). Everything else in the redesign is reskin of already-wired endpoints.

---

## 4. Phased migration plan

Adopts the audit's Phase 0–6 sequencing and refines it. **Phases 1, 3, 4 are pure-frontend** (zero `server/` changes — see §5e). New-backend work is isolated to Phases 2 (data fix only), 5 (expense write), and the subscriptions/homework phases. The **data-quality track (Phase 6)** runs in parallel from day one.

The 5 Linear tasks map as: **KVA-153 → Phase 5b (subscriptions)**, **KVA-157 → Phase 5c (homework)**, **KVA-181 → Phase 3 (clients/UX polish)**, **KVA-177 → Phase 6 (data track)**, **KVA-123 → Phase 7 (acceptance / on-device re-audit)**.

### Phase 0 — Lock the spec + design tokens (no shipping code)

- **Scope:** Owner clicks through `crm-redesign-v7.html` per window and signs off. Extract the locked design tokens (gold `#C5A059`, bg `#101012`, surface `#1A1A1D`, sidebar `#151518`, input `#242427`, divider `#2A2A2D`, Inter font, SVG icon set, `--r-ctrl` radii, skeleton shimmer timing, toast system, pop-menu, drawer/sheet patterns) into the Flutter `ThemeData` + a shared component library.
- **Flutter files:** `lib/core/theme/*` (new tokens), shared widgets (`AppToast`, `AppPopMenu`, `AppDrawer`, `AppSheet`, `SkeletonShimmer`).
- **Backend endpoints covered:** none.
- **Regression checks:** none (additive theme + new widgets, not yet mounted). Golden-test the token values against the prototype.

### Phase 1 — RBAC + nav shell + auth reskin (highest owner pain, lowest risk) · pure-frontend

- **Scope:** Corrected role nav (admin ≠ manager; no role-edit control for admin — coverage A1/I9), manager nav order, **5-role** rendering (keep `system_admin`, do not collapse to v7's 4), login/signup→OTP, 2FA, forgot→code→newpass, **first-run onboarding slides → legal consent** (v7p2-1, v7p2-2). Apply the v7 nav shell (desktop rail / phone bottom-bar + "Ещё" overflow).
- **Existing Flutter services/files to wire:** `MagicAuthService` (login/signup/otp/reset/identities/logout-all), release-gate router (`app_router.dart`, `/legal/gate`), `MagicSettingsService`; `MessengerScreen` nav switch, `AdminDashboardScreen`/`ManagerDashboardScreen` wrappers, teacher 3-tab shell, client shell.
- **New v7 flows to build:** v7 login/signup/OTP boxes, onboarding slides + consent rows wired to `GET /legal/documents/current` + `POST /legal/consents/current`.
- **Backend endpoints covered:** `/auth/*` (all), `/legal/gate`, `/legal/documents/current`, `/legal/consents/current`, `/profile/me` (read for gate).
- **Regression checks:** (a) network baseline of login→gate→role-route shows identical calls before/after; (b) all 5 roles land on their correct route; `system_admin` `RolesGuard` bypass intact; (c) release-gate funnel order preserved (`deletionPending` → `/onboarding` → `/legal-consent`); (d) auth contract/integration tests green.

### Phase 2 — Schedule rebuild (biggest conceptual change) · frontend + 1 data fix

- **Scope:** v7 block-drag vertical booking + sub-hour coefficient, tap-cell = 1h, sticky time-col + sticky room/teacher headers (K10), month-first default (K11), single header (D8), Год/Месяц/День modes, branch chips, conflict warning in booking sheet, **lesson attendance UI** (v7p2-3), reschedule/cancel wiring. Teacher schedule reskin (read + complete + notes + attendance).
- **Existing Flutter services/files to wire:** `ScheduleWidget`, `CreateLessonDialog`, `LessonAttendanceDialog`, `TeacherScheduleWidget`; `listLessons`, `getScheduleMatrix`, `getMonthSummary`, `createLesson`, `updateLesson`, `deleteLesson`, `getLessonAttendance`, room availability.
- **New v7 flows:** block-drag booking sheet (maps span → `durationMinutes`), partial-block hatch (display only), conflict re-check on teacher/room change → still calls `schedule/matrix`.
- **Backend endpoints covered:** §D fully (`/crm/lessons*`, `/schedule/matrix`, `/schedule/month-summary`, attendance).
- **Backend (data only, not API):** **B-track import fix D2** — "1 imported lesson ≠ N hourly rows" data-quality cleanup (see §4b B/D1). No API contract change.
- **Regression checks:** (a) booking emits the same `POST /crm/lessons` body (scheduledAt + duration + one of student/group/lead); (b) conflict types (`missing_teacher`, `branch_mismatch`, `room_overlap`, `teacher_overlap`) and pair-dedup unchanged; (c) teacher `PATCH` restricted to status/notes server-side; (d) per-branch `utc_offset_minutes` rendering preserved; (e) reschedule still clears `lesson_reminders` + fires teacher reschedule notification.

### Phase 3 — Clients redesign (KVA-181) · pure-frontend

- **Scope:** in-column drag-and-drop (THRESH tap-vs-drag), continuous in-hand lead→student transfer (dwell tab-expansion → branch → discipline), slide-out filters + persistent search (C3), dual-target column editor (C5), optimistic transfer + undo (K6), **filter presets + load-more pagination** (v7p2-7), restore "not saved in CRM" state, loss-reason capture on drop. Card drawer reskin (Инфо/Задачи/Комментарии/Семья/История + custom fields + duplicates). **KVA-181 sub-items D1 real-time search, D2 mobile filters, D3 fix slow kanban autoscroll, D4 deep-link to cards, D5 state preservation** all land here.
- **Existing Flutter services/files to wire:** `LeadsWidget`, `StudentsBoardWidget`, `LeadDetailDialog`, `ConvertLeadDialog`, `ManageStatusesDialog`, `CustomFieldConfigWidget`, `LeadFilterPresetStore` (FlutterSecureStorage); providers `leadBoardProvider`, `leadStatusesProvider`, `studentBoardProvider`. Services: `getLeadBoard`, `createLead/updateLead/moveStatus/deleteLead`, lead-statuses CRUD/order, `listLossReasons`, `listLeadSources`, `getLeadCard`, `getLeadStatusHistory`, `listComments/createComment`, `getFamilyForEntity`, `listDuplicateCandidates/decideDuplicateCandidate`, `getCrmCustomFields`, `HollihopService`.
- **New v7 flows:** dwell-transfer overlay (still calls `createStudent` with `{branchId, discipline, sourceLeadId}`), filter-preset chips, column-editor drawer (dual-target: `ST.kColumns` → lead-status order API; per-branch cols → branch-disciplines order API).
- **Backend endpoints covered:** §A, §B (board/card/convert), §G (duplicates, families read, hollihop, lead-statuses, disciplines order).
- **Regression checks:** (a) drag-to-column still sends `statusId` (UUID) or `clearStatus:true` for "Без статуса"; (b) keyset cursor pagination preserved (`{iso8601}|{uuid}` cursor, ≤50/column); (c) convert still enforces one-student-per-lead; (d) custom-field rendering matches `GET /settings/crm-custom-fields` schema; (e) filter presets persist under existing key `crm.lead_filter_presets.v1`.

### Phase 4 — Chat parity + real bug fixes · pure-frontend

- **Scope:** Port v7 visual refresh onto the existing messenger (two-pane desktop, consec-bubble radii, date separators, skeleton K14, full message ⋯ menu with edit/reply/forward/reactions/pin). **Keep channels, administration chat, groups, presence/typing — do not drop** (orphan notes §H). Fix real bugs **E2 voice playback** and **E3 gallery attachments** (§4b). Wire the v7 composer's attach/emoji/mic to the **real** `ChatAttachmentService` (they are stubs in the mock).
- **Existing Flutter services/files to wire:** `MessengerScreen`, `MessageInput`, `VoicePlayerWidget`, `VoiceRecorderWidget`, `FileAttachmentWidget`, `ChatInfoDialog`, `CreateGroupChatDialog`; services `MagicMessengerService`, `MagicRealtimeService`, `ChatAttachmentService`, `NotificationService`.
- **New v7 flows:** v7 composer, v7 reaction pills, skeleton loaders; notification-center list wired to `GET /notifications` (close orphan).
- **Backend endpoints covered:** §H (all messenger/channels/files), §I (notifications), administration-chat (keeps auto-lead trigger alive — §A orphan note).
- **Regression checks:** (a) send/edit/delete/react/pin emit identical messenger calls; (b) administration chat singleton + auto-lead on first non-staff message still fires (integration test); (c) channel permissions + manager/admin-only posting unchanged; (d) realtime events (`message.created/updated`, `chat.updated`, typing/presence) reconcile as before; (e) file purpose validation (`chat_attachment`/`chat_voice`, 25 MB, MIME) intact.

### Phase 5 — Reports / Finance / Tasks / Users / Settings + expense write · frontend + small backend

- **Scope:** Wire report cards to the 14 `/analytics/*` endpoints (reskin Reports Аналитика/Финансы/**Активность** (v7p2-4)/Управление). Tasks board reskin. Users list + **link-to-CRM (v7p2-6)** + role change + broadcast + **admin deletion-request queue** (close orphan). Settings reskin (custom-field editor, admin-chat avatar, branch/room/discipline mgmt, **subscription-package catalog** lives here). **Expense write API (§3.3)** + wire v7 «Добавить расход» sheet. Add **CSV/XLSX export buttons**, **sources/data-quality/responsible** analytics cards, **phone-review-queue + merge** "Качество данных" panel (close orphans).
- **Existing Flutter services/files to wire:** `ReportsWidget`, `FinancialDashboardWidget`, `ManagementDashboardWidget`, `_ActivityLogTab`, `TasksWidget`, `UserRolesWidget`, `CustomFieldConfigWidget`, `DebtorsWidget`, `TopUpDialog`, `BroadcastDialog`; services `getFinanceReport`, `getManagerDashboard`, all `analytics*Provider`, `listTasks/createTask/updateTask`, `MagicProfileAdminService` (list/detail/notes/link-candidates/auto-link/manual-link/role), `MagicSettingsService`, `MagicNotificationsService`, `listActivityLog`, `getPhoneReviewQueue`, `getMergeCandidates/mergeLeads/undoMerge`.
- **New backend:** `GET/POST/PATCH/DELETE /crm/expenses` (§3.3). NEW PR, contract-tested.
- **Backend endpoints covered:** §E, §F, §G (activity, phone-queue, merge), §I (broadcast, notifications), §J (profiles admin, settings, deletion-request admin), §K (all 14 analytics + export).
- **Regression checks:** (a) all analytics/finance/tasks calls unchanged; (b) RBAC: analytics/finance/tasks-write are manager/admin only (`assertCanWriteCrm`), staff-create admin-only, role-update guards last-`system_admin`; (c) expense write is a **purely additive** endpoint — finance report read path unchanged (diff `server/` shows only new expense files); (d) export endpoints serve identical CSV/SpreadsheetML.

### Phase 5b — Subscription packages (KVA-153) · new backend + frontend

- **Scope:** §3.1 — `subscription_packages` migration + catalog CRUD + `issue` (sale → subscription + payment) + «Выдать абонемент» + `lessons_used` decrement on attendance.
- **Flutter:** package catalog in Settings; «Выдать абонемент» on `/student/:id` + client portal subscription card.
- **Backend endpoints covered:** new `/crm/subscription-packages*`, `/crm/students/:id/subscriptions/issue`; existing `GET /crm/subscriptions` read path unchanged.
- **Regression checks:** (a) issue is transactional (subscription + payment atomic, rollback on failure); (b) `lessons_used` decrement idempotent per `lesson_participation` row (no double-count on re-mark); (c) existing subscription read contract unchanged; (d) audit events emitted.

### Phase 5c — Homework with files (KVA-157) · new backend + frontend

- **Scope:** §3.2 — `lesson_homeworks` + `homework_attachments` migrations, `homework_attachment` file purpose, homework endpoints (assign/submit/attachments), teacher assign+attach UI, client submit+download UI (replaces thin `HomeworkWidget`).
- **Backend endpoints covered:** new `/crm/homeworks*`; reuses existing `POST /files` + download-token (no new storage code).
- **Regression checks:** (a) reuses Files subsystem unchanged (new purpose only adds a row to the allowlist); (b) RBAC: teacher assigns own students, client submits own; (c) existing task/homework toggle path not broken during cutover; (d) audit events emitted.

### Phase 6 — Data-quality cleanup (parallel backend track — KVA-177, B1–B4) · backend-only

- **Scope:** Independent of the redesign; runs alongside Phase 1+. **KVA-177** ~199 room-lesson overlap data cleanup. **B1–B4:** re-import comments, null the fake `holli-hop-error@example.com` / synthetic `.invalid` emails where real ones exist, one-time Russian phone normalization pass (feeds `phone_review_queue`), and **fix the lesson-split import (D2)** so 1 imported lesson is 1 row of correct duration, not N hourly rows.
- **Backend touched:** one-off migrations/scripts over `app.lessons`, `app.leads`, `app.profiles`, `app.entity_comments`, `app.phone_review_queue`; no API contract change.
- **Regression checks:** (a) dry-run via `import_batches` (mode=dry_run) before apply; (b) `schedule/matrix` overlap count drops after KVA-177 cleanup (assert the ~199 → ~0 delta); (c) phone normalizer SQL expression stays in lockstep with `normalizePhoneRu` TS; (d) no row count regressions on core tables (before/after counts captured).

### Phase 7 — Acceptance / on-device re-audit (KVA-123)

- **Scope:** **KVA-123** Windows manager UX on-device re-audit against the shipped reskin; full RBAC walk-through (all 5 roles); regression-checklist sign-off (§5f); owner per-window acceptance against v7.
- **Backend endpoints covered:** none new — verification only.
- **Regression checks:** full §5f checklist green; baseline network diffs clean for every reskinned screen; contract + integration suites green.

---

## 4b. Real-bug fixes the mockup can only depict (real-code work, assigned to phases)

These are bugs the owner flagged (coverage report §5 blocker 3) that a mockup cannot solve — they are real Flutter/backend code work, not design:

| Bug | What it is | Real-code fix | Phase |
|---|---|---|---|
| **E2 voice playback** | v7 voice bubble plays a toast stub; real app uses `just_audio` + download-token | Verify/repair `VoicePlayerWidget` lazy URL resolution (`POST /files/:id/download-token`) + waveform progress; fix any playback failure path | **Phase 4** |
| **E3 gallery attachments** | v7 attach/emoji/mic are stubs; gallery/image-from-gallery is the bug owner is angry about | Wire composer attach to real `FilePicker`/gallery → `ChatAttachmentService` (image vs file MIME), full-screen `InteractiveViewer` | **Phase 4** |
| **E4 splash** | splash/loading polish | Real splash + skeleton-on-boot (K14) wired to gate load | **Phase 1** |
| **B1–B4 import data quality** | fake `holli-hop-error@example.com`/`.invalid` emails, missing comments, un-normalized phones | One-off backend scripts + `phone_review_queue` pass (data, not API) | **Phase 6** |
| **D1 "48 → real grid"** | schedule shows a fixed/wrong lesson count instead of the real grid; tied to the import lesson-split bug | Backend import fix (1 lesson = 1 correctly-durationed row) + Flutter renders real `month-summary`/`matrix` data | **Phase 2 (UI) + Phase 6 (data)** |

---

## 5. No-backend-bug / no-regression strategy

The redesign is a reskin. The single biggest risk is a reskinned screen quietly changing the API calls it makes. The strategy below makes that impossible to ship unnoticed.

### (a) Wire-to-existing-service checklist (per screen, before any reskin PR opens)

For each v7 screen, before writing UI, fill a one-row checklist: **{v7 screen → existing Flutter widget it replaces → exact service methods it calls → exact endpoints those hit → RBAC roles}**. Derived directly from the §2 matrix. A screen may not be reskinned until its row is filled; a method not already in the matrix means the screen is doing something new (escalate — it is probably an orphan or a contract change).

### (b) Same-API-calls baseline (capture → reskin → diff)

1. **Before** touching a screen, run the existing app against a seeded dev backend and **capture the network trace** for every interaction on that screen (endpoint, method, query params, body shape, headers). Store as a JSON fixture per screen under `test/baseline/<screen>.json`.
2. **After** the reskin, replay the same interactions and **diff the trace** against the baseline. The diff must be empty for reskin phases (1, 3, 4). For phases that add endpoints (2-data, 5), the diff may only contain the **new additive** calls — never a changed or dropped existing call.
3. CI gate: a script asserts `git diff server/` is empty for pure-frontend PRs (see (e)) and that the network diff for the touched screen is empty-or-additive.

### (c) Contract + integration tests stay green

- **Backend contract tests** (NestJS e2e per controller) must remain green untouched through Phases 1, 3, 4 — they are the executable spec of the contract the Flutter services depend on. Any new endpoint (expense, subscription-packages, homeworks) ships **with** its own contract test in the same PR.
- **Flutter service-layer tests** (mock HTTP) assert each service still serializes the same request/parses the same response. Reskin PRs must not edit `lib/core/services/*` request/response code — only call sites move.
- **Integration smoke** per phase: auth→gate→role-route (P1), book→conflict→save (P2), drag-status + convert (P3), send/voice/attach + auto-lead (P4), payment/expense/report (P5).

### (d) RBAC parity — 5 roles enforced identically

- The redesign keeps **all 5 backend roles** (`client`, `teacher`, `admin`=Администратор, `manager`=Управляющий, `system_admin`=Администратор системы; business hierarchy **`manager` (Управляющий) > `admin` (Администратор)**) even though v7 models only 4. RBAC is **set-based `@Roles(...)`**, not a linear hierarchy; P1 tightens it so `admin` no longer reaches manager-only endpoints/nav (A1). `system_admin` keeps its **unconditional `RolesGuard` bypass** (`backend-platform.md` rule 11) and the **last-`system_admin` demotion guard** (rule 9).
- Per-screen RBAC is asserted against the inventories, not the prototype: e.g. staff create/update is `admin`+ only; analytics/finance/tasks-write is manager/admin/system_admin (`assertCanWriteCrm`); teacher lesson `PATCH` is status/notes-only; client sees only own student's payments/tasks; channel posting manager/admin only; deletion-request PATCH `admin`-only.
- Add a **role-matrix test** that, for each role, walks every reskinned screen and asserts the visible actions == the backend-permitted actions. Catches the v7-only "admin == manager" simplification (coverage A1) before it ships.

### (e) Per-PR backend-untouched assertion (pure-frontend phases)

- Phases **1, 3, 4** (and the UI parts of 5) carry a CI check: **`git diff --name-only origin/main... -- server/` must be empty**. A non-empty result fails the PR. This makes "no backend regression" mechanically enforced for reskin work.
- New-backend PRs (expense, subscriptions, homework, data cleanup) are explicitly labeled `backend` and are the only PRs allowed to touch `server/` — each with migration + contract test + audit event.

### (f) Pre-merge regression checklist (every PR)

Before any merge:
1. `git diff server/` empty (pure-frontend PR) **or** scoped to the declared new endpoints only.
2. Network baseline diff for every touched screen is empty-or-additive.
3. Backend contract e2e suite green; Flutter service tests green.
4. RBAC role-matrix test green (5 roles, `system_admin` bypass intact).
5. The screen's §2 matrix row endpoints are all still reachable in the build (no orphaned capability).
6. Phase-specific integration smoke green.
7. Owner/visual sign-off against the corresponding v7 window.

---

## 6. Proposed Linear mega-epic structure

One mega-epic, one sub-epic per phase, concrete child tasks under each. The 5 existing tasks merge in at their marked slots (**KVA-153, KVA-157, KVA-181, KVA-177, KVA-123**). KVA-191 (epic «Завершение») is absorbed as the mega-epic; its children re-slot. Ordered for execution; Phase 6 runs in parallel from the start.

```
MEGA-EPIC: v7 Redesign → Existing App Migration (reskin, no backend regressions, full coverage)
│   Scope: port approved v7 design onto existing Flutter+NestJS, keep every backend endpoint wired, add only the genuinely-new flows.
│   (absorbs KVA-191 «Завершение»)
│
├─ SUB-EPIC P0 — Lock spec + design tokens
│     • P0-1 Owner per-window v7 sign-off — clickthrough crm-redesign-v7.html, capture decisions.
│     • P0-2 Extract design tokens into Flutter ThemeData — gold/bg/surface/divider/Inter/radii/icons.
│     • P0-3 Shared component lib — toast, pop-menu, drawer, sheet, skeleton-shimmer widgets.
│     • P0-4 Per-screen wire-to-service checklist (§5a) seeded from §2 matrix.
│
├─ SUB-EPIC P1 — RBAC + nav shell + auth reskin  [pure-frontend]
│     • P1-1 v7 nav shell — desktop rail / phone bottom-bar + «Ещё» overflow, 5-role aware.
│     • P1-2 Fix admin≠manager nav + disable role-edit for admin (A1/I9); keep system_admin (5th role).
│     • P1-3 v7 login + signup→OTP + 2FA reskin — wire MagicAuthService unchanged.
│     • P1-4 v7 forgot→code→newpass + auth-methods (MFA toggle, set password, identities).
│     • P1-5 First-run onboarding slides → legal consent (v7p2-2) — /legal/documents + consents.
│     • P1-6 Splash + boot skeleton (E4) wired to /legal/gate.
│     • P1-7 Network baseline + RBAC role-matrix test for auth/gate/nav.
│
├─ SUB-EPIC P2 — Schedule rebuild  [frontend + data fix]
│     • P2-1 v7 day grid — sticky time-col + sticky room/teacher headers (K10), Год/Месяц/День.
│     • P2-2 Block-drag vertical booking + sub-hour coefficient + tap-cell=1h → POST /crm/lessons.
│     • P2-3 Month-first default (K11) + single header (D8) → schedule/month-summary.
│     • P2-4 Conflict warning in booking sheet → schedule/matrix (4 types, pair-dedup).
│     • P2-5 Lesson attendance UI (v7p2-3) → GET/PATCH /crm/lessons/:id/attendance.
│     • P2-6 Reschedule/cancel wiring (PATCH/DELETE) + reminder/notify preserved.
│     • P2-7 Teacher schedule reskin — read + complete + notes + attendance (own scope).
│     • P2-8 Render real grid (D1 UI half) from month-summary/matrix (depends on P6-4 data fix).
│
├─ SUB-EPIC P3 — Clients redesign  (MERGE: KVA-181)  [pure-frontend]
│     • P3-1 v7 Лиды kanban — in-column drag (THRESH tap-vs-drag), insertion line, drop-arm.
│     • P3-2 Continuous lead→student transfer (dwell → branch → discipline) → createStudent.
│     • P3-3 Slide-out filters + persistent search (C3) [KVA-181 D1 search, D2 mobile filters].
│     • P3-4 Filter presets + load-more pagination (v7p2-7) → keyset cursor preserved.
│     • P3-5 Dual-target column editor (C5) → lead-status order + branch-disciplines order.
│     • P3-6 Card drawer reskin — Инфо/Задачи/Комментарии/Семья/История + custom fields + duplicates.
│     • P3-7 Loss-reason capture on terminal drop → loss-reasons + status-history.
│     • P3-8 Fix slow kanban autoscroll [KVA-181 D3]; deep-link to cards [D4]; state preservation [D5].
│     • P3-9 Family member add/remove wiring (backend already exists) + "not saved in CRM" state.
│
├─ SUB-EPIC P4 — Chat parity + real bug fixes  [pure-frontend]
│     • P4-1 v7 two-pane conversation + consec bubbles + date separators + skeleton (K14).
│     • P4-2 Full message ⋯ menu — edit/reply/forward/reactions/pin wired to existing services.
│     • P4-3 E2 voice playback fix — just_audio + download-token + waveform progress.
│     • P4-4 E3 gallery/file attachments — real FilePicker→ChatAttachmentService (image vs file).
│     • P4-5 Keep channels reskinned (list/posts/permissions) — DO NOT drop (orphan §H).
│     • P4-6 Keep administration chat + verify auto-lead trigger still fires (orphan §A).
│     • P4-7 Notification-center list → GET /notifications + read (close orphan §I).
│
├─ SUB-EPIC P5 — Reports/Finance/Tasks/Users/Settings + expense write  [frontend + small backend]
│     • P5-1 Reports reskin — Аналитика/Финансы/Активность(v7p2-4)/Управление → 14 /analytics/*.
│     • P5-2 Tasks board reskin → /crm/tasks (filters/reassign/timeline).
│     • P5-3 Users list + link-to-CRM (v7p2-6) + role change + broadcast → MagicProfileAdminService.
│     • P5-4 Settings reskin — custom-field editor, admin-chat avatar, branch/room/discipline mgmt.
│     • P5-5 [NEW-BE] Expense write API — GET/POST/PATCH/DELETE /crm/expenses + audit + contract test.
│     • P5-6 Wire v7 «Добавить расход» sheet to P5-5.
│     • P5-7 Close orphans — CSV/XLSX export buttons; sources/data-quality/responsible cards;
│             phone-review-queue + merge "Качество данных" panel; admin deletion-request queue.
│
├─ SUB-EPIC P5b — Subscription packages  (MERGE: KVA-153)  [new backend + frontend]
│     • P5b-1 [NEW-BE] 0033 subscription_packages migration + subscriptions FK (package_id, payment_id).
│     • P5b-2 [NEW-BE] /crm/subscription-packages CRUD + contract test.
│     • P5b-3 [NEW-BE] POST /crm/students/:id/subscriptions/issue (sale→subscription+payment, txn).
│     • P5b-4 [NEW-BE] lessons_used decrement on attendance (idempotent per participation row).
│     • P5b-5 Package catalog UI (Settings) + «Выдать абонемент» (student detail + client portal).
│
├─ SUB-EPIC P5c — Homework with files  (MERGE: KVA-157)  [new backend + frontend]
│     • P5c-1 [NEW-BE] 0034 lesson_homeworks + homework_attachments migration.
│     • P5c-2 [NEW-BE] homework_attachment file purpose (reuse Files subsystem, MIME+25MB).
│     • P5c-3 [NEW-BE] /crm/homeworks endpoints (assign/submit/attachments) + RBAC + contract test.
│     • P5c-4 Teacher assign+attach UI (lesson sheet / student detail).
│     • P5c-5 Client submit+download UI (replaces thin HomeworkWidget).
│
├─ SUB-EPIC P6 — Data-quality cleanup  (MERGE: KVA-177)  [backend-only, parallel from day 1]
│     • P6-1 [KVA-177] ~199 room-lesson overlap cleanup (dry-run via import_batches → apply).
│     • P6-2 B2 null fake holli-hop-error@example.com / synthetic .invalid emails where real exist.
│     • P6-3 B3 one-time RU phone normalization pass → phone_review_queue (SQL≡TS lockstep).
│     • P6-4 B4/D2 fix lesson-split import — 1 lesson = 1 correctly-durationed row (unblocks P2-8).
│     • P6-5 B1 re-import missing comments.
│
└─ SUB-EPIC P7 — Acceptance / on-device re-audit  (MERGE: KVA-123)
      • P7-1 [KVA-123] Windows manager UX on-device re-audit vs shipped reskin.
      • P7-2 Full 5-role RBAC walkthrough + role-matrix test sign-off.
      • P7-3 Pre-merge regression checklist (§5f) green across all phases.
      • P7-4 Owner per-window acceptance vs v7 + coverage-matrix orphan re-check (no dropped endpoint).
```

**Suggested execution order:** P0 → P1 → P2 (with P6 in parallel) → P3 → P4 → P5 → P5b → P5c → P7. P6 starts at P1 and feeds P2-8. New-backend sub-epics (P5b, P5c, and P5-5) are the only ones touching `server/` beyond the data track.
