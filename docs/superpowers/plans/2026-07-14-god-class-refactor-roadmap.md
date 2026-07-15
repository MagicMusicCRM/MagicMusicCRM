# De-God-ing Roadmap — MagicMusicCRM

_Created 2026-07-14. Behavior-preserving refactor of the ~9 God files into ~100–115
focused units. Sequenced by dependency and risk (what unblocks what), NOT by calendar.
Each step is independently shippable: one commit, green tests + typecheck, and a manual
check where risk warrants it._

---

## STATUS (updated 2026-07-15) — all documented God classes dissolved

| God file | Start | Now | Verdict |
|---|---:|---:|---|
| `crm.service.ts` | 9,960 | **1,451** | ✅ dissolved → 21 services + controller split |
| `crm.controller.ts` | 122 routes | **10 sub-controllers** | ✅ B6 done |
| `messenger.service.ts` | 1,974 | **780** | ✅ dissolved → 6 services + mappers |
| `profile.service.ts` | 1,466 | **701** | ✅ ProfileLinkingService extracted |
| `leads_widget.dart` | 2,601 | **859** | ✅ down to the interactive kanban core |
| `schedule_widget.dart` | 3,471 | **1,995** | ✅ down to the interactive day-view core |
| `client_card.dart` | 5,889 | **3,663** (+7 satellite files, all <800) | 🔶 core remains — see F3 |
| `messenger_screen.dart` | 3,853 | **3,363** | 🔶 interactive core — see F1 |

**Backend: essentially complete.** All three documented God classes dissolved; `tsc`
green, 440 tests / 67 suites green. Remaining backend files >800 (`crm.service` 1451 /
`leads.service` 1221 / `schedule.service` 1146 / `auth` 851 / `profile-linking` 832 /
`settings` 807) are **cohesive single-responsibility domains at the mapper-sharing wall**,
NOT God classes — splitting them means either duplicating ~180 lines of shared
mappers/types or a large shared-mappers refactor. Deliberately left per the guardrails.

**Frontend: leads + schedule done** (down to their cohesive interactive cores). `client_card`
and `messenger_screen` are reduced to their **interactive stateful cores** — every safe,
`flutter analyze`-verifiable extraction (sheets, dialogs, pure display sections) is done.
Getting these two under 800 requires hoisting state into a Riverpod controller (F1/F3),
which `analyze` cannot verify — it needs a device + backend run and should be done
incrementally, not in a headless marathon. **Stopping point per owner's decision.**

Full per-commit provenance + gotchas: memory `magicmusic-god-class-refactor.md`.

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

**B4 — mid tier** — 🔶 MOSTLY DONE (CrmService 7956 → 5616 LOC)
Shared helpers lifted first (they unblock every mid-tier domain):
- `BranchScope` (`branch-scope.ts`, `258aadf4`) — pure `branchIdExpr`/`extractBranchId`
  functions; also killed the 5× inline copy in `analytics.service.ts`.
- `AudienceResolver` (`audience.ts`, `e95d5497`) — `audienceForStudent/Group/Lesson`
  free functions; removed the 3 `affectedUserIdsForStudent` copies the B1 leaves left.
- `student-read.ts` (`4ce09427`) — shared `findStudent` + `StudentRow` (B3 seed).
- `crm-util.ts` (`19e69d23`) — `requiredTrim`/`trimOptional`/`sanitizeJsonObject`/
  `rethrowCreatePersonError`; removed the Groups/Payroll trim copies.
Domain services extracted: `FinanceService` (`e0847c37`), `TasksService` (`7e2b6b13`),
`AttendanceService` (`e797ff1a`), `StaffService` (`3babb22e`), `TeachersService`
(`e07b0794`). Back-injected into CrmService where a core aggregate calls them
(getStudentCard → finance/tasks). **Remaining:** `ScheduleService` (lessons + series +
matrix, largest), `TimelineCommentsService` (entity-resolution-coupled, closer to B5).
Still TODO: `CrmEntityResolver` map replacing the `if/else`-on-entity-type dispatch (OCP).

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

**F1 — `MessengerController`** — 🔶 STARTED, then held
`messenger_screen.dart` 3853 → 3363. `showStatusInfoDialog` peeled into `messenger_dialogs.dart`.
The bulk (`_buildChatView` 383 / `_buildChatList` 294, ~15 instance deps each) is the primary
interactive surface — NOT fractured (would create chatty-coupling). The remaining reduction IS
this F1 controller hoist: lift the 13 realtime handlers + session fields + 3 timers into a
Notifier. That's a runtime-behaviour change `analyze` can't verify — do it incrementally with a
device + backend, not headless. **Held here per owner's decision.**

**F2 — `schedule_widget`** — ✅ DONE (3471 → 1995)
Enums publicised; year/month views (`schedule_year_view` / `schedule_month_view`), lesson-details
sheet, filters/search/timezone dialogs, day-mode toggle, teacher-lesson card, shared helpers all
extracted (~12 satellite files, each <800; interactive grid already in `schedule_day_canvas`).
Remaining 1995 = the DAY VIEW interactive core (drag/resize/move/undo + `_buildDayViewByRoom/
ByTeacher`) + fetch infra — one responsibility, deliberately not fractured.

**F3 — `client_card` (heaviest widget)** — 🔶 DECOMPOSED to core (5889 → 3663), then held
22 green commits. Extracted (all `flutter analyze`-verified): modal sheets/dialogs as free
functions returning a record of collected values (`client_card_sheets.dart`,
`client_card_dialogs.dart`); pure UI factories (`client_card_ui.dart`); ~20 pure display helpers
and read-only sections as `part`-file top-level functions taking data+callbacks
(`client_card_display.dart`, `client_card_sections.dart`, `client_card_widgets.dart`,
`client_card_student_tabs.dart`) — all satellite files <800. The remaining 3663 is the
interactive stateful core: `build()`+tab dispatch, headers/action-bars, live-controller form
editors, the ledger `FutureBuilder`, and all async fetch/save + realtime. **This is exactly the
`ClientCardController` hoist** the original plan flagged as biggest-blast-radius — runtime
behaviour `analyze` can't check, needs device + backend verification. **Held here per owner's
decision** (incremental, reviewed, not a headless marathon).

**F4 — `leads_widget` (finish)** — ✅ DONE (2601 → 859)
`_LeadCard` split out (`lead_card.dart`) plus per-widget files (`kanban_column`,
`lead_board_filters`, `lead_dialogs`, `lead_badges`, `leads_board_states`, …); shared inline/
drawer filter panel unified. Remaining 859 = the interactive kanban core (board state, drag
autoscroll, optimistic status moves) — one responsibility, deliberately not fractured.

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

**Outcome (2026-07-15):** verdict met. No monsters remain — every documented God class is
dissolved into cohesive, single-responsibility units, each shippable on green tests/analyze.
The two Flutter widgets still >800 (`client_card` 3663, `messenger_screen` 3363) are reduced to
their genuine interactive stateful cores; the only path lower is a Riverpod controller hoist
(F1/F3) whose correctness `flutter analyze` cannot prove — it belongs in an incremental,
device-verified session, not a headless run. Backend files still >800 are cohesive domains at
the mapper-sharing wall, deliberately left rather than fractured. Held here by owner's decision.
