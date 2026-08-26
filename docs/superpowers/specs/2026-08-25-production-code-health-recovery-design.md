# Production Code Health Recovery Design

**Date:** 2026-08-25

**Status:** Approved by the owner on 2026-08-25; the complete `25 -> 0`
continuation was approved on 2026-08-26

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
- RepoWise reports zero `god_class` findings in live `lib/` and `server/src/`
  production code;
- every replacement owner created by the program scores at least `7.0`, has no
  god/brain owner finding, and keeps max CCN at or below `10` unless an explicit
  transaction-preservation exception is recorded with focused coverage;
- Sentrux acyclicity remains perfect under the active metric semantics
  (currently raw `0`, score `10000`), architectural rules pass, and quality
  does not regress from the active package baseline;
- Flutter and backend full verification gates pass.

The module scores are weighted gates, while zero production god classes is an
absolute gate. Files below `7.0` must also be triaged before completion: current
structural causes are fixed, while history-only or coverage-attribution signals
receive truthful tests/decisions instead of artificial file splitting or test
relocation. Therefore an average above target cannot hide an unresolved god
owner, and a volatile but cohesive boundary is not split solely to game the
metric.

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

## Package 4 verified outcome

The lesson-settlement ownership split is implemented and verified at
`dd71952a0f9f`.

- The `1,264`-NLOC repository with health `1.00`, max CCN `21`, and weighted
  deficit `8,848` is deleted without a compatibility facade. Six narrow
  production owners now separate catalog policy, plan persistence, effective
  facts, capacity locks, execution, and the application port.
- Every replacement meets the `7.0` health floor, max CCN is `10`, max NLOC is
  `555`, and the combined weighted deficit is `82`, a `99.1%` reduction.
- Full backend verification passed with `209` suites and `1,531` tests, plus
  typecheck, Nest build, and clean diff checks. RepoWise is exact with no live
  broken consumer, new cycle, missing-test warning, or conformance violation.
- Sentrux closed at quality `5732`, acyclicity `10000` with raw `0`, depth `13`,
  equality `6223`, modularity `5360`, redundancy `4870`, and both rules passing.

Repository code-only health is now `6.15`, so the global contract remains open.
The literal dashboard directive remains the 2,329-NLOC subscription integration
test (`9,549` weighted points) whose primary signal is historical co-change
scatter. Under the approved production-first policy, package 5 instead targets
`lib/features/crm/presentation/client_card/client_card_editors.dart`: health
`1.41`, `1,376` NLOC, max CCN `24`, weighted deficit `9,068`, 46.93% line
coverage, and co-change with 30 files. The next god-class owners remain
`server/src/crm/leads.service.ts` (`8,394`) and
`server/src/crm/crm.service.ts` (`7,381`); both stay in the mandatory cleanup
queue rather than being displaced by the package-5 choice.

## Package 5 verified outcome

The Client Card editor ownership split is implemented and verified at
`d6da59b19396`.

- The former `1,376`-NLOC editor part with health `1.41`, max CCN `24`, and
  weighted deficit `9,068` is deleted without a compatibility owner. Seven
  semantic parts now own custom-field policy and inputs, moderation, contacts,
  assignments, comments, and family/access behavior.
- Every replacement exceeds the `7.0` health floor: scores range from `8.80`
  to `10.00`, max CCN is `10`, max NLOC is `274`, and combined weighted deficit
  is zero. Repository code-only health moved from `6.15` to `6.21`.
- Full Flutter verification passed `999/999`, `flutter analyze` found no issues,
  and diff checks are clean. RepoWise change risk is percentile `96.4` due to
  the size of the semantic move, with 12 impacted tests and no untested changed
  line category.
- Sentrux reports quality `5730`, acyclicity `10000` with raw `0`, depth `13`,
  equality `6228`, modularity `5360`, redundancy `4857`, and both rules passing.
  The two-point package-local variance is caused by the seven-owner graph; the
  overall recovery-program quality remains `756` points above its `4974`
  baseline and no graph invariant regressed.

