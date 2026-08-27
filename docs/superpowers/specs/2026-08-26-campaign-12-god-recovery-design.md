# Campaign-12 God-Class Recovery Design

**Date:** 2026-08-26

**Status:** Approved in chat; awaiting owner review of this written specification

## Goal

Remove up to twelve production `god_class` owners in one continuous campaign,
moving the authoritative count from `23` to `11` if every lane passes. The
campaign optimizes wall-clock throughput while preserving the production
contracts established by the approved `25 -> 0` program.

The owner approved two execution changes:

- each owner receives only a short lane smoke-check during implementation;
- full repository suites, coverage, RepoWise recount, Sentrux acceptance, and
  whole-campaign review run once after all accepted lanes are integrated.

No lane is credited from planned work. A failed lane is omitted independently,
and the final count decreases only by owners proven clean at the global gate.

## Why staged rather than blind parallelism

The runtime exposes only three implementation-agent slots beside the
integrator. Twelve simultaneous branches would exceed that limit and ignore
real dependency order. Four tiers of three lanes keep all slots productive,
allow foundational owners to land before dependent UI owners, and isolate
merge failures.

The final global tests are not the dominant historical cost: the latest full
backend suite took 117.871 seconds, coverage 150.433 seconds, and a production
recount about 118 seconds. The previous delay came from eight microtasks,
repeated reviews, and repeated index waits for one owner. Campaign-12 replaces
that with one integrated cut per owner, one review per tier, and one global
gate.

## Authoritative starting point

Package 10 is closed with Critical/Important/Minor `0/0/0`. The production-only
RepoWise filter contains 781 files and exactly 23 `god_class` owners. Sentrux
baseline is quality 5757, depth 13, acyclicity 10000, and rules 2/2.

The implementation plan records the exact Campaign-12 baseline commit after
this specification and its plan are committed. Every Tier 1 worktree starts
from that same full SHA.

## Dependency tiers

| Tier | Lane | Production owner | Deficit | Dependency role |
|---:|:---:|---|---:|---|
| 1 | A | `server/src/messenger/messenger.service.ts::MessengerService` | 6,529 | Foundation for chat UI |
| 1 | B | `server/src/crm/payroll.service.ts::PayrollService` | 5,395 | Foundation for teacher statistics |
| 1 | C | `server/src/crm/commerce/subscription-issue.service.ts::SubscriptionIssueService` | 4,435 | Foundation for subscription issue UI |
| 2 | D | `server/src/profile/profile.service.ts::ProfileService` | 3,424 | Second foundation for chat UI |
| 2 | E | `server/src/auth/auth.service.ts::AuthService` | 5,467 | Independent security boundary |
| 2 | F | `server/src/crm/schedule/lesson-transition.service.ts::LessonTransitionService` | 5,250 | Schedule foundation plus neutral command metadata prerequisite |
| 3 | G | `lib/core/widgets/telegram/chat_info_dialog.dart::_ChatInfoDialogState` | 5,649 | Runs after Messenger and Profile |
| 3 | H | `lib/features/manager/presentation/widgets/teacher_stats_widget.dart::_TeacherStatsWidgetState` | 5,327 | Runs after Payroll |
| 3 | I | `lib/features/crm/presentation/client_card/subscription_issue_sheet.dart::_SubscriptionIssueFormState` | 5,525 | Runs after SubscriptionIssueService |
| 4 | J | `server/src/crm/schedule/schedule-plan.service.ts::SchedulePlanService` | 5,074 | Runs after LessonTransition and neutral metadata |
| 4 | K | `lib/features/admin/presentation/widgets/staff_detail_dialog.dart::_StaffDetailDialogState` | 4,608 | Independent Flutter leaf |
| 4 | L | `lib/features/admin/presentation/widgets/schedule_reference_settings.dart::_ScheduleReferenceSettingsState` | 4,471 | Independent Flutter leaf |

The twelve owners represent 61,154 current weighted-deficit points. The list is
dependency-driven rather than raw-rank-only: blocked UI owners are placed after
their backend foundations, and the scheduling lane is placed after its required
transition/metadata foundation.

## Lane architecture

Each lane is one integrated semantic cut, not a sequence of extraction phases.
It must:

1. Characterize only missing externally observable contracts.
2. Extract cohesive semantic owners while keeping one existing runtime and API.
3. Delete the god owner or reduce it to a small behavior-free shell.
4. Add a permanent AST/widget structural guard against regrowth.
5. Produce one reversible implementation commit and one lane report.

New semantic owners target health at least 7.0, max CCN at most 10, and no
`god_class` or `brain_method`. Compatibility shells must have explicit NLOC,
dependency, public-method, and direct-delegation ceilings derived from the
source contract.

### Backend invariants

Messenger retains route/DTO identity, membership and branch scope, masking,
message/reference/attachment validation, transaction boundaries, audit, lead
intake, realtime, and post-commit fanout order.

Payroll retains expected versions, rate and payout transaction boundaries,
idempotency, audit/outbox, append-only facts, calculation precision, and export
shape. Subscription issues retain preview/blocker/commit lifecycle, transaction
and projection ordering, audit/outbox, and historical records.

Profile and Auth retain fail-closed RBAC, credential/OTP/recovery behavior,
token/session semantics, password hashing, resource scope, audit, and response
shape. LessonTransition and SchedulePlan retain lock order, expected versions,
idempotency, lesson history, neutral command metadata, audit/outbox, and
append-only schedule facts.

### Flutter invariants

