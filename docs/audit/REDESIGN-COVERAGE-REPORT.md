# MagicMusicCRM — Prod-Readiness Coverage Report (Real App vs v6 Redesign Prototype)

**Date:** 2026-06-21
**Author:** Lead architect (automated synthesis)
**Inputs:** 8 area audits in `docs/audit/`, `docs/prototypes/crm-redesign-v6.html`, `docs/superpowers/specs/2026-06-20-crm-feedback-redesign.md`
**Question being answered:** How ready is the v6 redesign prototype to *become* the real app? What is lost on a naive port, what is genuinely new, and what must be built first?

**Legend:** ✅ full · 🟡 partial (UI shell present, logic/depth missing) · ❌ missing · ✨ new-in-prototype-only

---

## 1. Full Functionality Map — the real app's complete feature set

The real app = Flutter client (`messenger`, `crm`, `admin`, `manager`, `teacher`, `client`, `profile`, `auth`) + NestJS/PostgreSQL backend (`auth`, `crm`, `messenger`, `notifications`, `files`, `analytics`, `legal`, `settings`, `profile`, `audit`, `security`). Grouped by domain:

### A. Chat / Messenger
- Telegram-style chat list: direct, group, channel, administration chats; unread badges, mute, pinned-chat sort, group answered/unanswered status icon, last-message preview, search-by-name.
- Conversation: optimistic text send, edit, delete (own + moderated for admin), reply, forward, reactions (8 emoji, optimistic toggle), pinned-message bar + dialog, in-chat search, date separators, scroll-to-bottom FAB with unread badge, presence banner, typing indicator.
- Message types: text, voice (record AAC-LC + waveform playback via download-token), image (inline + full-screen zoom), file (typed download cards, open_filex).
- Attachments: `POST /files` multipart, single-use signed download tokens, 25 MB cap, MIME-based type detection, avatar uploads.
- Read state: per-chat unread, optimistic clear, `is_read` single/double tick, realtime `chat.updated` reconciliation.
- Channels: list/create/edit, per-user/role permissions (canRead/canWrite), posts, access checks, manager/admin-only posting.
- Groups: create (staff-only), member add/remove, members tab with roles, responded-at SLA tracking.
- Administration chat: client↔school singleton auto-creation; **auto-lead creation on first non-staff message** (pg advisory lock).
- Realtime: Socket.IO `/realtime`, rate-limited room.join/typing/presence, server-push events, JWT-authed.
- Notifications: local push on incoming, deep-link navigation, mute suppression.
- CRM-from-chat: save-as-lead/student, open contact card, resolve lead↔chat-user.
- ChatInfoDialog: media/files/links tabs, mute, staff notes (manager/admin), inline channel editing.
- Broadcast: admin mass push (all/students/teachers), recipient count.
- Backend depth: SLA analytics on administration chats, soft-delete content erasure, cross-chat attachment guard, reaction dedup, push pipeline (FCM v1 + encryption), email outbox (Resend + SMTP fallback, retry).

### B. Schedule
- Year-implicit / Month calendar (per-day lesson count) / Day view (room-axis & teacher-axis swimlanes).
- Branch selector with per-branch `utc_offset_minutes`, room colour coding.
- Create lesson (dialog / empty-slot tap), lesson detail, cancel/reschedule, attendance marking (`lesson_participation`, teacher-permitted).
- Backend: `schedule/matrix` conflict detection (missing_teacher, branch_mismatch, room_overlap, teacher_overlap; pair-deduped), `schedule/month-summary`, room availability, lesson reminders scheduler (day/hour, exactly-once claim), reschedule notifications to teachers.
- Teacher schedule: own lessons, mark completed, edit plan/notes, mark attendance.
- Client portal: upcoming/past lessons, next-lesson live countdown.

### C. Clients / Leads / Students
- Leads kanban: dynamic status columns, drag-and-drop status move (optimistic + rollback), cursor pagination, debounced search, quick filters, dropdown filters (branch/status/discipline/level/category), filter presets (FlutterSecureStorage), manage-columns (add/reorder/delete/colour), "Без статуса" column, create-lead FAB.
- Lead card: full detail dialog — editable fields + custom CRM fields, links/activity, **Family**, **status history**, comments, **duplicate-candidate detection + link**, summary chips, convert-to-student.
- Students board: per-branch discipline columns (read-only v1), student detail popup, full `/student/:id` screen.
- Convert/ConvertLeadDialog, save-from-chat, manual lead auto-create.
- Backend: leads board/card/status-history/chat-user, loss-reasons, lead-sources, students search + balances + invite + subscriptions, teachers, staff, branches, disciplines, rooms, groups, **dedup/merge + undo (transactional, allow-listed)**, **phone normalization + review queue**, **families/contacts**, HolliHop metadata proxy, comments/timeline, import-batch audit.