The global success contract remains open: code-only health is `6.21 < 7.5`.
Fresh production-first ranking selects `server/src/crm/leads.service.ts` as
package 6: health `1.90`, `1,376` NLOC, max CCN `26`, and weighted deficit
`8,394`. The remaining CRM and Flutter god classes stay in the mandatory queue.

## Package 6 verified outcome

The Leads application ownership split is implemented and verified at
`1ee213707149`.

- The former `1,376`-NLOC god class with max CCN `26` is now a SQL-free stable
  facade of `63` NLOC and max CCN `1`. Board query/filter/assembly, card
  aggregation, directory reads, transactional persistence, commands, and DTO
  mapping each have a named production owner.
- New owner health ranges from `7.44` to `9.65`, max CCN is `8`, max NLOC is
  `346`, and no god/brain finding remains. Combined facade/replacement weighted
  deficit is `247` versus `8,394`, a `97.1%` reduction.
- Full backend verification passed `211/211` suites and `1,537/1,537` tests,
  typecheck, Nest build, and diff checks. Eight final paired owner tests also
  pass; exact RepoWise risk reports `missing_tests=[]`, no new cycle, no
  conformance violation, no broken consumer, and no breaking API change.
- Sentrux improved `5730 → 5745`, with acyclicity `10000`/raw `0`, depth `13`,
  equality `6249`, modularity `5369`, redundancy `4896`, and both rules passing.

Backend module health is `7.02`, so the server-side program gate is achieved.
Repository code-only health is `6.26`; Flutter `4.82` and the overall `7.5`
contract remain open. The literal dashboard directive is still the large
subscription integration suite whose primary signal is historical co-change.
Under the approved production-first ranking, package 7 targets
`lib/features/admin/presentation/widgets/teacher_detail_dialog.dart`: health
`1.00`, `1,158` NLOC, max CCN `19`, weighted deficit `8,106`, zero attributed
line coverage, and ten dependents. `create_lesson_dialog.dart`,
`crm.service.ts`, `client_card_student.dart`, and `lesson_decision_flow.dart`
remain in the mandatory god-file cleanup queue.

## Package 7 verified outcome

The Teacher Detail dialog ownership split is implemented and verified at
`ab0f054baf67`.

- The former `1,158`-NLOC cyclic god owner is replaced by an import-only public
  shell of `234` NLOC and ten narrow semantic collaborators. Max CCN is `10`,
  and the shell itself is max CCN `5`.
- New-owner health ranges from `7.85` to `10.00`. Combined weighted deficit is
  `800` versus `8,106`, a `90.1%` reduction; no god/brain finding or dependency
  cycle remains. The shell's `4.73` headline is now historical co-change and
  prior-fix risk, not current structural complexity.
- Full Flutter verification passed `1,016/1,016`; analyzer and diff checks are
  clean. Direct tests own every live split boundary, including payroll version,
  access, RBAC, history, dialog-controller lifetime, and audit-reason behavior.
- Sentrux improved from the package baseline `5745` to `5748`, with acyclicity
  `10000`/raw `0`, depth `13`, equality `6262`, modularity `5381`, redundancy
  `4889`, and both rules passing.

Repository code-only health is now `6.30`, up from `6.26`; the global `7.5`
contract and the all-god-files program remain open. Under the production-first
policy, package 8 targets
`lib/features/admin/presentation/widgets/create_lesson_dialog.dart`; the literal
dashboard directive remains the subscription integration suite whose leading
signal is historical co-change scatter. `server/src/crm/crm.service.ts`,
`client_card_student.dart`, and `lesson_decision_flow.dart` remain mandatory
follow-up packages.

## Package 8 verified outcome

The lesson-creation ownership split is implemented and verified on the exact
production commit `861d89d77b0f25d3224e8a4d6f8770ae99aa1191`. The later
evidence-only commit does not change production code.

- The two original structural owners were
  `create_lesson_dialog.dart` at health `1.00`, `1,099` NLOC, max CCN `35`,
  and weighted deficit `7,693`, and `lesson_decision_flow.dart` at health
  `1.00`, `1,025` NLOC, max CCN `28`, and deficit `7,175`. Their total
  baseline deficit was `14,868`.
