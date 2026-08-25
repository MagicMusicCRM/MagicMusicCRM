# Production Code Health Recovery Design

**Date:** 2026-08-25

**Status:** Approved by the owner on 2026-08-25

## Context

RepoWise at `dd31e2a81c37` reports a repository health score of `6.32/10`.
The production modules are uneven: Flutter `lib` is `4.56/10`, backend
`server` is `6.64/10`, and tests are `8.13/10`. The code-only weighted score
is `5.93/10`; 376 files are below the target score of 8, but the top 36 files
represent about half of the weighted deficit.

The dominant issue is not raw file count. A small number of large orchestration
files combine presentation, workflow, policy, persistence, and side effects.
RepoWise ranks these files by weighted deficit, led by:

- `lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart`;
- `server/src/crm/schedule.service.ts`;
- `server/src/crm/crm-configuration.service.ts`;
- the Client Card, Teacher, Lead, and lesson-commerce god classes.

Sentrux at the same commit reports quality `4974`, acyclicity raw `1`, depth
`13`, and both architectural rules passing. RepoWise coverage attribution is
incomplete for capability-grouped Flutter tests, so a missing paired test file
must not be treated as proof that behavior is untested.

## Goal and success contract

Recover production architecture through a sequence of rollback-safe,
behavior-preserving cuts until all of the following are true on one indexed
commit:

- RepoWise `lib` average health is at least `7.0`;
- RepoWise `server` average health is at least `7.0`;
- combined production-code health is at least `7.5`;
- Sentrux acyclicity remains raw `1`, architectural rules pass, and quality
  does not regress from the baseline;
- Flutter and backend full verification gates pass.

These are module-level weighted gates. The program does not require every
individual production file to score 7: that would reward artificial file
splitting and test relocation rather than reducing architectural risk.

## Considered approaches

### 1. Weighted-deficit portfolio — selected

Address the highest weighted-deficit production boundaries in independent
vertical cuts. Each cut has characterization coverage, explicit ownership,
direct consumers, rollback-safe commits, and fresh RepoWise/Sentrux evidence.
This targets the small set of files responsible for most of the health gap.

### 2. Shallow metric optimization

Rename or move tests to match production filenames and split declarations into
small files without changing ownership. This can increase reported health
quickly, but leaves change coupling and orchestration risk intact. It is
rejected except for truthful coverage ingestion.

### 3. Big-bang layer rewrite

Replace the Flutter CRM and backend scheduling/configuration layers at once.
This could remove more debt per commit, but would combine UI, authorization,
transaction, rollout, and persistence risk. It is rejected.

## Program architecture

The program is a queue of independent health packages rather than one long
rewrite:

1. **Metric calibration.** Generate real Flutter/backend coverage artifacts
   and ingest them into RepoWise. Recompute the baseline without moving tests
   solely to satisfy filename pairing.
2. **Scheduling presentation.** Split recurring-plan presentation, constraint
   interpretation, and mutation workflows from the Flutter section shell.
3. **Scheduling backend.** Remove or extract remaining legacy scheduling
   responsibilities only after production reachability and rollback policy are
   approved; preserve transactions, advisory locks, expected versions,
   idempotency, audit/outbox, and RBAC.
4. **CRM configuration backend.** Move snapshot normalization and impact
   calculation into pure policy components, leaving persistence orchestration
   in the service.
5. **Remaining portfolio.** Process Client Card, Teacher, Lead, CRM, and
   commerce god classes in descending weighted-deficit order.

The queue is re-ranked after every package. A later package may move when fresh
metrics show a larger safe gain.

## First package: recurring schedule presentation

The first implementation package targets
`recurring_schedule_plan_section.dart`, currently 1,947 NLOC with health `1`,
max CCN `20`, and a weighted deficit of `13,629` points (`2.8%` of the whole
repository gap). One state class spans about 931 lines and owns 28 methods.

The cut creates four cohesive presentation boundaries:

- `schedule_plan_constraint_interpreter.dart` owns pure parsing, grouping,
  labels, draft-index mapping, and ranked suggestions from preview payloads;
