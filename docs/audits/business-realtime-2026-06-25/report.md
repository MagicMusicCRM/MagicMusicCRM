# Business Logic and Realtime Audit - 2026-06-25

## Executive Summary

The post-deploy audit focused on the broken business workflows reported by the owner: unstable realtime, chat ownership confusion, admin access gaps, lesson visibility, payments/subscriptions visibility, client navigation, lead/student drag-and-drop, HolliHop-derived fields, and inconsistent client-card opening.

The critical root cause was not a single UI bug. The application had mismatched backend policies, incomplete realtime fan-out, frontend-only invalidation assumptions, and several navigation paths that bypassed the unified client-card modal. This release closes the highest-impact gaps: admin/manager operational access, realtime event coverage plus polling fallback, chat work history, lead/student status movement, lesson/payment/subscription/group/task invalidation, client-facing navigation, and modal consistency.

Backend was deployed to staging at `https://api.phantom-net.ru/api` on 2026-06-25. Health, migrations, and client realtime smoke passed. Windows release and Android debug client builds were produced, and the Android build was installed to emulator `emulator-5554`.

## Critical Issues

| Issue | Status | Resolution |
|---|---:|---|
| Admin could not reliably perform operational work for any client | Fixed | Backend policies now treat admin as operational staff for CRM/payments/tasks/groups/client card workflows while keeping role mutation restricted. Frontend nav/RBAC exposes the same operational surfaces. |
| Client/admin chat state diverged after realtime glitches | Fixed | Messenger screens now use Socket.IO events as primary source and silent REST polling fallback when no realtime event arrives. |
| "Nobody took in work" / responsible admin history was not auditable | Fixed | `app.chat_work_events` migration plus service writes record assign/unassign work events and expose them in CRM timeline/card context. |
| Lessons created for a client could be visible to teacher but not client | Fixed | Client lesson queries now include lead-linked and student-linked lessons; lesson realtime fan-out includes affected users. |
| Payments/subscriptions created by staff were not reliably visible to clients | Fixed | Backend access and realtime fan-out were expanded for payments/subscriptions; client dashboard invalidates balances, payments, and subscriptions on relevant CRM events. |
| DnD lead/student status movement was incomplete | Fixed | Lead to student conversion remains aligned with visual instruction commit `b14dc4e`; reverse student to lead is implemented as a status-only backend operation. |

## High Issues

| Issue | Status | Resolution / Evidence |
|---|---:|---|
| Full-app realtime did not cover all business entities | Fixed | `crm.changed` coverage now includes lesson, lead, student, payment, subscription, task, group, comment, chat_work, notification. Frontend has fallback invalidation every 30s and chat fallback polling every 12s after realtime silence. |
| Admin message/client message identity was unstable in realtime merge | Fixed | Messenger DTO mapping and sender merge paths were normalized; administration chat still masks staff identity to clients as `Администрация`, while staff-side UI keeps actor/audit context. |
| Client interface looked like an admin-only CRM surface | Fixed | Client dashboard now has separate mobile bottom tabs and desktop sidebar sections: lessons, schedule, payments, subscriptions, chat, profile/student data. |
| Client card opened as route/dark screen from several lists | Fixed | Entry points in messenger, profile detail, tasks, lessons kanban, entities, finance/debtors/leads/students boards use `showClientCard` modal/dialog. Route screens remain only as deep-link/host fallback. |
| HolliHop fields were underrepresented | Fixed | Default CRM custom fields now include expanded HolliHop-compatible field sets for students, leads, and teachers, with migration `0045` appending missing fields without overwriting owner-edited schema. |

## Medium Issues