- The stable public boundaries are now a `298`-NLOC dialog composition shell
  at health `3.99`, max CCN `12`, `90.73%` line coverage, and deficit `1,195`,
  plus a `37`-NLOC decision entry at health `6.50`, max CCN `1`, `100%`
  coverage, and deficit `56`. The old god state, part cycle, and CCN-28 brain
  are gone. The shells alone carry `1,251` deficit points, a `91.6%`
  reduction from the two original files.
- The dialog shell's `save` remains the explicit Task 10 composition exception:
  CCN `12` in a `47`-NLOC UI-lifecycle method. The extracted semantic-owner
  ceiling remains max CCN `10`; no semantic owner or public shell has a
  `god_class` or `brain_method` finding.

Fresh full coverage at the same production SHA ingested `336` exact files and
`30,666/42,849` lines (`71.57%`). RepoWise measured the new semantic owners as
follows; weighted deficit is floored at zero per file against the `8.0` target.

| New semantic owner | Health | NLOC | Max CCN | Lines | Deficit |
|---|---:|---:|---:|---:|---:|
| `lesson_schedule_analysis.dart` | 9.65 | 139 | 5 | unmapped | 0 |
| `lesson_decision_controller.dart` | 8.37 | 192 | 10 | 90.48% | 0 |
| `lesson_decision_form.dart` | 7.97 | 296 | 10 | 90.50% | 9 |
| `lesson_decision_models.dart` | 9.73 | 169 | 3 | 97.10% | 0 |
| `lesson_decision_sections.dart` | 9.53 | 696 | 10 | 96.96% | 0 |
| `lesson_editor_data_controller.dart` | 6.89 | 606 | 9 | 96.68% | 673 |
| `lesson_editor_decision_policy.dart` | 5.57 | 610 | 9 | 97.81% | 1,482 |
| `lesson_editor_feedback.dart` | 5.90 | 268 | 4 | 93.75% | 563 |
| `lesson_editor_initial_mapper.dart` | 7.82 | 157 | 5 | 98.77% | 28 |
| `lesson_editor_models.dart` | 5.05 | 367 | 9 | 100% | 1,083 |
| `lesson_editor_save_flow.dart` | 9.63 | 163 | 4 | 98.21% | 0 |
| `lesson_editor_schedule_controller.dart` | 9.45 | 88 | 5 | 100% | 0 |
| `lesson_editor_view.dart` | 4.52 | 302 | 9 | 96.67% | 1,051 |
| `lesson_financial_section.dart` | 5.90 | 360 | 8 | 100% | 756 |
| `lesson_participant_section.dart` | 5.77 | 318 | 10 | 85.53% | 709 |
| `lesson_schedule_section.dart` | 7.18 | 328 | 10 | 97.86% | 269 |

The new semantic owners total `6,623` deficit points. Including the two stable
public shells, the replacement portfolio totals `7,874`, so the original
numeric `<= 2,230` portfolio gate is not met. The owner accepts this exact
history/co-change exception: five fixes now attach to models and policy, three
to feedback/view/financial/participant, and the same files co-change with
`9-12` peers even though current coverage is `85.53-100%`, max CCN is `10`,
and no god/brain remains. The cost is an honest `47.0%` measured portfolio
reduction instead of the original `85%`; history was not rewritten, files were
not moved for score, and functions were not reshaped to game denominators.

Three pre-existing touched boundaries remain outside the new-owner portfolio:
`magic_crm_service_schedule.dart` is `3.54/21/78.57%` with `3,809` deficit
points from unrelated service methods, while `searchable_picker_field.dart`
is `6.33/12/95.28%` with `387` and `searchable_select.dart` is
`3.89/17/90.91%` with `1,377`. The picker/select brain findings and structure
are their pre-package shared-widget baseline; Package 8 only relocated the
dependency-free item model and preserved the old import by re-export.

Verification is exact and fresh:

- the expanded owner-focused suite passed `205/205` in `39.108s`;
- the full Flutter suite passed `1,105/1,105` in `159.389s`, and the separate
  full coverage run passed `1,105/1,105` in `221.442s`;
