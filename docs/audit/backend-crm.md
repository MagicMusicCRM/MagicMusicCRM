# Backend CRM — Production-Readiness Audit Inventory

Generated from: `server/src/crm/**` and `server/db/migrations/0001–0032.up.sql`

---

## 1. Overview

The CRM is a NestJS service (`CrmModule`) exposing a single REST controller (`/crm/*`) backed by raw PostgreSQL queries (no ORM). All routes require JWT authentication (`JwtAuthGuard`). Authorization is enforced by `CrmPolicy` at the method level. The schema lives entirely in the `app` PostgreSQL schema, migrated by 32 sequential `.up.sql` files. Business entities include leads, students, teachers, staff, branches, rooms, groups, lessons, payments, tasks, families, and a dedup/merge pipeline. HolliHop integration surfaces external CRM metadata (disciplines, levels, categories, lead statuses) as read-only reference data.

---

## 2. Features

### Leads

- **`GET /crm/leads`** — list leads with full-text search (name/email/phone); manager/admin only; limit 100.
- **`GET /crm/leads/board`** — Kanban board view: leads grouped by status column with per-status counts; cursor-based pagination (keyset on `created_at`, `id`); filters: statusId, assignedTo, branchId, source, discipline, level, category, requestType, goal, gender, preferredSchedule, date range, openTasks flag, hideConverted flag, quick-filter (all/processed/deferred); limited to 50 rows per load.
- **`GET /crm/leads/app-count`** — count leads with `source = 'Через приложение'`; manager/admin/teacher.
- **`GET /crm/leads/:id/card`** — full lead card: lead row + linked students, related leads (same phone/email), comments, tasks, trial lessons, merged timeline; manager/admin only.
- **`GET /crm/leads/:leadId/status-history`** — ordered history of status + ownership transitions from `lead_status_history`; manager/admin only.
- **`GET /crm/leads/:id/chat-user`** — resolve messenger user behind a lead: prefers explicit `user_crm_links`, falls back to phone-match on profiles; manager/admin only.
- **`POST /crm/leads`** — create lead; fields: statusId, firstName, lastName, phone, email, source, notes, assignedTo, customDataPatch (arbitrary JSON), branchId extracted from patch; audited as `crm.lead_created`.
- **`PATCH /crm/leads/:id`** — update lead; coalesce-patch semantics; supports `clearStatus` bool to explicitly null status; if status or assignedTo changes a `lead_status_history` row is written with reasonId, statusComment, source snapshot; audited as `crm.lead_updated`.
- **`DELETE /crm/leads/:id`** — soft-delete (sets `deleted_at`); audited as `crm.lead_deleted`.
- **`GET /crm/lead-statuses`** — list all statuses ordered by sort_order; manager/admin only.
- **`POST /crm/lead-statuses`** — create a new funnel status with name, color, sortOrder; audited.
- **`PATCH /crm/lead-statuses/order`** — bulk reorder funnel columns by providing an ordered array of status UUIDs; uses `unnest … with ordinality`; audited.
- **`DELETE /crm/lead-statuses/:id`** — hard-delete a status (no soft-delete on this table); audited.
- **`GET /crm/loss-reasons`** — list active loss/pause reasons from `lead_loss_reasons` (kind: `lost`|`paused`, color, sortOrder); manager/admin/teacher.
- **`POST /crm/loss-reasons`** — create a loss/pause reason; manager/admin only.
- **`GET /crm/lead-sources`** — list active sources from `lead_sources` (canonicalName, displayName); manager/admin/teacher.
- **Auto-create lead from chat** — internal method `autoCreateLeadFromChat(senderUserId)` called by the messenger subsystem on first non-staff chat message; uses pg advisory lock (`pg_advisory_xact_lock(hashtext('autolead:'+userId))`) to prevent race-created duplicates; stamps source as `'Через приложение'`, assigns status `'Новый'`, creates `user_crm_links` row in same transaction.
- **Save contact from chat** — `POST /crm/contacts/save-from-chat` — idempotent upsert of a chat user as either a `lead` or `student`; stamps lead with source `'Чат'` and default status `'Новый'`; creates `user_crm_links` linking user↔entity.

### Students / Clients