- `schedule_plan_rows_review.dart` owns row editing and constraint-review UI;
- `recurring_schedule_plan_view.dart` owns active/ended plan cards, tray
  rendering, fallback lessons, and lesson-opening progress;
- `schedule_plan_mutation_flow.dart` owns create, row update, participant
  update, and end-sheet orchestration through explicit dependencies.

`RecurringSchedulePlanSection` remains the composition shell. It owns only the
entity-keyed controller lifecycle, write eligibility, reload/error feedback,
and wiring between the view and mutation flows. The existing
`RecurringSchedulePlanController` and `MagicCrmService` stay canonical; the cut
does not introduce a parallel state model or direct API/database access from a
widget.

## Data and interaction flow

```text
RecurringSchedulePlanSection
  -> RecurringSchedulePlanController -> MagicCrmService
  -> RecurringSchedulePlanView        -> callback intents
  -> SchedulePlanMutationFlow         -> MagicCrmService / MagicApiClient
  -> SchedulePlanRowsReview
       -> SchedulePlanConstraintInterpreter (pure)
```

Inputs remain immutable value objects or callback contracts. The constraint
interpreter receives preview maps and draft rows and returns typed issues and
suggestions; it owns no `BuildContext`, Riverpod reference, network client, or
mutable widget state.

## Preserved invariants

- Creation remains unavailable without an eligible subscription and hidden
  without `canWrite`.
- Group plans keep participant/subscription selection and dated versioned
  updates.
- Create, update, participant update, and end operations retain their current
  mutation identities, expected versions, effective dates, preview-before-
  commit sequence, and Russian success/error messages.
- Constraint grouping, participant labels, lesson links, suggestion ranking,
  time offsets, and draft-row mapping remain assertion-equivalent.
- Active plans stay expanded, ended plans stay grouped, tray pagination and
  retry remain unchanged, and duplicate lesson opening remains guarded.
- The Deep Charcoal & Sophisticated Gold theme and current widget keys remain
  unchanged.

## Test strategy

First add focused unit tests for the pure constraint interpreter using the
current analyzer and legacy preview shapes. Then move the existing row-review,
plan-card, tray, create/edit/participant/end widget assertions to the new
owners without weakening selectors or expectations. The existing capability-
grouped test remains a production behavior gate.

Focused Flutter tests run after each extraction. The package then runs full
`flutter test`, `flutter analyze`, diff checks, Sentrux scan/rules, RepoWise
index refresh, changed-file health, and change risk.

## Delivery and rollback

Each boundary lands in its own commit: pure interpreter, review widget, plan
view, mutation flow, and shell wiring. No API, schema, migration, environment,
or production-state change is part of this package. Rollback uses normal Git
reverts in reverse order; no data repair is required.

The package is accepted only when the original file and god-class span shrink
materially, all behavior gates pass, RepoWise reports no new cycle or missing
consumer, and the measured module/global health moves toward the approved
contract. Exact score gain is measured rather than promised.

## Package 1 verified outcome

The recurring-schedule presentation package is implemented and verified at
`7347300849b5`. It landed as five rollback-safe implementation commits:
`7425bc21`, `3649def3`, `1cbea79b`, `03d70353`, and `73473008`.

- Fresh verification passed: focused cross-boundary tests `78/78`, full Flutter
  tests `997/997`, full `flutter analyze` with zero issues, and a clean diff.
- RepoWise is exact at `7347300849b5` with `index_behind=false`. The original
  coordinator improved from health `1.00`, `1,947` NLOC, max CCN `20`, and
  weighted deficit `13,629` to health `4.98`, `214` NLOC, max CCN `9`, and
  weighted deficit `646`. The extracted interpreter, review, view, mutation,
  and end boundaries score `7.41`, `7.41`, `7.41`, `8.35`, and `8.43`.
- The Flutter module moved from `4.56` to `4.70`; repository code-only health
  moved from `5.93` to `5.99`. Backend health remained `6.64` because this
  package changed no backend production code.