All UI text remains Russian and all widgets remain on the Deep Charcoal &
Sophisticated Gold theme. Existing keys, navigation, provider ownership,
payload maps, optimistic versions, dialogs, toasts, error states, focus,
scrolling, and accessibility semantics remain stable. Widgets continue to use
existing services/providers; no direct database or Supabase access is added.

ChatInfo may start only after Messenger and Profile integrate. TeacherStats may
start only after Payroll integrates. SubscriptionIssueSheet may start only
after its backend service integrates. StaffDetail and ScheduleReference remain
leaf cuts and may not edit their shared parent, `magic_crm_service.dart`, or the
shared workspace characterization test.

## Worktrees and shared files

Each tier starts three `codex/campaign12-*` branches and worktrees from the same
integrated tier baseline. Lanes may not edit another lane's package.

Shared wiring is centralized:

- lane commits omit conflicting shared-module wiring when two lanes need the
  same module;
- after the three commits are applied, the integrator creates one tier wiring
  commit and runs the same lane smoke against the wired graph;
- shared Flutter parents and shared characterization tests are verify-only;
- an unplanned shared-file requirement stops that lane for an integrator
  ruling instead of silently widening scope.

Tier integration order is A/B/C, then D/E/F, then G/H/I, then J/K/L. The next
tier does not start until the preceding tier commits, wiring, smoke-checks, and
tier review are clean. This is dependency synchronization, not a global test
gate.

## Lane smoke-check

Lane smoke is mandatory and deliberately small. It includes:

- tests directly characterizing the moved boundary and its permanent guard;
- compile/typecheck or Flutter analyze restricted to the affected package when
  supported, plus `git diff --check`;
- live source checks for transaction/RBAC/UI invariants relevant to that lane;
- targeted RepoWise health for the original and new owners.

Lane smoke excludes full backend Jest, full Flutter tests, fresh repository
coverage, full RepoWise production recount, Sentrux global acceptance, and
whole-campaign review. Those run once after Tier 4.

A lane with a failing smoke cannot integrate. This is the minimum evidence
needed to keep a late global failure attributable; removing even lane smoke is
expected to increase total debugging time.

## Review model

One independent reviewer examines the three commits and wiring of each tier as
an integrated package. The reviewer verifies scope, dependency order, behavior
contracts, permanent guards, and smoke evidence. Critical or Important
findings are fixed before dependent tiers start. Minor hardening may be deferred
only to the global gate with an explicit ruling and cost.

This reduces review cycles from twelve owner reviews to four tier reviews while
keeping independent scrutiny at every dependency boundary.

## Single global gate

After all accepted Tier 4 commits integrate, run exactly one campaign gate:

- full backend Jest, backend typecheck and Nest build;
- full Flutter tests and Flutter analyze;
- fresh backend and Flutter LCOV artifacts with hashes and RepoWise ingestion;
- exact RepoWise index, health for every original/new owner, hard risk arrays,
  and one production-only god/brain recount;
- Sentrux rescan, health and rules;
- final whole-campaign review over the complete commit range.

Acceptance requires:

- production `god_class` count `23 -> 11` if all twelve lanes integrated, or an
  exact decrease equal to the number of accepted lanes;
- no new production god/brain finding;
- every new owner at health at least 7.0 and max CCN at most 10;
- no endpoint/DTO/RBAC/transaction/history/audit/outbox/UI regression;
- empty breaking-change, consumer-break, dependency-cycle, conformance, and
  security arrays;
- Sentrux quality at least 5757, depth at most 13, acyclicity 10000, rules 2/2;
- final review with no Critical or Important finding.

If the global gate fails, use the lane/tier commit boundaries and focused smoke
tests to identify the owning cut. Fix only that lane, rerun its smoke, then
rerun the single global gate. Accepted sibling lanes are not rewritten.

## Expected throughput

Campaign-12 uses four three-lane tiers. The planning target is 14–24 hours of
continuous wall-clock work, followed by the single global gate. This is a
planning range, not an acceptance shortcut: campaign completion is determined
only by the exact final evidence.

## Results

Campaign-12 is **ACCEPTED** for the literal range
`9cb1f506a5c5418650926fe53b81fe2667ba9bd7..734a5f0f44b6bd9ec8861c05ec4e0c3959f697f1`.
All twelve lanes and four tier reviews integrated. The exact lane/tier commit
ledger, 92-owner health/coverage ledger, production filter, LCOV provenance,
risk arrays, Sentrux ruling, and eleven remaining owners are recorded in
`.superpowers/campaign12/campaign-12-global-evidence.md`; independent review
and every corrective disposition are in
`.superpowers/campaign12/campaign-12-whole-review.md`.

Measured acceptance: production god owners `23 -> 11`; weighted deficit
`61,154 -> 5,734` (`90.62%` recovered); no changed production brain finding;
all 80 added production owners meet health `>=7.0` and CCN `<=10`. Backend is
251/251 suites and 1,723/1,723 tests plus typecheck/build PASS. Flutter is
1,214/1,214 plus analyzer zero. RepoWise hard/security arrays are empty.
Sentrux is quality 5,829, depth 13, cycles 0/10,000, rules 2/2, with equality,
modularity, and redundancy all improved from the campaign baseline. Independent
review is Critical 0, Important 0, Minor 1; the duplicate active-account
lookup is explicitly deferred to Auth repository consolidation.

The evidence commit is the commit containing these Results and cannot embed
its own SHA. Its full SHA and exact RepoWise index equality are verified
immediately after commit.