- **`GET /crm/students`** — list students with text search; teachers see only their own students (via lesson FK); managers/admins see all; limit 100.
- **`GET /crm/students/search`** — rich search with filters: q, status, branchId, groupId, discipline, level, category, createdAt range, linkedUser (bool), noEmail, noOpenTasks; returns extended stats (groupsCount, openTasksCount, lessonsCount, paymentsTotal, linkedUserId, isAppAccount) per student; manager/admin/teacher.
- **`POST /crm/students`** — create student; inserts `users` (role=client, is_app_account=false, synthetic email if none supplied: `student-{uuid}@local.magicmusiccrm.invalid`), `profiles`, and `students` in a single CTE; optionally links to an existing lead (enforces one-student-per-lead constraint); extracts branchId from customDataPatch; audited.
- **`GET /crm/students/:id`** — fetch single student; access: manager/admin OR teacher who has taught the student OR client whose profile matches.
- **`GET /crm/students/:id/card`** — aggregate card: student + groups + lessons + payments + tasks + comments + expectedPayments + balance + userCrmLinks + merged timeline; parallel sub-queries.
- **`PATCH /crm/students/:id`** — coalesce-patch; updates profile, user email, student.status, custom_data (merge-patch `||`), branch_id; if status changes inserts `student_status_history`; audited.
- **`POST /crm/students/:id/invite`** — sends email invite to student (template `student_invite`) via NotificationsService; guards against synthetic `.invalid` email addresses; audited with SHA-256 hash of email.
- **`GET /crm/students/:id/groups`** — active group memberships for a student.
- **`GET /crm/student-balances`** — computes balance as `sum(payments) – sum(lesson_costs)` on the fly; lesson cost = group.price_per_lesson OR student.custom_data.individualPrice/individual_price; supports `debtOnly=true` filter and `studentId` filter; manager/admin only.
- **`GET /crm/subscriptions`** — list subscriptions from `app.subscriptions`; scoped by role (manager/admin see all; client sees own); filter by studentId.
- **`GET /crm/me`** — client self-summary: own students (direct profile match) + family-linked students (parent/payer role in families) + upcoming lessons + tasks + recent payments; used by the student portal.

### Teachers

- **`GET /crm/teachers`** — list with text search; rich filters: status, branchId, discipline, level, category, appRole, authorization (app/technical/linked/unlinked), ratingFrom, ratingTo, birthdayMonth; access: manager/admin/teacher (teachers see own record); client sees their own teachers via lessons; includes branches (from groups+lessons), studentsCount, lessonsCount, rating (from `custom_data.rating`).
- **`POST /crm/teachers`** — create teacher; same CTE pattern as student (synthetic email if absent); role=teacher, is_app_account=false; audited.
- **`PATCH /crm/teachers/:id`** — coalesce-patch on profile + user + teacher rows; audited.

### Staff

- **`GET /crm/staff`** — list with text search; filters: branchId, role, status, appRole, authorization, birthdayMonth; includes branch assignments from `staff_branch_assignments`; manager/admin/teacher readable.
- **`POST /crm/staff`** — admin-only; creates user (role = dto.role, is_app_account=true, profile_completed=true) + profile + staff_member with auto-derived position; audited.
- **`PATCH /crm/staff/:id`** — admin-only; coalesce-patch across user/profile/staff_member; audited.

### Branches

- **`GET /crm/branches`** — list branches; searchable; manager/admin/teacher.
- **`POST /crm/branches`** — create branch with name, address, utcOffsetMinutes (default 180 = Moscow UTC+3); audited.
- **`PATCH /crm/branches/:id`** — update branch metadata including timezone; audited.

### Disciplines

- **`GET /crm/disciplines`** — list active global disciplines.
- **`POST /crm/disciplines`** — create a discipline (name must be unique case-insensitively).
- **`GET /crm/branches/:branchId/disciplines`** — list disciplines assigned to a branch, ordered by sort_order.
- **`POST /crm/branches/:branchId/disciplines`** — assign a discipline to a branch with optional sort_order; idempotent (ON CONFLICT updates sort_order, clears deleted_at).
- **`PATCH /crm/branches/:branchId/disciplines/order`** — reorder branch disciplines via ordered disciplineId array.

### Rooms

