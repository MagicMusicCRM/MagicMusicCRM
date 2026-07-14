# De-God-ing Roadmap — MagicMusicCRM

_Created 2026-07-14. Behavior-preserving refactor of the ~9 God files into ~100–115
focused units. Sequenced by dependency and risk (what unblocks what), NOT by calendar.
Each step is independently shippable: one commit, green tests + typecheck, and a manual
check where risk warrants it._

## Context (measured, not estimated)

| God file | Size | Decomposes into |
|---|---|---|
| `server/src/crm/crm.service.ts` | 9,960 LOC / 182 methods | 20 domain services + ~10–15 repositories + ~15 mappers + ~5 shared helpers |
| `server/src/crm/crm.controller.ts` | 122 routes | ~14 sub-controllers |
| `server/src/messenger/messenger.service.ts` | 1,974 / ~50 methods | 4 services (Chat / Message / Channel / ReadReceipt) |
| `server/src/profile/profile.service.ts` | 1,466 / ~31 methods | 2 services + 4 linker strategies |
| `lib/.../client_card/client_card.dart` | 5,889 | shell + 10 tab widgets + controller + shared field widgets (~14) |
| `lib/.../messenger/.../messenger_screen.dart` | 3,853 | controller + ChatListPane + ChatView + MessageComposer + CrmPanel (~7) |
| `lib/.../admin/widgets/schedule_widget.dart` | 3,471 | controller + viewProvider + 3 view widgets + LessonDetailsSheet + filters (~7) |
| `lib/.../manager/widgets/leads_widget.dart` | 2,601 | LeadCard split + shared filter panel + controller move (~5) |

DI hygiene is already correct (no manual `new XxxService()`). The foundation is clean —
this is decomposition, not a rewrite.

---

## Track B — Backend

**B0 — mechanics baseline** ✅ **DONE**
`HomeworkService` extracted (commit `9c5521dd`). Pattern for every step below: new
`@Injectable`, re-inject shared collaborators, move routes (paths unchanged), move tests.

**B1 — leaf domains (low risk, builds confidence)** ✅ **DONE**
Extracted one at a time: `ReferenceDataService` (`6b630ba7`) → `SubscriptionsService`
(`485bd782`) → `RoomsService` (`423d0f67`) → `BranchesService` (`231f03f3`) →
`GroupsService` (`5f298859`) → `PayrollService` (`0a0eea37`). CrmService 9726 → 7956 LOC.
Reality vs. plan: several "leaves" did call shared helpers — handled per ponytail by
copying small helpers (`affectedUserIdsForStudent`, `requiredTrim`, `utcDayStart`,
`trimOptional`, `toLeadStatusDto`) with `ponytail:` notes pointing at the B4/B5
consolidation (AudienceResolver / shared mappers). Two student-coupled group reads
(`listStudentGroups`, `listGroupStudents`) stayed in CrmService to avoid dragging the
core student mapper out early. Subscriptions/Groups needed one back-injection each into
CrmService for `getStudentCard`. The dead `HolliHopMetadataService` dep on CrmService was
dropped when ReferenceData took its only users. Gate held every step: `tsc` + full
`src/crm` jest green (13 suites, 193 tests), routes unchanged.

**B2 — break module coupling (small step, big lever)** ✅ **DONE** (`117aa269`)
`messenger → LeadIntakePort` (`src/common/lead-intake.port.ts`): messenger injects a
one-method `LEAD_INTAKE_PORT` token instead of the whole `CrmService`; CrmService
`implements LeadIntakePort`, CrmModule binds `useExisting: CrmService`. Port lives in
`common/` so the core doesn't import a feature module. MessengerModule still imports
CrmModule for the token — the win is file-level type decoupling, which unblocks splitting
messenger.service (B7) and crm.service (B5) independently. Full server suite green.

**B3 — repository layer (prerequisite for the core)** — 🔶 SEEDED
Deferred per ponytail (introduce infra when the 2nd/3rd caller forces it, not
speculatively) and seeded on demand: `student-read.ts` (`4ce09427`) exports
`StudentRow` + `findStudent(db, id)` as the shared student read (the
`StudentRepository` seed) — a plain hand-written-SQL free function, no ORM. More
per-aggregate reads (Lead/Profile/Link) get seeded the same way when the core
extraction (B5) forces them.