### D. Users / RBAC
- 5 roles: client < teacher < manager < admin < system_admin; strict route-level enforcement; release-gate funnel.
- Users/profiles list, role filter, search, **role assignment**, link/unlink CRM entity, broadcast.
- Backend: profile admin (list/detail/notes/link-candidates/auto-link/manual-link/role-update), last-system_admin guard, CRM link exclusivity, RolesGuard with system_admin bypass.

### E. Reports / Finance / Tasks
- Reports: Аналитика (KPIs, lessons/revenue bar charts, teacher ranking, monthly table), Финансы (fl_chart dashboard, teacher efficiency, room load), Активность (audit log), Управление (funnel, debts, forecast, branches, churn, chat SLA, loss reasons).
- Finance: headline aggregate, period filter, payment list + add, payment types, debtors + top-up, expected payments, conversion tracking.
- Tasks: full filtered task board, status changes, reassign, entity timeline sheet, create task; client homework completion.
- Backend analytics: 14 `/analytics/*` endpoints, finance report, CSV + (pseudo) XLSX export, materialized views + refresh worker, manager dashboard, data-quality, responsible-distribution, sources.

### F. Settings / Config
- CRM custom-field schema config (8 types, per-entity, required/hint/options), lead-status management, admin-chat avatar, branch/room/discipline/teacher management.
- Backend: `system_settings`, env Joi validation, security gate (CI), config defaults.

### G. Profile / Portal / Auth
- Auth: login, register, email-OTP (signup + 2FA), password reset (2-phase), set-password, identities, logout-all, refresh-rotation + reuse detection, Sentry.
- Release gate: loading, onboarding, legal-consent, legal-documents viewer, account-deletion request + status (hard lockout).
- Profile: edit + avatar crop/upload, auth-methods (MFA toggle, password), DOB.
- Client portal: child switcher, subscription card, upcoming/history lessons, countdown, progress notes (read-only), homework.

### H. Data / Schema
- 32 migrations, `app` schema: users, profiles, branches, rooms, lead_statuses, leads, students, teachers, groups, group_students, lessons, lesson_participation, tasks, payments, expected_payments, subscriptions, student_balances, entity_comments, expenses, user_crm_links, staff_members, import_batches, duplicate_candidates, lesson_reminders, lead_loss_reasons, lead_sources, disciplines, branch_disciplines, student_disciplines, lead_status_history, student_status_history, families, family_members, contacts, merge_log, mv_finance_monthly/teacher_performance/room_load, analytics_refresh_runs, chats, chat_members, messages, message_reactions, channels, channel_permissions, channel_posts, notifications + deliveries + devices, email_outbox, file_objects, file_download_tokens, legal_documents/consents, account_deletion_requests, system_settings, profile_notes, audit_events, refresh_sessions + auth token tables.

---

## 2. Coverage Matrix (real feature → v6 prototype)