- **`GET /crm/rooms`** — list rooms; filterable by branchId; manager/admin/teacher.
- **`GET /crm/rooms/availability`** — per-room availability slot query: shows all lessons in a time window, computes `is_available` (no overlapping non-cancelled lesson in the requested slot), and `conflict_types` array (`room_overlap`, `teacher_overlap` if teacherId given); manager/admin/teacher.
- **`POST /crm/rooms`** — create room with branchId, name, capacity; audited.
- **`PATCH /crm/rooms/:id`** — update room; audited.
- **`DELETE /crm/rooms/:id`** — soft-delete room; audited.

### Groups

- **`GET /crm/groups`** — list groups with teacher/branch/room info; filterable by branchId, text search; manager/admin/teacher.
- **`POST /crm/groups`** — create group with teacherId, branchId, roomId, name, pricePerLesson; audited.
- **`GET /crm/groups/:id/students`** — list active (left_at IS NULL) students in a group.
- **`POST /crm/groups/:id/students`** — add student to group; ON CONFLICT clears `left_at` (re-join); audited.
- **`DELETE /crm/groups/:id/students/:studentId`** — set `left_at = now()` (soft remove from group); audited.

### Lessons / Schedule

- **`GET /crm/lessons`** — list lessons; role-scoped (manager/admin see all; teacher sees assigned; client sees own or group lessons); filters: studentId, teacherId, from, to, isTrial; returns up to 200.
- **`GET /crm/schedule/matrix`** — schedule conflict view: lessons for a time window with computed `conflict_types` per lesson (`missing_teacher`, `branch_mismatch`, `room_overlap`, `teacher_overlap`); filters: branchId, roomId, teacherId, isTrial; `groupBy` parameter (room/teacher/day); deduplicates overlap pairs in application layer (KVA-166) so the badge count is exact.
- **`GET /crm/schedule/month-summary`** — lightweight per-day lesson count + room ids for month calendar view; avoids shipping full lesson list.
- **`POST /crm/lessons`** — create lesson; requires scheduledAt + at least one of studentId, groupId, leadId; defaults: duration 60 min, status `scheduled`; audited.
- **`PATCH /crm/lessons/:id`** — update lesson; teachers may update status/notes only (not time/room/teacher); managers/admins can update all fields; on time change: deletes `lesson_reminders` markers so reminders fire for the new time; fires reschedule notifications to assigned teacher (and previously-assigned teacher on swap) via `notifyTeacherOfReschedule` (KVA-158); audited.
- **`DELETE /crm/lessons/:id`** — soft-delete lesson + delete lesson_reminders; manager/admin only; audited.
- **`GET /crm/lessons/:id/attendance`** — attendance roster: students for the lesson (individual or group), merged with `lesson_participation` rows; returns per-student status (present/absent) + passReason; teacher/manager/admin.
- **`PATCH /crm/lessons/:id/attendance`** — upsert attendance per student; validates students belong to the lesson; sets lesson status to `completed`; audited.

### Tasks

- **`GET /crm/tasks`** — list tasks with per-role scoping (manager/admin see all; teacher/client see assigned only; client also sees tasks on own student); filters: studentId, status, q, entityType, entityId, assignedTo, createdBy, branchId, priority, taskType, communicationMethod, from, to.
- **`POST /crm/tasks`** — create task on any CRM entity (entityType: student/teacher/group/lesson/lead/profile); fields: title, description, status, dueAt, assignedTo; audited.
- **`PATCH /crm/tasks/:id`** — coalesce-patch; audited.

### Comments / Timeline

- **`GET /crm/comments`** — list comments on an entity; clients/teachers restricted to `[PROGRESS]`-prefixed comments only.
- **`POST /crm/comments`** — create comment; optional `progress: true` flag prefixes body with `[PROGRESS]` for teacher progress notes; teachers may only post progress notes on their own students' records.
- **`GET /crm/timeline`** — unified per-entity timeline: union of comments, tasks, lessons, payments, and optionally audit events; returns up to 200 items sorted desc by `occurred_at`.

### Payments / Finance