- Sentrux reports quality `4974`, acyclicity raw `1`, depth raw `13`, modularity
  `5362`, redundancy `4826`, and both architectural rules passing. The
  design-token cut removed the historical `design_tokens -> telegram_colors`
  forwarding edge without changing any locked ARGB value.
- RepoWise classifies the full package change as `Elevated`, risk percentile
  `100`, because it spans 20 files and 5,170 changed lines. The authoritative
  full Flutter suite covers the package where line-level attribution is absent.

The global success contract remains open: `lib 4.70 < 7.0`,
`server 6.64 < 7.0`, and code-only `5.99 < 7.5`. Fresh RepoWise re-ranking
selects `server/src/crm/schedule.service.ts` as package 2: its god-class cut is
the current directive and represents `11,346` recoverable weighted points.

## Package 2 verified outcome

The full scheduling-backend ownership split is implemented and verified at
`2f6627a9`. It landed as independent rollback points for conflict ownership,
series materialization, series commands, test ownership, deletion of the old
god class, lesson-write simplification, creation persistence, and teacher-rate
corrections.

- RepoWise is exact at `2f6627a9b0fc` with `index_behind=false`. The original
  `schedule.service.ts` improved by deletion from health `1.90`, 1,860 NLOC,
  max CCN `16`, and weighted deficit `11,346`; no compatibility facade remains.
- Direct replacement owners score: mutation `8.55`, teacher rate `8.15`,
  conflict `9.50`, locks `9.85`, series commands `7.80`, series read `7.80`,
  and materialization `7.45`. The mutation and rate owners have zero weighted
  deficit, and none of the seven owners has the former god-class finding.
- Full backend verification passed: 199 suites, 1,493 tests, typecheck, Nest
  build, and a clean diff. Transaction-owned executors, deterministic locks,
  expected versions, append-only payroll facts, audit, realtime, and legacy/V4
  routing remain covered by the redistributed characterization suites.
- The backend module health moved from `6.64` to `6.74`. Sentrux closed at
  quality `4974`, acyclicity `1`, depth `13`, equality `6186`, modularity
  `5353`, redundancy `4827`, and both architecture rules passing. Modularity
  fell by 9 raw points as direct owners replaced one facade, while the combined
  quality floor and graph invariants remained accepted.

The global success contract remains open: backend `6.74 < 7.0`, Flutter
`4.70 < 7.0`, and repository code-only health has not yet reached `7.5`.
Fresh RepoWise re-ranking selects
`server/src/crm/crm-configuration.service.ts` as the next directive: an
untested five-dependent hotspot with `10,021` recoverable weighted points.

## Package 3 verified outcome

The CRM configuration semantic split is implemented and verified at
`650960b1940c`.

- RepoWise is exact with `index_behind=false`. The original service moved from
  health `1.06`, `1,444` NLOC, max CCN `53`, and weighted deficit `10,021` to
  health `8.00`, `412` NLOC, max CCN `9`, and zero weighted deficit. The
  god-class finding is removed.
- All extracted production owners exceed the `7.0` floor: normalizer `8.15`,
  persistence `9.85`, impact policy `8.50`, branch policy `10.00`, and
  contracts `9.85`. The whole configuration package now has zero weighted
  deficit.
- Full backend verification passed with `204` suites and `1,516` tests, plus
  typecheck, Nest build, focused CRM `32/32`, and a clean diff. Sentrux reports
  quality `5720`, acyclicity score `10000` with raw `0`, depth `13`, equality
  `6202`, modularity `5355`, redundancy `4841`, and both rules passing.
- Backend module health is now `6.86`; repository code-only health is `6.12`.
  The global contract remains open, so the recovery program continues.

The literal dashboard directive is a large integration test whose primary
signal is historical co-change scatter. Applying the approved production-first
ranking instead selects
`server/src/crm/commerce/lesson-settlement.repository.ts`: health `1.00`,
`1,264` NLOC, max CCN `21`, weighted deficit `8,848`, nine dependents, and an
untested financial hotspot. It is package 4; characterization must precede any
structural change.
