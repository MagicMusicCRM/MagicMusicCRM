# Final God Files 11→0 Design

**Status:** owner-approved for autonomous execution

**Baseline:** `8fa82cb3a0c66de31575679079f9db850e5e3cc9`
**Goal:** remove every remaining production RepoWise `god_class` and
`brain_method` owner without changing product behavior, public HTTP/Flutter
entry points, database schema, or architectural invariants.

## Baseline

The exact RepoWise index equals the baseline commit. The production filter from
Campaign-12 resolves 859 files and eleven god owners:

| Owner | Health | NLOC | Max CCN | Deficit |
|---|---:|---:|---:|---:|
| `FinanceService` | 2.09 | 815 | 9 | 4,817 |
| `_FinanceWidgetState` | 1.00 | 668 | 35 | 4,676 |
| `_PreferredScheduleEditorState` | 1.00 | 667 | 39 | 4,669 |
| `_StudentFunnelEditorState` | 1.00 | 665 | 16 | 4,655 |
| `_ClientCardState` | 1.00 | 620 | 18 | 4,340 |
| `_StudentsBoardWidgetState` | 1.48 | 662 | 19 | 4,316 |
| `_SharedTaskEditorState` | 3.24 | 790 | 22 | 3,760 |
| `LessonCommandService` | 2.94 | 739 | 13 | 3,739 |
| `StudentFunnelService` | 5.34 | 775 | 13 | 2,062 |
| `_ProductionWorkspaceHostState` | 3.49 | 425 | 14 | 1,917 |
| `_ReferenceCatalogLifecycleDialogState` | 5.65 | 378 | 25 | 888 |

Total target weighted deficit is 39,839. Target risk has zero security signals
and every owner has live behavioral coverage, although RepoWise cannot pair
some Flutter tests by filename.

## Architecture

Every existing public class/widget remains the compatibility facade. Large
state owners become composition shells; business state and async lifecycle move
to controllers, rendering moves to stateless views, and pure transformations
move to models/policies/projections. Backend facades preserve every public
method and delegate to injected query/command owners.

The program is split into three independently executable subprojects:

1. backend finance, lesson command, and student funnel services;
2. Flutter CRM/manager editors, boards, and finance;
3. production workspace and reference lifecycle shells.

Only the integrator edits `server/src/crm/crm.module.ts`. Lanes do not edit
another lane's files, stage unrelated changes, or rewrite shared providers.

## Frozen contracts

### Backend

- Controllers, routes, DTOs, error codes, JSON shapes, SQL schema, migrations,
  and public facade signatures do not change.
- Authorization executes before reads/mutations. Resource scope remains on the
  backend.
- Finance transfer legs stay in one transaction. Payment locks, duplicate
  detection, lesson ownership, insertion, audit, and realtime ordering remain
  unchanged.
- Lesson create/update/settlement update retain exactly three
  `executeVersionedMutation` envelopes with expected version, idempotency,
  audit, outbox, locks, constraints, lifecycle snapshot, settlement and
  post-commit ordering intact.
- Funnel revision publication remains append-only: branch validation, advisory
  lock, current version, stable-key checks, lead-status sync and revision insert
  stay in one transaction. Rollback publishes a new revision and never updates
  or deletes history.

### Flutter

- Existing widget constructors, dialog helpers, provider contracts, routed and
  dialog APIs, Russian copy, keys, navigation, focus, scrolling and Deep
  Charcoal/Gold theme remain compatible.
- Widgets call existing services/providers only. No direct database/Supabase
  access is introduced.
- Controllers use explicit dispose/generation guards. A stale or late async
  completion cannot mutate state, notify listeners, navigate, show UI feedback,
  or issue follow-up I/O.
- Dirty-form save/discard/cancel, preview-before-commit, expectedVersion,
  optimistic rollback, realtime precedence, and terminal-success semantics are
  preserved.
- `WorkspaceNavigationScope`, entity-link routing, ClientCard teacher
  fail-closed behavior, and capability-gated mounting remain unchanged.

## Required cuts

### Backend facades