- **`GET /crm/payments`** — list payments; manager/admin see all; client sees own; filters: studentId, from, to; returns page + `totalAmount` + `totalCount` over the full filtered set (not just the page).
- **`POST /crm/payments`** — record a payment: studentId, amount, currency (default RUB), paymentDate, method, externalId, notes; audited.
- **`GET /crm/expected-payments`** — list expected (future) payments for a student; access restricted to student's own profile or manager/admin.
- **`GET /crm/reports/finance`** — monthly finance report: revenue, expenses, lesson counts, attendance rate, new students per month; by-teacher revenue breakdown; by-room lesson count; manager/admin only.
- **`GET /crm/dashboard/manager`** — manager KPI dashboard: revenue, expectedPayments, debtStudents, activeStudents, newLeads, openTasks, overdueTasks, trialLessons, scheduleIssues (lessons with conflicts), roomLoadLessons, staffActivity (audit event count); filterable by branchId and date range.
- **`GET /crm/overview`** — lightweight global KPI snapshot: counts of students, teachers, branches, today's lessons, month completed lessons, open tasks, new leads, month revenue.

### Dedup / Merge

- **`GET /crm/duplicates`** — list `duplicate_candidates` with status filter (default `pending`) and optional leadId; resolves entity names/phones/emails; manager/admin only.
- **`PATCH /crm/duplicates/:id`** — decide on a duplicate candidate: decision status in (`pending`, `not_duplicate`, `attached`, `merged`, `ignored`); `attached` action links lead→student via `students.lead_id`; audited.
- **`GET /crm/merge-candidates`** — find leads with identical `phone_normalized` AND identical first_name/last_name (exact, case-insensitive); manager/admin/teacher; up to 200.
- **`POST /crm/leads/:winnerId/merge/:loserId`** — transactional merge: repoints students.lead_id, lessons.lead_id, lead_status_history.lead_id, lead_comments.lead_id, tasks.entity_id, entity_comments.entity_id, chats.lead_id; marks pending duplicate_candidates as `merged`; soft-deletes loser; writes `merge_log` with `repointed` JSON for undo; audited.
- **`POST /crm/merges/:mergeLogId/undo`** — transactional undo of a merge: reverses each repointed key via a hard-coded allow-list of SQL statements; restores loser lead; marks merge_log.undone_at; manager/admin only.

### Phone Normalization

- **`GET /crm/phone-review-queue/count`** — count unresolved rows in `phone_review_queue`; manager/admin/teacher.
- **`GET /crm/phone-review-queue`** — list unresolved queue entries (entityType, entityId, rawPhone, reason); limit up to 200.
- Phone normalization logic (`phone.util.ts`): strips non-digits, normalizes Russian numbers to `+7XXXXXXXXXX`; accepts 11-digit (starting 7 or 8) or 10-digit (starting 9); rejects others as `too_short` or `non_ru`; the same algorithm is mirrored as a SQL expression (`normalizedPhoneExpr`) used in backfill migrations and phone-match queries.

### Families / Contacts

- **`POST /crm/families`** — create a family unit with optional name and branchId; manager/admin only.
- **`POST /crm/families/:familyId/members`** — add a member (entityType: student/lead/profile, role: parent/child/partner/sibling/guardian/payer, isPrimaryContact bool); idempotent via ON CONFLICT.
- **`GET /crm/families/by-entity/:entityType/:entityId`** — look up the family and all members for any entity; resolves names from leads/students/profiles; manager/admin/teacher.
- **`DELETE /crm/family-members/:memberId`** — soft-delete a family member; manager/admin only.
- **`POST /crm/families/:familyId/primary-payer/:memberId`** — set the primary payer pointer on the family; manager/admin only.
- Client self-view (`GET /crm/me`) resolves family-linked students: if the calling user is a `parent` or `payer` member in any family, their children (student members) are included in the result.

### Contacts / Chat Integration

- **`GET /crm/contacts/by-user/:userId`** — resolve CRM entity (studentId + leadId) for a given user; prefers explicit `user_crm_links` then profile ownership; manager/admin only.

### HolliHop Integration (read-only metadata proxy)

- **`GET /crm/hollihop/disciplines`** — external disciplines list.
- **`GET /crm/hollihop/levels`** — external levels list.
- **`GET /crm/hollihop/categories`** — external categories list.
- **`GET /crm/hollihop/lead-statuses`** — external lead statuses list.
- All four require manager/admin role; delegated to `HolliHopMetadataService`.

### Activity Log

- **`GET /crm/activity`** — audit event log filtered by: q (full-text across action/metadata/actor name), actorUserId, entityType, entityId, branchId (from metadata or staff assignments), role (app or staff), historyType, from, to; returns actor enrichment (role, position, branches); manager/admin only.

