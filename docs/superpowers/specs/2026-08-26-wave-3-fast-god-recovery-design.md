# Wave-3 Fast God-Class Recovery Design

**Date:** 2026-08-26

**Status:** Superseded by the owner-approved Campaign-12 design on 2026-08-26

This three-owner proposal is retained as decision history. It is replaced by
`2026-08-26-campaign-12-god-recovery-design.md`, which keeps the same isolation
model but expands execution to four dependency-ordered tiers and one global
acceptance gate.

## Goal

Remove three independent production `god_class` owners in one parallel wave,
moving the authoritative production count from `23` to `20` without weakening
runtime, RBAC, transaction, UI, or release guarantees.

This wave changes the execution granularity approved by the owner: one
integrated semantic cut and one task review per owner, followed by one combined
full-suite, coverage, RepoWise, Sentrux, and whole-wave gate.

## Selected owners

| Lane | Owner | Health | NLOC | Max CCN | Deficit | Why now |
|---|---|---:|---:|---:|---:|---|
| A | `server/src/messenger/messenger.service.ts::MessengerService` | 1.74 | 1,043 | 16 | 6,529 | Highest-deficit dependency-ready owner; paired tests and 89.69% line coverage |
| B | `lib/features/admin/presentation/widgets/staff_detail_dialog.dart::_StaffDetailDialogState` | 1.04 | 662 | 30 | 4,608 | Isolated Flutter leaf with one production importer and direct characterization |
| C | `lib/features/admin/presentation/widgets/schedule_reference_settings.dart::_ScheduleReferenceSettingsState` | 2.14 | 763 | 11 | 4,471 | Isolated Flutter leaf with one production importer and mounted behavior tests |

The wave targets 15,608 weighted-deficit points. The three implementation
scopes have no direct dependency path. Shared Flutter files
`manage_entities_widget.dart`, `magic_crm_service.dart`, and
`system_settings_workspace_test.dart` are verify-only and must not be edited in
lanes B or C.

`AuthService` and `PayrollService` remain the first backend fallbacks. They
would recover 1,783 more points than the two Flutter lanes, but security and
transaction boundaries make them slower and less suitable for the first fast
wave. `ChatInfoDialog` waits for Messenger/Profile; scheduling services remain
behind neutral command metadata and lesson-transition prerequisites.

## Lane A — Messenger

Replace `MessengerService` with three semantic owners:

- `ChatInboxService`: chat listing, branch/folder/archive projection, cursor and
  summary helpers;
- `MessageDeliveryService`: message reads/sends, attachment and reference
  validation, masking, lead intake, resurface and fanout ordering;
- `ChatLifecycleService`: announcements bootstrap, direct/admin/group creation,
  membership, leave, chat detail and mute.

The controller keeps all existing `/messenger/*` routes, DTOs, payloads, actor
identity, and error behavior. Message insert, `last_message_id`, and client
resurface remain one transaction. Commit must still precede lead intake,
unarchive, audience-specific realtime publication, and chat-list fanout.
Privacy masking, branch scope, blacklist, attachment ownership, reply/forward
visibility, audit order, and existing non-idempotent retry semantics remain
unchanged. Delete `MessengerService` unless a live external source consumer is
found during implementation.

Lane A may edit only the Messenger package, its existing unit tests, and its two
PostgreSQL integration fixtures.

## Lane B — Staff detail

Retain `_StaffDetailDialogState` as a small orchestration shell and extract:

- immutable draft/normalization state;
- stateless identity, employment and branch form;
- access/status panel with explicit callbacks.

Preserve widget keys, Russian strings, role-action visibility, provisioning,
managed-password reveal, profile-save payloads, provider reads, lifecycle
dialogs, and the dialog result. The shell target is below 250 NLOC with build
CCN at most 10. New characterization or structural guards belong in a unique
`test/features/admin/staff_detail_dialog_test.dart` file.

## Lane C — Schedule reference settings

Retain `_ScheduleReferenceSettingsState` as the orchestration and saving shell,
then extract:

- selectors and save-status presentation;
- branch-hours editor for weekly hours and exceptions;
- teacher assignment/availability editor for recurring and interval data.

Preserve section enum and constructor, optimistic versions, copy-on-write map
payloads, required unavailability reasons, widget keys, Russian text, toasts,
and error behavior. The shell target is below 300 NLOC with max CCN at most 10.
New characterization or guards belong in a unique
`test/features/admin/schedule_reference_settings_test.dart` file.

## Parallel execution

Each lane uses its own `codex/` branch and Git worktree from the same exact
baseline. Each lane has one implementer and one independent reviewer. A lane is
one integrated task: characterize only missing contracts, perform the complete
semantic extraction, add a permanent structural guard, run focused tests,
typecheck/analyze/build as applicable, and collect targeted RepoWise/Sentrux
metrics.

Lanes do not run full repository coverage or a full production recount. Those
expensive gates run once after the three reviewed lane commits are integrated.
If a lane requires an out-of-scope shared-file edit, it stops and reports the
conflict instead of broadening its worktree.

Integration order is Messenger, Staff detail, then Schedule reference. Each
commit is cherry-picked independently so a failed lane can be omitted without
rewriting accepted work.

## Acceptance

Per lane:

- focused characterization and regression tests pass;
- no endpoint, DTO, payload, UI text, key, RBAC, transaction, history, audit, or
  realtime behavior changes;
- the original owner loses `god_class` and `brain_method`;
- each new semantic owner targets health at least 7.0 and max CCN at most 10;
- a permanent source/widget guard prevents the original shell from regrowing;
- task-scoped review has no Critical or Important finding.

Combined wave:

- all three reviewed commits integrate without shared-file conflict;
- the full backend Jest suite, full Flutter test suite, backend typecheck/build,
  and Flutter analyze pass;
- one fresh backend LCOV artifact and one fresh Flutter LCOV artifact are
  ingested after integration rather than once per lane;
- RepoWise index is exact and production recount proves `23 -> 20`, with no new
  production god/brain owner and empty hard risk arrays;
- Sentrux quality does not fall below 5757, depth stays at most 13, acyclicity
  remains 10000, and architectural rules pass 2/2;
- final whole-wave review has no Critical or Important finding.

Any failed lane remains outside the integration branch while successful lanes
continue. The global count decreases by the number of accepted lanes; it is
never inferred from planned work.