- `flutter analyze` reported zero issues in `11.710s`; `git diff --check`
  exited zero in `0.026s`;
- RepoWise coverage remains pinned to the exact production SHA `861d89d7`.
  The final index is exact at the documentation SHA `8ad0594c`; its indexed
  MCP/status dashboard has `1,596` files, average health `6.70`, and hotspot
  health `5.90`. Separately, the live CLI health scan sees `1,695` files at
  average health `6.82` and hotspot health `4.69` while consuming the
  production-SHA LCOV; these scopes are not interchangeable.

The exact 34-file `lib` change set gives RepoWise PR blast score `6.27`.
`breaking_changes`, `conformance_violations`, `dependency_cycles`, and
`will_break_consumers` are empty. The three `missing_tests` labels are
`lesson_schedule_section.dart`, `lesson_editor_feedback.dart`, and
`lesson_decision_form.dart`. The first two are directly exercised by
`lesson_editor_sections_test.dart`; the form has `90.50%` ingested coverage
through the flow suite, so none is a truthful owner gap. The full suite passes.
The MCP-only `lesson_schedule_analysis.dart: not_indexed` result is likewise
resolved by live CLI health (`9.65/5`, 139 NLOC) and source. Dart-filtered
`get_change_risk` for `d1d24ea3..861d89d7` is Elevated/high at percentile
`100`, score `9.9`, probability `99.1%`, driven by `10,699` additions and
`2,943` deletions across `50` files; this is review priority, not a
broken-consumer finding.

Sentrux closes on the accepted `5736` exception: genuine Task 10 fixes improved
`5723 -> 5736`, while the remaining 12 global points require unrelated cleanup.
Fresh raw evidence is depth `13`/score `3810`, acyclicity raw `0`/score
`10000`, equality raw `0.3690247236570714`/score `6310`, modularity raw
`0.31095361747322303`/score `5406`, redundancy raw
`0.5222544113774032`/score `4777`, `4,655` import edges, `2,727` cross-module
edges, and rules `2/2`; a same-tree session end is stable at `5736 -> 5736`.

The production god-owner recount moves `26 -> 25`; Package 8 removes the old
`_CreateLessonDialogState` finding. The next package is
`server/src/crm/commerce/subscription-lifecycle.service.ts`: health `1.04`,
`1,350` NLOC, max CCN `14`, and recoverable weighted deficit `9,396`. It ranks
ahead of `crm.service.ts` (`7,381`) and `lesson-transition.service.ts`
(`7,076`). Repository completion remains open.

## Live global god-owner audit after Package 7

A full in-process `repowise health --format json` run at `d1ce1b443b8d`
analyzed 1,670 files. Repository average health is `6.77`, hotspot health is
`4.61`, and the production-only filter finds `239` files below `7.0` plus `26`
live `god_class` findings. The filter includes `lib/**` and `server/src/**` and
excludes specs, tests, integration fixtures, generated platform code, docs, and
outputs. This is the authoritative baseline for the owner's all-god-files
requirement; dashboard test-file directives do not displace it.