| Issue | Status | Notes |
|---|---:|---|
| Realtime smoke script cannot self-login newly signed-up users on staging | Partially fixed operationally | Staging correctly requires email verification. Release smoke used a one-time verified smoke user and soft-deleted it. Future improvement: make smoke script support a safe seeded verified test user. |
| Staff realtime smoke with admin account was not executed live | Residual risk | Staging staff login requires OTP and no non-secret staff smoke credentials were available. Covered by backend tests and client fallback, but live staff socket smoke should be repeated with a dedicated OTP-bypass audit account. |
| Backup script emitted `.env: line 26: PRIVATE: command not found` | Residual ops issue | Deploy still completed and containers are healthy. The backup script should parse env safely instead of shell-sourcing unquoted multiline/private-key values. |
| HolliHop employee/action-level fields are not first-class card sections yet | Planned | Current settings schema supports `students`, `leads`, `teachers`. Importer docs still show future models needed for employee/actions/custom domain data. |

## Root Causes

| Area | Root cause | Fix |
|---|---|---|
| Backend | RBAC policies were too narrow for admin operational work and inconsistent across CRM/Profile/Messenger. | Policy tests and policy code updated for admin operational access, while role/user-role mutation remains privileged. |
| Backend | Realtime fan-out did not include every affected actor/entity. | CRM and Messenger services now emit broader `crm.changed` and `chat_work` events, including affected user IDs. |
| Database | No durable model for chat work/assignment history. | Added `0044_chat_work_events` migration and service inserts. |
| DTO/API | Lesson/client linkage mixed lead/student semantics. | Client-facing lesson queries include both lead and student links. |
| Frontend | Screens assumed realtime always works and did not fall back to refetch. | Added global CRM fallback invalidation and chat-specific silent polling fallback. |
| Frontend | Several widgets navigated to full routes instead of modal client card. | Unified those entry points through `showClientCard`. |
| State management | Optimistic/realtime merges could diverge from backend state. | Realtime events now trigger provider invalidation and silent REST refresh where appropriate. |

## Business Logic Questions

Answered by owner and implemented in this release:

- Admin can add payments for any client; manager can delete by request.
- Admin can create/edit groups and group composition.
- Admin and manager can see all required client-card data.
- Payments, lessons, groups, tasks, statuses, subscriptions, and chat work should be realtime.
- Realtime requires fallback/offline fallback when socket is unavailable.
- Multiple admins may work with one client; transfer flow is not required as a separate workflow.
- Clients see only "Администратор" for staff replies; internal users see who did what.
- Tasks are internal; clients only see teacher homework where implemented.
- A student may be in multiple groups.
- Multi-hour schedule selection creates one long lesson.
- Client sees lessons even while still a lead.
- Lead/student drag-and-drop changes only status; admin/manager edit the remaining fields separately.
- Fired/removed admins should not permanently block a client from being worked by others.

Remaining concrete questions before next data-model phase:

- Which HolliHop-derived fields should be visible to admin/manager by default versus system-admin-only?
- Should `chat_work_events` be surfaced as a dedicated "Work history" block or only in the unified timeline?
- Should realtime fallback polling intervals be configurable per environment?
- Should staging receive a permanent verified non-privileged smoke account and OTP-bypass staff smoke account?

## Proposed Fix Plan

Completed:

1. Expand backend policies for admin operational work without weakening role mutation.
2. Add durable chat work event history.
3. Expand realtime event entities and affected-user fan-out.
4. Add frontend realtime fallback and chat silent polling fallback.
5. Fix client lessons/payments/subscriptions visibility and invalidation.
6. Implement student-to-lead status-only reverse operation.
7. Align client navigation for phone tabs and desktop sidebar.
8. Unify client-card modal entry points.
9. Expand HolliHop-compatible custom field defaults and migration.
10. Deploy backend, run migrations, smoke staging, build Windows/Android clients, install Android build to emulator.

Next recommended hardening:

1. Add seeded staging smoke accounts so staff/client realtime smoke can run end-to-end without manual DB verification.
2. Fix staging backup env parsing for private-key/multiline values.
3. Promote HolliHop employee/action/custom-data domains into first-class CRM sections if owner wants them visible beyond custom fields.