| # | Real feature | v6? | Note |
|---|---|---|---|
| **CHAT** |
| 1 | Chat list (direct/group/channel/admin) | 🟡 | 6 mock chats; no channel type, no admin-chat concept, no group SLA icon |
| 2 | Optimistic text send | ✅ | Bubble appends instantly; tick upgrades after 700ms |
| 3 | Voice message record + playback | 🟡 | Waveform bubble renders; playback is a toast stub (real app plays) |
| 4 | Image/file attachments | ❌ | Attach/emoji/mic are toast stubs only |
| 5 | Edit / delete / reply / forward / reactions | 🟡 | ⋯ menu has save-as-lead/open-card/pin/clear; no edit/reply/forward/reactions UI |
| 6 | Pinned-message bar, in-chat search, presence, typing | 🟡 | Live chat-list search ✅; pin-chat menu item; no pinned bar, typing, presence dot in convo |
| 7 | Read receipts (single/double tick) | ✅ | Tick upgrade simulated |
| 8 | Channels (create/permissions/posts) | ❌ | Absent entirely |
| 9 | Save-as-lead / open card from chat | ✅ | ⋯ menu + real drawer for open-card |
| 10 | Auto-lead on first admin-chat message | ❌ | No administration-chat / auto-lead concept |
| 11 | Realtime (Socket.IO, push notifications) | ❌ | No network; all in-memory |
| 12 | Skeleton loader on chat open | ✅ | 6-row shimmer ~320ms (K14) |
| **SCHEDULE** |
| 13 | Month view (per-day counts) | ✅ | Default view, picker, today highlight (K11) |
| 14 | Year view | ✨ | 12-month grid — new, not in real app as a distinct view |
| 15 | Day view room-axis / teacher-axis | ✅ | Sticky headers (K10), both axes |
| 16 | Block-drag vertical booking + sub-hour coefficient | ✨ | Owner's new UX concept; real app uses dialogs |
| 17 | Tap-cell = 1h lesson | ✨ | New |
| 18 | Booking sheet (student/teacher/room/duration) | 🟡 | UI complete; appends to mock array, no persistence/validation server-side |
| 19 | Conflict detection (pre-save) | 🟡 | `findConflicts()` warns; far simpler than backend matrix (4 conflict types, pair-dedup) |
| 20 | Branch selector + per-branch rooms | 🟡 | Chip selector; no UTC offset / timezone logic |
| 21 | Attendance marking | ❌ | No attendance UI |
| 22 | Cancel / reschedule lesson | ❌ | "Изменить" is a toast stub; no reschedule |
| 23 | Lesson reminders | ❌ | Backend-only; n/a in prototype |
| **CLIENTS/LEADS/STUDENTS** |
| 24 | Leads kanban + in-column D&D | ✅ | Pointer drag, insertion line, drop-arm (G3/G5) |
| 25 | Drag status move + optimistic | ✅ | Move + toast; loss-reason prompt on "Отказ" |
| 26 | Continuous lead→student transfer | ✨ | Dwell tab-expansion → branch → discipline, in-hand (H7/G4/G6) — net-new |
| 27 | Slide-out filters + persistent search | ✅ | Filter drawer + full-width search (C3) |
| 28 | Column add/rename/reorder | ✅ | Dual-target editor (lead + per-branch student) (C5) |
| 29 | Cursor pagination / load-more | ❌ | All leads in memory; no pagination |
| 30 | Quick filters + dropdown filters (discipline/level/category) | 🟡 | Chips present; not wired to HolliHop metadata depth |
| 31 | Filter presets (persisted) | ❌ | Not present |
| 32 | Lead card: Инфо/Задачи/Комментарии/Семья/История | ✅ | All 5 tabs present with mock data |
| 33 | Custom CRM fields in card | ❌ | No custom-field schema rendering |
| 34 | Duplicate-candidate detection + link | ❌ | Absent |
| 35 | Loss reason (capture + report) | ✨ | Captured on drop, feeds report — richer than real app's plain reason field |
| 36 | "Not saved in CRM" state | ❌ | Removed (I3); all mock data saved=true — real app needs this state |
| 37 | Students board per-branch discipline cols | ✅ | Per-branch cols, read-only cards |
| 38 | Full `/student/:id` detail screen | ❌ | Only the drawer; no deep student screen (lessons/payments/groups/timeline) |
| **USERS / RBAC** |
| 39 | 4-role nav + RBAC | ✅ | All 4 roles simulated; admin≠manager fixed (A1/I5) |
| 40 | Users list + jump-to-card | ✅ | Open-card per kind (A2) |
| 41 | Role change (manager-only) | ✅ | Pop-menu mutates role; disabled for admin (I9) |
| 42 | Link/unlink CRM entity | ❌ | No link-to-CRM flow |
| 43 | 5th role (system_admin) | ❌ | Only 4 roles; no system_admin |
| 44 | Release gate / onboarding / legal consent | 🟡 | Login redesigned; legal docs + delete in profile (K4); no gate funnel/onboarding |
| **REPORTS/FINANCE/TASKS** |
| 45 | Reports: funnel/branches/loss/debts/forecast/churn/SLA/weekly | ✅ | 8 cards, inline SVG bars (I6) |
| 46 | Reports: Активность (audit log) | ❌ | Not present |
| 47 | Reports: monthly tables / teacher ranking / fl_chart depth | 🟡 | Sparklines only; no detailed tables |
| 48 | Finance: revenue/expense/profit/debtors | ✅ | KPI cards + sparklines |
| 49 | Add expense | ✨ | Expense add sheet — real app has NO expense write API |
| 50 | Add payment / debtors top-up | ❌ | No payment create / top-up |
| 51 | CSV / XLSX export | ❌ | Backend has it; prototype none |
| 52 | Tasks list + check toggle + new task | 🟡 | Basic list; no filters/reassign/timeline/priority/due |
| 53 | Client homework completion | ✅ | Checkable homework in My School |
| **SETTINGS/CONFIG** |
| 54 | Lead-status / funnel column config | ✅ | Column editor in Настройки |
| 55 | Per-branch student funnel + rooms config | ✅ | Branch set-cards, rooms, add/edit |
| 56 | Teacher management | 🟡 | Add/edit teacher in settings; lighter than CRM staff/teacher CRUD |
| 57 | Custom-field schema editor | ❌ | Absent |
| 58 | Admin-chat avatar setting | ❌ | Absent |
| **PROFILE/PORTAL/AUTH** |
| 59 | Login / signup / logout | ✅ | Redesigned auth screen (K2), quick-role login |
| 60 | Email OTP / 2FA / password reset | ❌ | Demo auth only; no OTP/reset/MFA |
| 61 | Profile edit + avatar upload | 🟡 | Profile hero/contact; no editable avatar upload |
| 62 | Legal docs + account deletion request | ✅ | Both present (K4) |
| 63 | Client portal (subscription/lessons/homework/countdown) | 🟡 | Subscription card, lessons, homework ✅; no live countdown, no progress notes |
| 64 | Child switcher | ✅ | Kid switch in My School + profile preview |
| 65 | Teacher: own students, lesson comments, mark complete | 🟡 | Students list + lesson comment (K5/K8); no mark-complete/attendance |