| # | Production owner | RepoWise | NLOC |
|---:|---|---:|---:|
| 1 | `lib/core/widgets/telegram/chat_info_dialog.dart::_ChatInfoDialogState` | 1.00 | 807 |
| 2 | `lib/features/manager/presentation/widgets/finance_widget.dart::_FinanceWidgetState` | 1.00 | 668 |
| 3 | `lib/features/manager/presentation/widgets/student_funnel_editor.dart::_StudentFunnelEditorState` | 1.00 | 665 |
| 4 | `lib/features/manager/presentation/widgets/students_board_widget.dart::_StudentsBoardWidgetState` | 1.00 | 662 |
| 5 | `server/src/crm/commerce/subscription-lifecycle.service.ts::SubscriptionLifecycleService` | 1.04 | 1,350 |
| 6 | `lib/features/admin/presentation/widgets/schedule_reference_settings.dart::_ScheduleReferenceSettingsState` | 1.05 | 764 |
| 7 | `lib/features/manager/presentation/widgets/teacher_stats_widget.dart::_TeacherStatsWidgetState` | 1.09 | 1,074 |
| 8 | `lib/features/crm/presentation/client_card/preferred_schedule_editor.dart::_PreferredScheduleEditorState` | 1.12 | 668 |
| 9 | `lib/features/admin/presentation/widgets/staff_detail_dialog.dart::_StaffDetailDialogState` | 1.28 | 662 |
| 10 | `lib/features/crm/presentation/client_card/client_card.dart::_ClientCardState` | 1.70 | 620 |
| 11 | `lib/features/admin/presentation/widgets/create_lesson_dialog.dart::_CreateLessonDialogState` | 1.86 | 1,099 |
| 12 | `server/src/crm/crm.service.ts::CrmService` | 1.90 | 1,210 |
| 13 | `server/src/auth/auth.service.ts::AuthService` | 1.90 | 865 |
| 14 | `lib/features/manager/presentation/tasks/shared_task_editor.dart::_SharedTaskEditorState` | 2.02 | 790 |
| 15 | `server/src/messenger/messenger.service.ts::MessengerService` | 2.15 | 1,043 |
| 16 | `server/src/crm/finance.service.ts::FinanceService` | 2.34 | 815 |
| 17 | `server/src/crm/commerce/subscription-issue.service.ts::SubscriptionIssueService` | 2.47 | 1,008 |
| 18 | `lib/features/crm/presentation/client_card/subscription_issue_sheet.dart::_SubscriptionIssueFormState` | 2.56 | 1,115 |
| 19 | `lib/core/workspace/production_workspace_host.dart::_ProductionWorkspaceHostState` | 2.68 | 425 |
| 20 | `server/src/crm/schedule/lesson-command.service.ts::LessonCommandService` | 2.83 | 741 |
| 21 | `server/src/crm/schedule/schedule-plan.service.ts::SchedulePlanService` | 3.22 | 1,148 |
| 22 | `server/src/crm/schedule/lesson-transition.service.ts::LessonTransitionService` | 3.39 | 1,535 |
| 23 | `server/src/crm/student-funnel.service.ts::StudentFunnelService` | 4.04 | 775 |
| 24 | `server/src/crm/payroll.service.ts::PayrollService` | 4.79 | 1,178 |
| 25 | `server/src/profile/profile.service.ts::ProfileService` | 5.37 | 656 |
| 26 | `lib/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart::_ReferenceCatalogLifecycleDialogState` | 5.62 | 378 |

The queue is not executed by raw score alone. Every package is selected by
recoverable weighted deficit, production reachability, transaction risk, and
the ability to land rollback-safe semantic owners. `lesson_decision_flow.dart`
is also mandatory even though its large file contains several classes rather
than one RepoWise `god_class`: it scores `2.02`, spans 1,025 NLOC, has a
175-line/CCN-28 brain `build`, and carries 7,175 weighted-deficit points.

After every structural package the full production filter is rerun. Completion
requires the god-class count to reach zero, all replacement owners to satisfy
the per-owner floor, all remaining sub-7 files to be classified and remediated,
and the existing RepoWise/Sentrux/test gates to pass on the same indexed commit.

## Approved `25 -> 0` continuation baseline

The owner approved continuous execution of the complete remaining program on
2026-08-26. The exact indexed commit is `9963adb839ad`; the worktree is clean.
RepoWise's indexed dashboard reports 1,596 files, average health `6.70`, and
hotspot health `5.90`. A distinct live CLI scan reports 1,695 files, average
health `6.82`, and hotspot health `4.69`. These scopes remain separate in every
evidence manifest. Sentrux reports quality `5736`, depth `13`, acyclicity raw
`0`/score `10000`, and rules `2/2`.

The 25 production god owners carry `114,548` weighted-deficit points:
`54,801` in Flutter and `59,747` in the backend. Coverage is currently pinned
to production SHA `861d89d7`; backend source is byte-identical to that SHA, but
every package must generate or ingest fresh coverage before acceptance.