---

## 3. Per-Role Behavior / Permissions

Role hierarchy (enum `app.user_role`): `client` < `teacher` < `manager` < `admin` < `system_admin`.

| Operation | client | teacher | manager | admin | system_admin |
|---|---|---|---|---|---|
| List students | no | own only (via lessons) | all | all | all |
| Read own student | yes (self) | yes (own students) | yes | yes | yes |
| Write CRM (create/update leads, students, groups, lessons, rooms, etc.) | no | no | yes | yes | yes |
| Create/update staff | no | no | no | yes | yes |
| Delete lesson | no | no | yes | yes | yes |
| Update lesson status/notes | no | yes (own lessons only) | yes | yes | yes |
| Read branches/rooms/groups/staff/disciplines/sources | no | yes | yes | yes | yes |
| Read own payments | yes | no | yes | yes | yes |
| View all payments | no | no | yes | yes | yes |
| Manager dashboard / finance report | no | no | yes | yes | yes |
| Dedup / merge / phone queue | no | teacher can read queue | yes | yes | yes |
| Post progress comment on student | no | yes (own students) | yes | yes | yes |
| Post any comment | no | no | yes | yes | yes |
| Client self-summary (`/crm/me`) | yes | — | — | — | — |

`isManagerOrAdminRole` covers `manager`, `admin`, `system_admin`.
`isAdminRole` covers `admin`, `system_admin` only (used for staff create/update).

---

## 4. Data / Schema Touched

### Core Identity (migration 0001)
- **`app.users`** — id, email (unique case-insensitive when active), password_hash, full_name, phone, role (enum: client/teacher/manager/admin/system_admin), email_verified_at, profile_completed, is_app_account (0016), phone_verified_at (0016), created_at, updated_at, deleted_at
- **`app.audit_events`** — id, actor_user_id, action, entity_type, entity_id, metadata (jsonb), created_at
- **`app.email_verification_tokens`**, **`app.otp_challenges`**, **`app.password_reset_tokens`**, **`app.oauth_states`**, **`app.user_identities`**, **`app.refresh_sessions`** — auth plumbing

### Profile & Core CRM (migration 0002)
- **`app.profiles`** — id, user_id (unique FK), first_name, last_name, phone, dob, avatar_file_id, email_otp_2fa_enabled, custom_data (jsonb), phone_normalized (0025)
- **`app.branches`** — id, name, address, utc_offset_minutes (0024, default 180), created_at, updated_at, deleted_at
- **`app.rooms`** — id, branch_id (FK → branches), name, capacity, created_at, updated_at, deleted_at
- **`app.lead_statuses`** — id, name (unique), sort_order, color (0010), is_terminal (0026), requires_reason (0026), created_at
- **`app.leads`** — id, status_id (FK → lead_statuses, ON DELETE SET NULL), first_name, last_name, phone, phone_normalized (0025), email, source, notes, assigned_to (FK → users), custom_data (0010, jsonb), branch_id (0027, FK → branches), created_by, created_at, updated_at, deleted_at
- **`app.students`** — id, profile_id (FK → profiles), lead_id (FK → leads), status (text, default 'active'), custom_data (jsonb), branch_id (0027, FK → branches), created_at, updated_at, deleted_at
- **`app.teachers`** — id, profile_id (FK → profiles), status (text), specialization (text), custom_data (jsonb), created_at, updated_at, deleted_at
- **`app.groups`** — id, teacher_id (FK → teachers), branch_id (FK → branches), room_id (FK → rooms), name, price_per_lesson (numeric 12,2), created_at, updated_at, deleted_at
- **`app.group_students`** — id, group_id, student_id, joined_at, left_at (null = active); unique (group_id, student_id)
- **`app.lessons`** — id, student_id, group_id, lead_id (0010), teacher_id, branch_id, room_id, scheduled_at, duration_minutes (default 60), status (default 'scheduled'), is_trial (bool), notes, created_by, created_at, updated_at, deleted_at; CHECK: at least one of student_id/group_id/lead_id not null
- **`app.lesson_participation`** — id, lesson_id, student_id, status (default 'scheduled'), pass_reason (0009); unique (lesson_id, student_id)
- **`app.tasks`** — id, entity_type (crm_entity_type enum), entity_id, title, description, status (default 'open'), due_at, assigned_to, created_by, branch_id (0027), created_at, updated_at, deleted_at
- **`app.payments`** — id, student_id, amount (numeric 12,2), currency (default 'RUB'), payment_date, method, external_id, notes, created_by, branch_id (0027), created_at, deleted_at
- **`app.expected_payments`** — id, student_id, amount, due_date, status (default 'pending'), description, created_at, updated_at
- **`app.subscriptions`** — id, student_id, lessons_total, lessons_used, starts_at, expires_at, status (default 'active'), created_at, updated_at
- **`app.student_balances`** — student_id (PK), balance (numeric), updated_at (materialized cache; but CRM service recomputes on the fly)
- **`app.entity_comments`** — id, entity_type (crm_entity_type enum), entity_id, author_id, body, created_at, deleted_at
- **`app.profile_notes`**, **`app.lead_comments`** — legacy comment tables (lead_comments still referenced in merge undo)

