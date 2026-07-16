# Architecture-audit follow-up — 2026-07-16

Second remediation pass over the findings in `architecture-map.html`, after the
section-9 bug-fix commits (`e3af2756`/`c3f54fb1`, merged via PR #9). This pass
worked the sections 4/5/6 *architectural* findings high→low. Branch:
`claude/busy-cannon-e3ff86`, off `main` @ `42a9086f`.

Verification gates used throughout: backend `tsc --noEmit` + `jest` (now **68
suites / 443 tests**, +2 from the new authorization guard); frontend `flutter
analyze` (clean apart from 3 pre-existing `convert_lead_dialog_test` warnings)
and `flutter test` (**239 pass / 3 pre-existing failures** — the `widget_test`
suite that still asserts the old `api.phantom-net.ru` URL; unchanged from
baseline).

---

## Done this pass

### Backend
- **B1 — Shared CRM mappers** (`server/src/crm/crm-mappers.ts`). `LessonRow`/
  `toLessonDto`, `TaskRow`/`toTaskDto`, `TimelineRow`/`toTimelineDto`,
  `PaymentRow`/`toPaymentDto`, the presentable-email helpers and the Moscow
  lesson-time formatter were byte-identical across 2–3 services each; now a
  single source, imported by crm/leads/schedule/finance/tasks/timeline.
- **B2 — CRM↔messenger data boundary.** The ~55-line chat-work timeline query
  (reads `app.chats` / `app.chat_work_events`) was inlined in three CRM services.
  Introduced a messenger-owned `ChatWorkTimelineService` + `ChatWorkTimelineModule`
  (depends only on `DatabaseModule`, so `CrmModule` imports it with **no module
  cycle / no `forwardRef`** — the audit's celebrated property is preserved). CRM
  and leads inject it; `timeline.service` shares one exported SQL fragment.
- **B3 — De-duplicated crm.service reads.** `getMySummary`'s self-view
  lessons/tasks/payments SQL moved into the owning services
  (`ScheduleService.listUpcomingLessonsForStudents`,
  `TasksService.listOpenTasksForStudents`,
  `FinanceService.listRecentPaymentsForStudents`). Authorization semantics
  unchanged (these are deliberately un-gated self-view reads; ownership is
  established upstream).
- **B4 — Authorization systematised.** Confirmed `schedule.listLessons` is
  authorized by its documented row-level SQL predicate (unknown roles see
  nothing). Added a **structural guard test**
  (`crm-authorization.guard.spec.ts`): every `actor`-taking CRM service method
  must carry a recognized auth marker (`policy.assert*`, role-helper throw,
  ownership check, row-level SQL, or delegation) **or** be on an explicit
  allowlist with a reason. 128 methods scanned; the only exemptions are the two
  inbound-capture `lead-intake` flows. Includes a stale-allowlist check.
- **B5 — DTO validation on raw-query endpoints.** `listStudentLedger`,
  `listPhoneReviewQueue`, `listMergeCandidates`, `listScheduleSeries`,
  `deleteScheduleSeries` now use validated/whitelisted query DTOs instead of raw
  `@Query('x')` + manual `Number()`.
- **B6 — Role SQL predicate helper.** The `('manager','director','admin',
  'system_admin')` membership test was hand-copied into 8 queries. Single-sourced
  as `MANAGER_ADMIN_ROLES` + `managerAdminRolesSql()`; emits byte-identical SQL.
- **B7 (part) — Legacy `lead_comments`** removed from the merge re-point + undo
  map (app-dead table; comments live in `entity_comments`).
- **B8 — Dead `CrmService` export** removed from `CrmModule` (only its own
  controllers inject it; other modules use the exported `DashboardService` /
  `CrmPolicy` / `LEAD_INTAKE_PORT` contract).

### Frontend
- **F1 — `finance_widget` export** no longer builds its own authorized `Dio`.
  Added `MagicApiClient.downloadBytes` + `MagicCrmService.exportFinanceMonthly`;
  the widget just persists bytes. Errors surface the localized
  `MagicApiException.message`.
- **UX1** — already resolved in §9 (`student_schedule_section` has a `hasError`
  branch with retry).
- **UX2 — Server search in pickers.** `group_detail_dialog` student picker now
  hits `searchStudents(q:)` server-side (student #101+ reachable); the tasks
  "Ответственный" and `create_group_dialog` teacher dropdowns became searchable
  `SearchableSelect` pickers.
- **F2 — Silent read-catches** in `client_card_data` now `debugPrint` (kept
  section isolation). Raw-`$e` leaks are largely already prevented by
  `MagicApiException.toString()` returning the localized message.
- **F3 (slice)** — extracted the duplicated dashboard `_LegendItem` into a shared
  `DashboardLegendItem`, used by both finance and management dashboards.
- **F4 (slice)** — removed the provably-dead `teacher_profile_first_name`/
  `_last_name` duplicate keys (single reader, always equal to `teacher_*`).
- **F5** — deleted the unreachable `broadcast_dialog.dart` (129 dead lines); made
  the fixed-width `create_group_dialog` (`width: 420`) responsive (`maxWidth`).
- **M2 (slice)** — `Payment` converted from a map-wrapper to a **real parsed
  `fromMap` DTO** (typed `final` fields, same getter API, behaviour-preserving),
  with a unit test. It carries the migration recipe for the remaining domains.

---

## Deferred — requires an owner decision or data we don't have here

These are **not** oversights; each is blocked on production data, a product
decision, or app-level QA. Listed so the next engineer starts from the right
place.

### Needs production EXPLAIN (section-9 tail — perf, deliberately not applied)
- **Messenger inbox folder classification** does a correlated regexp scan of
  `app.students` per (chat × participant), ignoring the indexed
  `phone_normalized` column; `chat_members` join lacks a `user_id` filter in the
  `ON`. Superlinear on ~2000 clients. `messenger.service.ts:138–180`.
- **Leads board** computes three correlated count sub-queries for **all** leads
  before the `rn ≤ limit` slice — push the slice into an inner CTE.
  `leads.service.ts:182–236`.
- **`listStudents`/`searchStudents`** `lessons × teachers` join for
  `array_agg(teacher_user_ids)` multiplies rows — replace with `LEFT JOIN
  LATERAL`. `crm.service.ts:200–303`. (Also blocks a real UX3 pagination — see
  below.)

Each needs before/after `EXPLAIN (ANALYZE)` on prod-scale data before touching.

### Needs a product/client decision
- **Report time-zone unification.** The finance report and manager dashboard
  bucket months by **UTC**, while `getOverview` uses **Europe/Moscow** — a 01:00
  MSK payment on the 1st lands in different months on adjacent screens. Unifying
  on `date_trunc(... at time zone 'Europe/Moscow')` **changes reported numbers**,
  so it must be agreed with the client. `dashboard.service.ts:319–358, 618–624`.

### Needs a production migration check
- **Branch double-write (B7 remainder).** `branchIdExpr` still coalesces the real
  `branch_id` column with the legacy `custom_data->>'branchId'` JSON. Removing the
  JSON fallback is only safe once migration `0027_unified_branch_id` is confirmed
  to have back-filled `branch_id` for **all** rows on prod. Until then the fallback
  stays. `branch-scope.ts`.

### Safe, but scoped out of this pass (do any time)
- **LIKE escaping** of `%`/`_` in 5 search filters (not injection — parameterised —
  but `"50%"` matches everything). Small escape helper. Grouped under the §9 tail
  the owner asked to skip, but it needs no prod/client input.
  `leads.service.ts:480,697 · crm.service.ts:218 · dashboard.service.ts:499 ·
  subscriptions.service.ts:141`.
- **`room.join ×3 / presence.update ×2`** on chat selection — collapse the three
  channel helpers into one join. `messenger_screen_messaging.dart:338–353`.

### Large sweeps — best done incrementally with the pattern now in place
- **UX3 — real "load more" pagination.** `searchStudents`/`listStudents` expose
  only `limit`, no offset/keyset cursor. A genuine "load more" (students board's
  500-cap, manage-entities lists) needs server-side keyset pagination **on the
  perf-flagged `listStudents` query above** — i.e. it depends on the EXPLAIN work.
  This pass made only the safe consistency change (manage-entities lessons cap
  50→100) and surfaced the constraint. The leads board's cursor pagination
  (`kanban_column`) is the reference to copy once the server supports it.
- **F2 — one notification system.** `MagicToast` (19 files) vs raw `SnackBar`
  (52 files). A mechanical but broad sweep; low per-site risk-adjusted value, and
  `MagicApiException.toString()` already prevents raw-error leakage, so it's
  cosmetic. Standardise on `MagicToast` opportunistically.
- **F4 — remaining duplicate mapper keys.** `body`/`content` (comment),
  `expires_at`/`valid_until` (subscription), and the re-nested
  `groups`/`rooms`/`branches` on a lesson each still have **live readers**
  (`Comment.content`, `subscription_status_card`, tests), so a blind removal would
  break silently. These collapse naturally as each domain is migrated to a real
  DTO (M2) — do them there, not as standalone key deletions.
- **F5 residuals** — replace stringly-typed roles with an `enum`; give the
  single-flight refresh per-`MAGIC_PROFILE` isolation; de-duplicate the inline
  forward-message dialog. Each is a focused follow-up.

---

## M1 — client-card / god-widget decomposition roadmap

The three god-widgets (`_ClientCardState` ~6 905 lines / ~18 part-files,
`_MessengerScreenState` ~3 946 / 9, `_ScheduleWidgetState` ~4 380 / 16) are one
`State` object whose methods are scattered across `extension` fragments that can
all mutate every field. This was **not** touched by code in this pass: it is the
repo's highest-risk surface and a correct extraction must be validated with
app-level visual QA, which the current environment cannot provide. A blind
extraction risks regressions worse than the debt.

**The target pattern already exists in-repo** — `student_schedule_section.dart`
is a self-contained child `StatefulWidget` that owns its state, fetches its own
data (`FutureBuilder` + `hasError` + retry) and is embedded by the card. Extract
further tabs the same way:

1. Pick a tab whose fields/methods are the most self-contained (grep the part
   files for the fields only that tab reads/writes).
2. Create `‹tab›_section.dart` — a `ConsumerStatefulWidget` owning those fields,
   its own fetch, and its own loading/error/empty states.
3. Pass **inputs down** (ids, the parent's read-only data) and **events up**
   (callbacks) — no shared mutable state.
4. Delete the moved fields/methods from `_ClientCardState`.
5. QA the tab in the running app (open/edit/save/error paths) before the next.

Do one tab per PR. Each extraction shrinks `_ClientCardState` and removes a slice
of the "any fragment mutates any field" coupling.

## M2 — Map→DTO migration roadmap

`Payment` (this pass) is the reference: a real immutable DTO with a `fromMap`
that parses once into `final` fields, same getter surface, unit-tested. Next
domains, in rough ascending reader-footprint: `Lead`, `Subscription`, `Comment`,
`Lesson`. For each: lift wrapper getters to `final` fields parsed in `fromMap`,
keep derived getters, and collapse that domain's duplicate mapper keys (the F4
items) into one field. There are ~598 `Map<String,dynamic>` uses across 95 files;
this is the only path that removes them and the runtime key-typo class of bug.