| Rank | Production owner | Health | NLOC | Max CCN | Deficit |
|---:|---|---:|---:|---:|---:|
| 1 | `server/src/crm/crm.service.ts` | 1.90 | 1,210 | 21 | 7,381 |
| 2 | `server/src/messenger/messenger.service.ts` | 1.74 | 1,043 | 16 | 6,529 |
| 3 | `server/src/crm/commerce/subscription-lifecycle.service.ts` | 3.44 | 1,350 | 14 | 6,156 |
| 4 | `lib/core/widgets/telegram/chat_info_dialog.dart` | 1.00 | 807 | 45 | 5,649 |
| 5 | `lib/features/crm/presentation/client_card/subscription_issue_sheet.dart` | 3.04 | 1,114 | 19 | 5,525 |
| 6 | `server/src/auth/auth.service.ts` | 1.68 | 865 | 11 | 5,467 |
| 7 | `server/src/crm/payroll.service.ts` | 3.42 | 1,178 | 23 | 5,395 |
| 8 | `lib/features/manager/presentation/widgets/teacher_stats_widget.dart` | 3.04 | 1,074 | 22 | 5,327 |
| 9 | `server/src/crm/schedule/lesson-transition.service.ts` | 4.58 | 1,535 | 36 | 5,250 |
| 10 | `server/src/crm/schedule/schedule-plan.service.ts` | 3.58 | 1,148 | 19 | 5,074 |
| 11 | `server/src/crm/finance.service.ts` | 2.09 | 815 | 9 | 4,817 |
| 12 | `lib/features/manager/presentation/widgets/finance_widget.dart` | 1.00 | 668 | 35 | 4,676 |
| 13 | `lib/features/crm/presentation/client_card/preferred_schedule_editor.dart` | 1.00 | 667 | 39 | 4,669 |
| 14 | `lib/features/manager/presentation/widgets/student_funnel_editor.dart` | 1.00 | 665 | 16 | 4,655 |
| 15 | `lib/features/admin/presentation/widgets/staff_detail_dialog.dart` | 1.04 | 662 | 30 | 4,608 |
| 16 | `lib/features/admin/presentation/widgets/schedule_reference_settings.dart` | 2.14 | 763 | 11 | 4,471 |
| 17 | `server/src/crm/commerce/subscription-issue.service.ts` | 3.60 | 1,008 | 18 | 4,435 |
| 18 | `lib/features/crm/presentation/client_card/client_card.dart` | 1.00 | 620 | 18 | 4,340 |
| 19 | `lib/features/manager/presentation/widgets/students_board_widget.dart` | 1.48 | 662 | 19 | 4,316 |
| 20 | `lib/features/manager/presentation/tasks/shared_task_editor.dart` | 3.24 | 790 | 22 | 3,760 |
| 21 | `server/src/crm/schedule/lesson-command.service.ts` | 2.93 | 741 | 13 | 3,757 |
| 22 | `server/src/profile/profile.service.ts` | 2.78 | 656 | 10 | 3,424 |
| 23 | `server/src/crm/student-funnel.service.ts` | 5.34 | 775 | 13 | 2,062 |
| 24 | `lib/core/workspace/production_workspace_host.dart` | 3.49 | 425 | 14 | 1,917 |
| 25 | `lib/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart` | 5.65 | 378 | 25 | 888 |

### Selection method and package topology

Packages are ranked by `weighted_deficit * structural_fraction`, where the
structural fraction excludes history-only and coverage-attribution deductions.
Dependency readiness is a veto, not a discount: a high-risk owner may wait for
a prerequisite, but it remains in the mandatory queue. The queue is re-ranked
after every accepted package against one exact indexed commit.

The default is one source god owner per package, producing 25 packages. Only
owners that share an indivisible characterization suite may be combined, so
the safe lower bound is 23 packages. Package 9 remains the previously approved
`subscription-lifecycle.service.ts` cut: despite `crm.service.ts` having the
larger raw deficit, lifecycle is the highest ready boundary with strong
transactional coverage and only four dependents.

Execution proceeds in these dependency waves:

1. Backend foundations: subscription lifecycle, CRM students, messenger,
   auth, payroll, scheduling, finance, subscription issue, profile, and funnel.
2. Scheduling moves shared command metadata to a neutral contract before the
   god owners land separately in transition, plan, then command order.
3. Flutter leaves: subscription issue, chat, teacher statistics, preferred
   schedule, finance, funnel editor, board, lifecycle, staff, references, and
   shared tasks.
4. Flutter hubs: `client_card.dart` only after its leaf editors; the production
   workspace host is last after all feature packages.

Backend prerequisites land before their presentation consumers:
messenger/profile before chat; payroll before teacher statistics; finance
before finance UI; funnel service before funnel editor/board; subscription
issue service before issue sheet, and issue sheet before Client Card.

### Per-package semantic contract

Every package extracts named domain or presentation owners with immutable
inputs and explicit callback/service interfaces. Original public files may
remain as compatibility facades only when they contain composition or
controller-facing delegation; they may not retain policy, persistence,
transaction callbacks, mutable god state, or copied decision logic. Existing
`part` families are converted to imported semantic collaborators when they
share private state; adding more part files is not an accepted split.

Backend transaction executors keep each complete transaction callback intact.
Expected versions, mutation identities, idempotency locks, preview-token
binding/currentness, deterministic lock order, audit/outbox writes, append-only
facts, RBAC, and resource scope remain in the same atomic boundary. Flutter
widgets continue through canonical services/providers and do not access the
database or Supabase directly.

### Per-package acceptance gate

A package is accepted only when all of the following hold on its final commit:

- the production god count decreases and no new production `god_class` or
  `brain_method` appears;
- every new semantic owner has max CCN `<=10` and targets health `>=7.0`;
  a lower headline is allowed only for evidenced history/co-change deductions
  with no live structural defect and truthful coverage;
- characterization and focused tests pass after every boundary, followed by
  the relevant full Flutter/backend suite, analyzer/build, and diff checks;
- RepoWise reports no new consumer break, cycle, or conformance violation and
  publishes exact SHA, file/NLOC denominator, coverage SHA, target metrics,
  portfolio delta, and change risk;
- Sentrux stays at quality `>=5736`, depth `<=13`, perfect acyclicity, and
  rules `2/2`; any root-cause regression blocks acceptance even when the
  aggregate score rises.

Each semantic boundary is a reversible commit. A failed package is reworked or
reverted in reverse commit order. No schema/data mutation belongs to this
program, and financial, lesson, payroll, reservation, audit, or outbox history
is never manually rewritten to repair a refactor.

## Package 9 verified outcome — subscription lifecycle

Package 9 is accepted at code commit `8ebbf32e03a4` over execution range
`8a38a57b..8ebbf32e`. Its reversible code commits are `ffd1fdb9`, `aa27e4ef`,
`9dec8c6d`, `34763488`, `829069d9`, `b5cdaa56`, and `8ebbf32e`. The production
recount moves `25 -> 24` `god_class` owners. The former
`SubscriptionLifecycleService` moves from health `3.44`, `1,350` NLOC, max CCN
`14`, and weighted deficit `6,156` to a transaction-free 72-NLOC facade at
health `7.39`, max CCN `1`, and deficit `44`, with no `god_class` or
`brain_method` finding.

The five semantic owners close as follows: command policy `7.95` / 187 NLOC /
CCN `5` / deficit `9`; replacement policy `9.05` / 258 / `8` / `0`;
cancellation policy `9.65` / 203 / `6` / `0`; replacement executor `8.15` /
475 / `8` / `0`; cancellation executor `8.15` / 484 / `8` / `0`. Shared
lifecycle types score `9.65` at 46 NLOC and CCN `1`. The split-owner deficit is
therefore `6,156 -> 53`, recovering `6,103` points; the mandatory god-owner
portfolio moves `114,548 -> 108,392` because the removed owner carried all
`6,156` god-owner points. No replacement owner is below `7.0`, and every owner
is at or below CCN `10`.