### Expenses (migration 0007)
- **`app.expenses`** — id, amount, category, description, branch_id (0027), created_at, updated_at, deleted_at

### Lead Management extensions (migration 0010)
- `app.lead_statuses.color` added
- `app.leads.custom_data` added
- `app.lessons.lead_id` FK added; constraint changed from student_or_group to student_or_group_or_lead

### Auth Improvements (migration 0011)
- `app.otp_challenges` — rate-limiting fields
- `app.refresh_sessions` — revocation fields

### App Accounts & CRM Links (migration 0016)
- **`app.user_crm_links`** — id, user_id, entity_type (student/lead/teacher/staff — expanded in 0017), entity_id, matched_phone, link_source (auto_phone/manual_phone/auto_email/manual_email/import), confirmed_at, created_by, created_at, deleted_at; unique per (user_id, entity_type, entity_id) when active; unique per (entity_type, entity_id) when active

### Staff (migration 0017)
- **`app.staff_members`** — id, profile_id (unique when active), role, position, status, custom_data (jsonb), created_at, updated_at, deleted_at
- **`app.staff_branch_assignments`** — id, staff_member_id, branch_id; unique (staff_member_id, branch_id)
- `app.user_role` enum extended with `system_admin`
- `app.crm_entity_type` enum extended with `staff`

### Import Audit (migration 0019)
- **`app.import_batches`** — id, source, mode (dry_run/apply), status (running/completed/failed), started_at, finished_at, counts (jsonb), warnings, report
- **`app.import_source_records`** — id, import_batch_id, source, external_id, target_table, target_id, source_checksum, raw (jsonb), field_loss
- **`app.duplicate_candidates`** — id, import_batch_id, entity_type_a/b, entity_id_a/b, match_type (phone/email/full_name/lead_student_phone/lead_student_email), match_value, confidence (numeric 5,4), source, status (pending/not_duplicate/attached/merged/ignored), decided_at, decided_by, decision_notes, created_at, updated_at, deleted_at

### Lesson Reminders (migration 0022)
- **`app.lesson_reminders`** — tracks which reminders have fired (keyed by lesson_id + kind); CRM service deletes these on reschedule or lesson delete

### Branch Timezone (migration 0024)
- `app.branches.utc_offset_minutes` added (default 180 = Moscow)

### Phone Normalization (migration 0025)
- `app.leads.phone_normalized` (text, indexed)
- `app.profiles.phone_normalized` (text, indexed)
- **`app.phone_review_queue`** — id, entity_type (lead/profile), entity_id, raw_phone, reason (empty/too_short/non_ru), created_at, resolved_at, resolved_by; unique per (entity_type, entity_id)

### CRM Dictionaries (migration 0026)
- **`app.lead_loss_reasons`** — id, name, kind (lost/paused), sort_order, is_active, color, created_at, updated_at, deleted_at; seeded with 11 reasons
- **`app.lead_sources`** — id, canonical_name (unique), display_name, is_active, created_at, deleted_at; seeded with 11 sources
- **`app.disciplines`** — id, name (unique case-insensitive), is_active, created_at, updated_at, deleted_at
- **`app.branch_disciplines`** — id, branch_id, discipline_id, sort_order, created_at, deleted_at; unique (branch_id, discipline_id)
- **`app.student_disciplines`** — id, student_id, discipline_id, is_primary, created_at, deleted_at; unique (student_id, discipline_id); one primary per student enforced by partial unique index