**Tally:** ✅ ~28 · 🟡 ~17 · ❌ ~21 · ✨ ~7 (of ~73 mapped features).

---

## 3. Gaps — real-app features NOT represented in v6 (lost on a naive port), ordered by importance

1. **All networking / realtime / persistence.** The prototype is 100% in-memory mock. No REST, no Socket.IO, no optimistic-then-server reconciliation, no auth tokens, no file storage. This is the single largest gap — everything else sits on top of it.
2. **Channels** (list/create/permissions/posts/access) — entirely absent. A whole messenger sub-system.
3. **Auth depth:** email verification, OTP/2FA, password reset, refresh-token rotation + reuse detection, release-gate funnel, onboarding. Prototype auth is "any non-empty creds pass."
4. **Full `/student/:id` detail screen** (lessons, payments, groups, subscriptions, timeline, comments) — only a light drawer exists.
5. **Custom CRM field schema** (definition + rendering in cards + settings editor) — absent; this drives the entire lead/student data model in the real app.
6. **Dedup / merge / duplicate-candidate** flows, **phone normalization + review queue**, **HolliHop metadata** — none present; these are core data-quality features the owner explicitly flagged (B1–B4).
7. **Attachments / voice playback / image-from-gallery** — the exact bugs (E2/E3) the owner is angry about are still stubs in the prototype; not yet designed.
8. **Tasks depth** (filters, priority, due-date, reassign, entity timeline, status workflow) and **client/teacher task scoping**.
9. **Finance writes** beyond expenses: add payment, debtor top-up, expected payments; **CSV/XLSX export**.
10. **Reports depth:** Активность audit log, detailed monthly/teacher tables, real chart library parity.
11. **Cursor pagination & filter presets** on the leads board (scalability + saved views).
12. **Attendance, cancel/reschedule, lesson reminders, reschedule notifications.**
13. **Profile/RBAC plumbing:** link/unlink CRM entity, 5th role (system_admin), broadcast push, profile notes, avatar upload, account-deletion *processing* (admin side).
14. **Timezone / UTC-offset** handling per branch (real app does it; prototype ignores it).
15. **Group chat SLA / responded-at, presence, typing indicators** in conversation.

---

## 4. New in the Redesign (prototype adds; real app lacks)

1. **Per-branch student funnels** — each branch carries its own independent discipline/funnel columns (`BRANCHES[i].cols`); real app's student board is a fixed per-branch discipline grouping, not editable per-branch funnels.
2. **Continuous in-hand lead→student transfer** (dwell-debounced tab-expansion → branch drop-zone → discipline column, one gesture) — genuinely novel UX; real app uses a modal `ConvertLeadDialog`.
3. **Year view** for schedule (12-month grid) — not a distinct view in the real app.
4. **Vertical block-drag booking with sub-hour coefficient fill** — the owner's new schedule paradigm; real app uses `CreateLessonDialog`.
5. **Loss-reason capture on drop** (prompted when dropping into "Отказ") feeding the Reports "Причины потерь" funnel live — tighter loop than the real app's plain `reason_id` field.
6. **Redesigned login/auth screen** + quick "Войти как…" role switcher (K2).
7. **System-wide optimistic UI + skeleton loaders** as a deliberate design language (K6/K14) — partially present in real app (chat, kanban) but the prototype standardizes it everywhere.
8. **Expense add sheet** — the real backend has *no* expense write API at all; the prototype invents the UX for one.
9. **In-place RBAC demonstration** (role + frame toggle, CSS-driven `data-role`/`data-pov`) — a design artifact, not a shippable feature, but valuable as the RBAC spec.