Backend verification passed twice: `225/225` suites and `1,567/1,567` tests in
`117.051 s`, then the same counts with coverage in `122.258 s`; typecheck
passed in `3.06 s`, and build passed in `6.50 s`. The first coverage attempt at
Node's default approximately 2-GB heap ended in an out-of-memory failure after
about `164.5 s`; the unchanged command passed with
`NODE_OPTIONS=--max-old-space-size=8192`. The generated LCOV SHA-256 is
`ea00521cffe08f4d4091d895af899e1d742bd9a4b9a72762a666f96faf75123e`,
`766,302` bytes and 428 report records. RepoWise resolved 407 files and reports
`84.47%` mapped lines / `61.83%` mapped branches at exact coverage commit
`8ebbf32e`; the seven Package 9 owner/type files aggregate to `363/390`
coverable lines (`93.08%`) and `190/304` branches (`62.50%`). File-level LCOV
attributes every changed owner; 26 changed coverable lines remain uncovered,
while the facade's 10 changed coverable lines are all covered. The per-test
change map separately attributes three guarding integration/module tests and
does not infer per-test attribution for newly added source files; that narrower
map is not substituted for the file-level LCOV evidence.

RepoWise's exact indexed dashboard at `8ebbf32e` has 1,609 files, average
health `6.74`, with module scores `server=7.07` and `lib=5.06`. The distinct
live CLI scan has 1,708 files, average health `7.02`, hotspot health `4.99`,
773 production-filter files, 243 below `7.0`, and exactly 24 production
`god_class` findings; these scopes are deliberately not combined. Package PR
risk is `1.31`, with no breaking change, consumer break, dependency cycle, or
conformance violation. Full-range change risk is `9.8`, probability `0.9813`,
percentile `98.0`, review priority `high`, classification `Elevated`, driven by
the intentionally broad 16-file semantic split; full tests close the predicted
downstream review surface.

The accepted executor exception is explicit: replacement and cancellation
`execute` remain complete atomic I/O owners at 196 and 195 lines respectively,
both health `8.15` and CCN `8`. Splitting either callback would weaken the
transaction/integrity boundary. Policy low-cohesion/DRY findings and facade
history/test-pair heuristics are accepted only because their exact health is
`>=7`, no live structural gate fails, and file-level coverage is present.

Sentrux rescans 2,433 files and closes at quality `5744`, depth `13` / score
`3810`, acyclicity raw `0` / score `10000`, equality `6331`, modularity `5411`,
redundancy `4792`, and rules `2/2`. Every root cause is at or above the Package
9 baseline (`5736`, `13/3810`, `10000`, `6310`, `5406`, `4777`).

The fresh Package 10 owner is `server/src/crm/crm.service.ts`: health `1.90`,
1,210 NLOC, max CCN `21`, and weighted deficit `7,381`. It is now dependency-
ready after the lifecycle foundation, has a paired test and no test-gap or
security signal, and ranks above messenger (`6,529`) and the remaining ready
backend/Flutter owners. Its 100% hotspot, six dependents, and 27 fixes in six
months raise the required characterization depth but do not veto readiness.

### Phase B: health completion after `god_class = 0`

Eliminating all 25 owners cannot by itself satisfy the approved health
contract. Their entire current deficit is about `0.37` points over the indexed
repository denominator, so the realistic indexed result is approximately
`6.90-7.03`, not `7.5`. Flutter starts at `5.06`; backend already meets its
module gate at `7.02`.

After the absolute `god_class = 0` gate, the same package process continues
over non-god production hotspots ranked by recoverable deficit. The current
front includes `client_card_student.dart`, `client_create_dialogs.dart`,
`client_payment_form.dart`, `schedule_widget_actions.dart`, and
`subscription-preview-token.ts`. Phase B ends only when Flutter is `>=7.0`,
backend remains `>=7.0`, combined production health is `>=7.5`, all remaining
sub-7 production files are classified, and the RepoWise/Sentrux/test gates pass
on one exact indexed commit.

The owner's full-program approval authorizes continuous task execution without
check-ins between packages. Work stops only for an irreversible/destructive
operation, a security-sensitive decision, an external side effect such as
merge/push/deploy, or a plan defect that leaves every path forward speculative.