### Unified Branch FK (migration 0027)
- `branch_id` FK column added to: `leads`, `students`, `payments`, `expenses`, `tasks`, `chats`
- `lead_id` and `student_id` FK columns added to `app.chats`

### Status History (migration 0028)
- **`app.lead_status_history`** — id, lead_id, old_status_id, new_status_id, old_owner_id, new_owner_id, changed_by, changed_at, reason_id (FK → lead_loss_reasons), comment, branch_id, source_snapshot
- **`app.student_status_history`** — id, student_id, status, branch_id, changed_at

### Families (migration 0029)
- **`app.families`** — id, name, branch_id, primary_payer_member_id (FK → family_members, deferred), created_at, updated_at, deleted_at
- **`app.family_members`** — id, family_id, entity_type (student/lead/profile), entity_id, role (parent/child/partner/sibling/guardian/payer), is_primary_contact, created_at, deleted_at; unique (family_id, entity_type, entity_id)
- **`app.contacts`** — id, entity_type (student/lead/profile), entity_id, phone_normalized, name, role, created_at (no soft-delete)

### Merge Log (migration 0030)
- **`app.merge_log`** — id, entity_type (lead/student), loser_id, winner_id, repointed (jsonb — map of table.column → [id array]), merged_by, merged_at, undone_at, undone_by

### Analytics (migration 0031)
- **`app.analytics_refresh_runs`** — id, kind, status (running/completed/failed), claimed_at, ran_at, finished_at, error
- **`app.mv_finance_monthly`** — materialized view: month_start, lessons, completed_lessons, revenue, expenses, new_students
- **`app.mv_teacher_performance`** — materialized view: teacher_id, teacher_name, completed_lessons, revenue
- **`app.mv_room_load`** — materialized view: room_id, room_name, lessons

### Lead Board Cleanup (migration 0032)
- NULL-status leads migrated to `'Новый'` status
- `'Успешный'` and `'Отказ'` statuses marked `is_terminal = true`
- `'Отказ'` marked `requires_reason = true`, colored `#E53935`
- Empty legacy statuses (`'Контакт'`, `'Переговоры'`, `'Договор'`) deleted if no leads reference them
- Sort orders densely renumbered

### Key Indexes
- `lessons`: scheduled_at, student_id+scheduled_at, teacher_id+scheduled_at, lead_id+scheduled_at, branch_id, room_id (migration 0012, 0021)
- `leads`: created_at desc, phone_normalized, branch_id, status_id (implied by FK), status_id+created_at (0012)
- `students`: profile_id, branch_id
- `group_students`: student_id where left_at IS NULL
- `tasks`: assigned_to+status+due_at
- `payments`: student_id+payment_date desc
- `duplicate_candidates`: status+created_at, composite unique on (entity pairs + match)
- `phone_review_queue`: created_at where resolved_at IS NULL
- `user_crm_links`: user+entity_type, entity unique

---

## 5. Notable Business Rules / Edge Cases

1. **Branch resolution is dual-path**: `branchIdExpr()` coalesces `entity.branch_id` (real FK, added in 0027) with `entity.custom_data->>'branchId'` / `custom_data->>'branch_id'` (legacy JSON). The service dual-writes both on every create/update via `extractBranchId()`. Queries that filter by branch must use this expression or will miss legacy data.

2. **Lesson constraint relaxed**: The original `student_or_group_check` (0002) was replaced with `student_or_group_or_lead_check` (0010) to allow trial lessons directly on a lead before conversion.

3. **Student creation creates a synthetic user**: Every student gets a `users` + `profiles` row even if no real account exists. Email is synthetic (`student-{uuid}@local.magicmusiccrm.invalid`) unless a real email is supplied. The `is_app_account = false` flag marks these as non-login records. The `inviteStudent` flow checks `isDeliverableEmail()` to prevent sending to synthetic addresses.

4. **Lead-to-student conversion guard**: `createStudent` checks that no student already exists with the same `lead_id` to prevent duplicate conversions (`ConflictException`).