---

## 5. Prod-Readiness Assessment

### Overall coverage estimate: **~40%** of the real app's functionality is represented in the v6 prototype.
Reasoning: the prototype nails **visual + UX design, RBAC navigation, kanban interaction, schedule layout, and the redesigned flows the owner explicitly asked for** (roughly the front-50% of the experience). But it is a **design artifact, not an application**: zero backend wiring, and ~21 substantial feature areas are missing or stubbed. As a *visual/interaction spec* it is ~85% ready; as a *shippable app* it is ~15%. Blended, weighting the missing data/integration layer heavily, ≈40%.

### Top blockers to porting the redesign to prod
1. **No backend integration layer.** Every screen is in-memory mock. Porting means re-binding every interaction to `MagicCrmService` / `MagicMessengerService` / `MagicRealtimeService` / auth + files. This is the bulk of the work and is entirely unbuilt in the prototype. The real app already has these services — the prototype must be reconnected to them, not the other way around.
2. **Missing core data systems** the redesign silently assumes away: custom-field schema, dedup/merge, phone normalization, channels, full student detail, attachments/voice, OTP auth, pagination. Each is a real subsystem with backend already present but no prototype design.
3. **The owner's actual bug list (E1–E6, D1–D8, B1–B4) is only partially addressed by visuals.** Tap-vs-drag (E1) ✅, sticky headers (K10) ✅, single month header (D8) ✅, RBAC (A1) ✅ — but voice playback (E2), gallery attachments (E3), splash (E4), import data quality (B1–B4), and the "48→real grid" data bug (D1) are not solvable by the mockup and remain open in the real codebase.

### Recommended sequencing (what to build first)
Treat the prototype as the **approved design spec** and port *into the existing Flutter app*, not greenfield:

- **Phase 0 — Lock the spec.** Owner clicks through v6, signs off per-window. Extract design tokens + component inventory into the Flutter theme.
- **Phase 1 — RBAC + nav shell (highest owner pain, lowest risk).** Implement the corrected role nav (admin ≠ manager, no role-edit for admin — A1/I9), manager nav order (K12), 4-role rendering, login/logout redesign (K2). This is mostly real-app refactor + the gate already exists.
- **Phase 2 — Schedule rebuild (biggest conceptual change).** Block-drag vertical booking, sub-hour coefficient, sticky headers (K10), month-first (K11), single header (D8). Wire to existing `/crm/lessons` + `schedule/matrix` conflict API. Fix the import "1 lesson ≠ N hourly" data bug (D2) server-side in parallel.
- **Phase 3 — Clients redesign.** In-column D&D, continuous lead→student transfer (H7), slide-out filters + search (C3), column editor (C5), optimistic transfer (K6), "not saved" state (E5/I3). Wire to existing leads board / convert / save-from-chat. Restore cursor pagination + filter presets the prototype dropped.
- **Phase 4 — Chat parity + bug fixes.** Port the visual refresh onto the existing messenger; fix voice playback (E2) and gallery attachments (E3) — these are real-code fixes, not design. Add skeletons (K14).
- **Phase 5 — Reports/Finance/Tasks/Users/Settings.** Wire the report cards to the 14 `/analytics/*` endpoints (already built), tasks to `/crm/tasks`, users to profile-admin. Add the expense write endpoint the prototype implies.
- **Phase 6 — Data-quality cleanup (parallel track, backend).** B1–B4: re-import comments, null the fake `holli-hop-error@example.com` emails, one-time phone normalize pass, fix lesson-split import. Independent of the redesign and can run alongside Phase 1.

**Bottom line:** the v6 prototype is an excellent, owner-approved *design and interaction blueprint* covering ~40% of functionality and ~85% of the desired UX. It is not close to a shippable app — but it shouldn't be ported as one. The correct move is to reskin/reflow the *existing, already-backed Flutter app* to match v6, building the genuinely-new flows (block-booking, continuous transfer, per-branch funnels) and fixing the real bugs the mockup can only depict, not solve.