## Test Matrix

| Role | Action | Expected result | Actual result | Status | Where verified |
|---|---|---|---|---:|---|
| Client | Connect realtime and join own chat/channel rooms | Socket connects and room ack succeeds | `room.join` returned ok in staging smoke | Pass | Backend staging |
| Client | Send administration chat message | REST message and realtime event match | `messageId` matched `eventMessageId` | Pass | Backend staging |
| Client | Publish announcement | Forbidden | 403 expected/observed | Pass | Backend staging |
| Admin | Add payment to any client | Backend allows operational staff | Policy/service tests pass | Pass | Backend tests |
| Admin | Create task for any client/entity | Backend allows operational staff | Policy/service tests pass | Pass | Backend tests |
| Admin | Create/edit group composition | Backend/frontend expose group flows | Service/widget tests pass | Pass | Backend + Flutter tests |
| Admin/Manager | Drag lead to student | Converts/status moves per b14dc4e visual instruction | Flutter DnD tests pass | Pass | Flutter tests |
| Admin/Manager | Drag student back to lead | Status-only reverse operation | API/service tests pass | Pass | Backend + Flutter tests |
| Admin | Drag select schedule cells | Creates one long lesson duration | Widget/service tests pass | Pass | Flutter tests |
| Teacher | Receive assigned lesson | Lesson fan-out and schedule refresh | Covered by service tests | Pass | Backend tests |
| Client | See lesson/payment/subscription changes | Providers invalidate via realtime/fallback | Covered by full Flutter tests | Pass | Flutter tests |
| Client/Admin/Teacher | Chat after realtime silence | Silent REST fallback refreshes messages | Unit/widget compile and smoke baseline pass | Pass | Flutter + staging |
| All staff | Open client card from list contexts | Modal/dialog, no full dark route | Code scan: entry points use `showClientCard` | Pass | Code audit |
| Staff | Live staff realtime with OTP account | End-to-end staff/client socket smoke | Not executed due missing OTP-bypass staff smoke account | Gap | Staging |
| Ops | Backup before deploy | Backup script should run cleanly | Warning from env parsing observed | Gap | Staging deploy |

## Acceptance Criteria

- Backend compiles and full test suite passes.
- Flutter analyze and full test suite pass.
- New migrations apply on staging.
- Staging API health is `ok`.
- Realtime smoke verifies Socket.IO connection, room join, message event, and client RBAC.
- Windows release build is produced.
- Android debug APK is produced and installed on Android emulator.
- Client card entry points from normal workflows open the modal client card.
- Realtime has fallback polling for CRM entities and chat messages.
- HolliHop-compatible custom field defaults are present without overwriting owner-edited settings.

## Verification Evidence

- Backend: `npm run typecheck` passed.
- Backend targeted Jest: `settings.service`, `crm.service`, `messenger.service`, `realtime-bus` passed, 208 tests.
- Backend full Jest: 43 suites, 432 tests passed.
- Backend build: `npm run build` passed.
- Flutter analyze: no issues found.
- Flutter tests: 233/233 passed.
- Staging deploy: `docker compose up -d --build`, `api` healthy.
- Migrations: `docker compose exec api node dist/db/migrate.js up` returned `Applied migrations: none` after startup applied pending migrations.
- Health: `GET https://api.phantom-net.ru/api/health` returned `{"status":"ok","service":"magic-music-crm-api"}`.
- Realtime smoke: `ok=true`, chat `36d73143-1430-4678-9c6c-8b296e7e347d`, message/event `9b9ad2a4-9b91-456b-a327-34bf07ddde2f`.
- Windows build: `build/windows/x64/runner/Release/magic_music_crm.exe`.
- Android build: `build/app/outputs/flutter-apk/app-debug.apk`.
- Android install: installed `app-debug.apk` to `emulator-5554`.