5. **Phone normalization**: Only Russian numbers are supported. The normalizer produces `+7XXXXXXXXXX` from 10-digit (`9xxxxxxxxx`) or 11-digit (`7/8xxxxxxxxxx`) inputs. All others go to `phone_review_queue`. The SQL expression (`normalizedPhoneExpr`) and TypeScript function (`normalizePhoneRu`) must stay in lockstep (explicitly documented in code).

6. **Schedule conflict detection**: Conflict types detected per lesson: `missing_teacher`, `branch_mismatch` (lesson.branch_id ≠ room.branch_id), `room_overlap` (two different groups/students sharing the same room simultaneously), `teacher_overlap` (same teacher double-booked). Group lessons sharing a room with the same group are explicitly excluded from overlap (a group class has one room row per participant). Conflicts are deduplicated to one entry per pair in the application layer (KVA-166) to avoid N×count badge inflation.

7. **Lead board cursor pagination**: Uses keyset pagination (`(created_at, id) < (cursor_created_at, cursor_id)`) rather than OFFSET; cursor is encoded as `{iso8601}|{uuid}` and validated before use. The `rn <= limit` row-number approach means up to `limit` rows per status column per page, not per query.

8. **Lead merge undo**: The `repointed` JSON in `merge_log` stores which row IDs moved for each table.column key. The undo procedure uses a hard-coded allow-list (`UNDO_REPOINT`) — table names are never derived from stored data, preventing SQL injection. Only leads are undoable (not students).

9. **Dedup decision `attached`**: When a `duplicate_candidates` pair is marked `attached`, the service links the student's `lead_id` to the lead (if it was null or already pointed there). Conflicts where the student already has a different lead produce a `ConflictException`.

10. **Status history triggers**: Both `lead_status_history` and `student_status_history` are written by the application (not DB triggers) inside the update methods. For leads, the history row is written if `status_id` OR `assigned_to` changes. For students, only on `status` change.

11. **`lead_status_history` includes `source_snapshot`**: Captures the lead's `source` string at the moment of the transition, for funnel-attribution analytics.

12. **Progressive comment filter**: Teachers and clients receive only comments whose body starts with `[PROGRESS]`. Staff (manager/admin) see all comments. The prefix is applied automatically when creating a progress comment.

13. **Race protection for auto-lead creation**: `autoCreateLeadFromChat` holds a per-user pg advisory lock (`pg_advisory_xact_lock`) for the duration of the transaction, preventing two concurrent first-chat-messages from creating two leads for the same user.

14. **Families extend client self-view**: `getMySummary` (GET /crm/me) additionally pulls in students linked through the Families model (where the calling user's profile is a `parent` or `payer` family member), not just directly owned students.

15. **`hideConverted` filter on lead board**: Uses `phone_normalized` + first_name + last_name exact match to detect converted students in addition to the explicit `lead_id` FK, catching cases where students were created without going through the lead.

16. **Soft-delete pattern**: All primary CRM entities use `deleted_at` soft-deletes. `lead_statuses` uses hard-delete (no `deleted_at` column). The merge operation soft-deletes the loser lead; `on delete set null` on FKs preserves referential integrity for all child rows.

17. **Materialized views are application-refreshed**: `mv_finance_monthly`, `mv_teacher_performance`, `mv_room_load` are owned by the `magiccrm_app` database role and refreshed by an application-level analytics worker (tracked in `analytics_refresh_runs`). The CRM service does NOT use these views — it queries base tables directly. The views exist for external analytics consumers.

18. **`custom_data` JSONB on most entities**: Students, teachers, staff, leads, profiles all carry open `custom_data` JSONB used for HolliHop-imported fields (discipline, level, category, individualPrice, rating, birthday, hollihopId, etc.) and app-specific metadata. Updates use `||` merge-patch semantics (never full replace). The `sanitizeJsonObject` helper strips `undefined` values.

19. **`duplicate_candidates` match types**: `phone`, `email`, `full_name`, `lead_student_phone`, `lead_student_email`. The CRM service handles `attached` decisions for `lead_student_*` pairs. Auto-detection is done outside the CRM service (import pipeline).

20. **No pagination offsets in lesson/schedule queries**: All lesson lists use `LIMIT` only (no cursor or offset), meaning the client must supply explicit `from`/`to` bounds to scope results; a wide open query is truncated silently.