**B4 — mid tier** — 🔶 FOUNDATION DONE
Shared helpers lifted first (they unblock every mid-tier domain):
- `BranchScope` (`branch-scope.ts`, `258aadf4`) — pure `branchIdExpr`/`extractBranchId`
  functions; also killed the 5× inline copy in `analytics.service.ts`.
- `AudienceResolver` (`audience.ts`, `e95d5497`) — `audienceForStudent/Group/Lesson`
  free functions; removed the 3 `affectedUserIdsForStudent` copies the B1 leaves left.
Remaining domain services to extract (foundation ready): `FinanceService` (mapped:
10 methods + 4 mappers; toPaymentDto/PaymentRow shared with getMySummary → copy,
other 3 mappers + rows move; back-inject into CrmService for getStudentCard's
payments/expected/balances), `AttendanceService`, `ScheduleService`, `TasksService`,
`TimelineCommentsService`, `TeachersService`, `StaffService`. Still TODO:
`CrmEntityResolver` map replacing the `if/else`-on-entity-type dispatch (OCP).

**B5 — tangled core (last, highest risk)**
`StudentsService`, `LeadsService`, `ClientLinkingService`, `MergeService`,
`DashboardReportsService`. Only after B3/B4 — otherwise circular deps. Merge/undo and
identity-glue live here and cross all of them.

**B6 — controllers**
Split `crm.controller.ts` (122 routes) into ~14 sub-controllers under the shared `crm`
prefix. Can be done incrementally: carve each sub-controller out alongside its service in
B1–B5 (pure route move, low risk).

**B7 — parallel monsters**
`messenger.service` → Chat/Message/Channel/ReadReceipt; `profile.service` → Profile +
ProfileCrmLink + 4 linker strategies (fixes the 3×-duplicated OCP dispatch).

---

## Track F — Frontend (runs in parallel)

**F0 — typed models (cross-cutting, start early)**
Replace `Map<String,dynamic>` with typed models (246 `['key']` accesses in messenger alone).
This is the ROOT fix — without it widgets shrink but stay stringly-typed. Do it domain by
domain, synced with backend DTOs.

**F1 — `MessengerController` (first)**
Lift the 13 realtime handlers + 31 session fields + 3 timers into a Notifier. Removes ~60 of
86 `setState`; render methods (385/298 lines) untouched. Highest state-smell relief at low
risk (handlers are pure payload→state). Pattern already exists (`chat_providers.dart`).

**F2 — `schedule_widget`**
Controller + `scheduleViewProvider` + 3 view widgets + `LessonDetailsSheet`. Clean boundary
over the fetched matrix; no dual-mode fork.

**F3 — `client_card` (heaviest widget)**
Extract `ClientCardController` first (all async logic + 16 `ref.read(service)` sites), then
peel tabs one at a time behind the existing `TabBarView`. Dual lead/student mode + 15 live
form controllers = biggest blast radius, so after messenger + schedule prove the mechanics.

**F4 — `leads_widget` (finish)**
Board state already in `leadBoardProvider`. Remaining: split `_LeadCard` (418-line build),
one shared filter panel (kill the drawer/inline duplication), move `_scheduleTrial` /
`createLesson` into the existing controller.

**F+B cross-cut — de-duplication**
`createLesson` is duplicated across 3 widgets; "schedule trial" across 2. After the
controllers exist, fold into one `bookLesson()` / `scheduleTrialLesson()`.

---

## Guardrails — do not slide into over-engineering

- **Split only along a real seam** (like homework), never "just in case". No second reason to
  change → leave it.
- **No big-bang.** Each phase is a commit on green tests; the system stays shippable after any step.
- **Definition of done (project-wide, NOT textbook DDD):** no file > ~800 lines, one class =
  one responsibility, each with its own spec. `HomeworkService` is the reference level.
- **Stop signal:** if an extraction needs a single-implementation interface "for cleanliness",
  stop — that is the over-engineering we just cleaned out.
- **Order is fixed:** leaves → infrastructure (repo) → core. Starting with Students/Leads
  guarantees circular deps and pain.

## Realistic verdict on "clean code"

Achievable in the sense of _"no monsters, every module understandable and tested"_ — ~100 units,
incremental. NOT worth chasing academic Clean Architecture / ports-and-adapters everywhere —
that replaces one mess with another. The raw-SQL-no-ORM design is a deliberate, valid choice;
"clean repository" here means thin repos, not a DDD cathedral.