- `FinanceService` delegates to `FinancePaymentService`,
  `StudentFinanceQueryService`, `StudentAccountTransferService`, and
  `ExpenseService` under `server/src/crm/finance/`.
- `LessonCommandService` delegates to `LessonConstraintPreviewService`,
  `LessonWriteCommandService`, and `LessonPlannedSettlementCommandService`;
  persistence/projections move to `lesson-command.repository.ts`, pure metadata
  and integrity helpers to `lesson-command-integrity.ts`.
- `StudentFunnelService` delegates to query, transition-policy, and revision
  owners under `server/src/crm/student-funnel/`; shared definitions, types,
  repository and resolver are separate owners. Existing exported types are
  re-exported from the compatibility file.

### Flutter CRM/manager

- Preferred schedule: controller owns draft/filter/validation; view renders;
  shell owns dirty-exit, pickers and Navigator.
- Shared task: immutable draft/controller owns preview generations, identity,
  payload/reminders and terminal success; view renders.
- Finance: controller owns query/CRUD/export lifecycle; `finance_widget_widgets`
  becomes a normal view library, breaking the existing part cycle; shell owns
  dialogs/toasts/provider composition.
- Student funnel: controller owns load/draft/preview/publish/rollback; view
  renders; shell owns discard/confirmation dialogs and Navigator.
- Students board: controller owns branches/pagination/search/optimistic state;
  pure projection re-buckets students; auto-scroll has a small lifecycle owner;
  existing Riverpod providers and `LeadTransferController` remain canonical.
- ClientCard: a workspace controller owns section/offset/expanded/dirty/close
  lifecycle; a pure access policy projects role/capabilities; a shell renders.
  Existing semantic extensions remain separate and are not merged into a new
  mega-controller.

### Workspace/admin

- `ProductionWorkspaceRuntime` owns controller/persistence/logout/reset/restore
  generations and initial-route normalization. `ProductionWorkspaceView`
  renders mobile/desktop shells. Host state owns Riverpod effects and dirty
  prompts.
- `ReferenceCatalogLifecycleController` owns immutable observable state and API
  orchestration. `ReferenceCatalogLifecycleContent` renders server-driven
  blockers/impact/history/actions. Dialog state owns text controllers,
  controller listening and Navigator.

## Execution waves

1. Backend: finance, student funnel, lesson command in parallel; one module
   wiring commit after all three lane commits.
2. Flutter: preferred schedule, shared task and finance in parallel.
3. Flutter: student funnel, students board and reference lifecycle in parallel.
4. Flutter: ProductionWorkspaceHost and ClientCard in parallel, after public
   widget/controller contracts from earlier waves stabilize.

Each lane uses RED→GREEN characterization/architecture tests and focused smoke.
After every integrated lane: `repowise update --index-only`, targeted RepoWise
health/risk, then Sentrux rescan/health/rules. Full backend/Flutter/coverage
gates run once after all eleven owners integrate.

## Acceptance

- Production RepoWise `god_class`: exactly `11 -> 0`; no production
  `brain_method` remains.
- Each compatibility state/facade is at most 150 NLOC unless RepoWise proves no
  god/brain marker; every new controller/view/service is at most 350 NLOC,
  health `>=7.0`, max CCN `<=10`, and has a focused test or justified pure view
  coverage.
- Original public callers do not require changes except DI registration and
  private internal imports.
- Backend full Jest, typecheck and build pass; Flutter full tests and analyze
  pass; fresh LCOV is ingested with hashes.
- RepoWise hard/security arrays are empty. Sentrux has no worse depth, cycles,
  equality, modularity, redundancy or rules than this baseline.
- Independent whole-program review reports Critical 0 and Important 0.

## Explicit exclusions

No feature redesign, route/DTO/schema migration, data cleanup, legacy history
deletion, UI restyle, unrelated dead-code cleanup, or speculative generic
framework is part of this program. `room_lifecycle_dialog.dart`, LeadsWidget,
and unrelated Auth consolidation are follow-ups only if they independently
remain health bottlenecks after the `11 -> 0` gate.
