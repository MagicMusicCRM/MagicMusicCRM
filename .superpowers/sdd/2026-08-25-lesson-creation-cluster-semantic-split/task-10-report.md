# Task 10 report: live lesson editor composition

## Status

Implementation and behavioral verification are complete. The public lesson
dialog now composes the typed Task 1-9 owners and the legacy god state/part file
is deleted. Task 10 is **not complete at the package gate** because Sentrux
quality is `5723`, below the required `5748`; depth, acyclicity, and both rules
pass. The owner ruled that the implementation must be committed for independent
review without metric gaming or unrelated cleanup.

## RED -> GREEN

- Architecture RED: the new acceptance test found the legacy `part` link, the
  `_CreateLessonDialogState` symbol, old workflow helpers, a shell over 320
  lines, and the live `create_lesson_dialog_view.dart`. GREEN: the view is
  deleted, the state is `_LessonEditorDialogState`, forbidden symbols are
  absent, and the formatted shell is 317 physical lines.
- Search seam RED: the direct controller contract had no query-aware CRM
  adapter. GREEN: `LessonEditorDataController.searchClients(query)` trims and
  forwards `q` with `limit: 50` through `MagicCrmService.searchClientRefs`,
  returning immutable typed client metadata; the shell never calls the API or
  service directly for search.
- Composition characterization RED: typed catalog mapping lost branch default
  duration, defaults still lived in the legacy shell, and the new view lacked
  retryable load-error rendering. GREEN: catalog duration is preserved, policy
  owns defaults, and `LessonEditorView` renders the legacy error/retry state.
- Structural RED after first wiring: Sentrux reported quality `5669` and depth
  `14`. The proven longest path crossed `searchable_picker_field.dart ->
  searchable_select.dart`. Moving only dependency-free `SearchableSelectItem`
  to the picker, with a compatibility re-export from the old import, restored
  depth `13`. A typed schedule-model re-export then removed six redundant
  editor imports without changing behavior.

## Resulting boundaries

- `CreateLessonDialog` keeps its constructor, static `show`, route/dialog
  adaptation, caller contract, Russian titles, and return values unchanged.
- `_LessonEditorDialogState` owns only collaborator composition and Flutter UI
  lifecycle: `setState`, focus/scroll, `showDialog`, `ScaffoldMessenger`,
  `Navigator`, and `scheduleNavigationProvider`. It contains no
  `MagicApiClient`, direct client-search service call, or duplicated financial,
  validation, schedule, payload, preview, or save workflow.
- One persistent `LessonEditorSaveFlow` instance serves every submit. Busy,
  invalid, preview fail-open, constraint fail-closed, authoritative 422,
  create success, edit decision, cancellation, and draft-preservation outcomes
  retain the live behavior.
- Typed data ownership preserves actor-scoped remote search, latest-query
  behavior, preloaded/fresh overlap metadata, stale branch/client request
  rejection, subscription clearing, and all immutable reference patches.
- Presentation owners remain props-only. Constraint content renders in
  `LessonConstraintDialog`, while every navigation and dialog callback stays
  in `_LessonEditorDialogState` as required by the Task 9 guard.

## Verification

- Architecture acceptance: `1/1` pass.
- Task 10 focused cluster, including the paired model contract: `67/67`
  pass.
- Task 1-9 direct owner cluster: `141/141` pass.
- Task 9 presentation guard: `19/19` pass; core picker/select direct tests:
  `8/8` pass.
- Fresh full Flutter suite after the final production change, with truthful
  coverage enabled: `1097/1097` pass in `3m48s`; RepoWise ingested 336 exact
  files at 71.5% lines without adding a tracked artifact. The final direct
  model coverage refresh also passed `3/3`.
- Targeted analyzer: no issues. Formatter stable. `git diff --check` clean.
  Forbidden `part`, old state/helper, provider, and direct API scan: zero hits.
  Caller scan found 16 live constructor/static-show uses compiling in the full
  suite.

## RepoWise health and change risk

RepoWise is current at the implementation commit. Health / max CCN for the new
semantic owners: decision models `9.73/3`, form `7.97/10`, controller `8.37/10`,
sections `9.53/10`; editor models `7.05/9`, data `7.28/9`, policy `7.66/9`,
view `7.71/9`, initial mapper `8.22/5`, schedule section `8.64/10`, financial
section `9.10/8`, feedback `9.19/4`, schedule controller `9.45/5`, save flow
`9.63/4`. No new owner has a god/brain finding. The shell is bounded at 317
physical lines / 300 NLOC; its lower aggregate `4.18` and max CCN `12` remain
isolated to UI lifecycle/history, while the extracted props-only view is below
the CCN ceiling.

The Task 9 participant owner is the one explicit no-structure exception:
`5.57/10` with 85.53% coverage. Task 10 changes only remove its redundant
import; RepoWise's lower headline is driven by history/coverage scoring, not a
new function or complexity regression. Shared picker is exactly unchanged at
its approved `6.33/12` baseline with 95.28% coverage; the compatibility select
retains its pre-existing `2.25/17` baseline rather than widening this task into
shared-widget cleanup. Final change risk is Elevated / high priority at the
85.5th percentile (`9.5`, probability `94.92%`), driven by the intentional
`1,300` additions / `1,858` deletions across 26 files; its ingested map names
six impacted tests.

## Sentrux gate

- Final: quality `5723`; depth raw `13`; acyclicity `10000` with raw `0`;
  equality `6318`; modularity `5407`; redundancy `4717`; `4661` import edges;
  `2731` cross-module edges; rules `2/2`; `session_end` passes as stable.
- Against Task 9: modularity `5393 -> 5407`, equality `6311 -> 6318`, edges
  `4662 -> 4661`, and cross-module edges `2742 -> 2731` improve. Only
  redundancy regresses `4755 -> 4717` after deleting the old implementation.
- Sentrux's exact current redundancy ratio is `1343 / 2542 =
  0.528324154209284` (`dead + duplicate` functions divided by total
  functions). Reaching overall `5748` with the other current subscores would
  require redundancy around `4824`. Removing private functions also removes
  them from the denominator, requiring roughly 58 waste removals; making
  helpers public, adding denominator-only functions, or altering bodies solely
  to evade duplicate hashes was rejected as metric gaming.
- Package threshold **NOT MET: best `5723` versus required `5748`**. Reducing
  the unrelated teacher-chain depth or doing repository-wide dead/duplicate
  cleanup was explicitly kept outside Task 10 scope. Independent review must
  decide a separate cleanup; this report does not mark Task 10 complete.

## Changed files

Production/core:

- `lib/core/widgets/searchable_picker_field.dart`
- `lib/core/widgets/searchable_select.dart`
- `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- `lib/features/admin/presentation/widgets/create_lesson_dialog_view.dart`
  (deleted)
- `lib/features/admin/presentation/widgets/lesson_decision/lesson_decision_models.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_data_controller.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_decision_policy.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_feedback.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_initial_mapper.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_models.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_save_flow.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_schedule_controller.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_editor_view.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_participant_section.dart`
- `lib/features/admin/presentation/widgets/lesson_editor/lesson_schedule_section.dart`

Tests/report:

- `test/core/widgets/searchable_picker_field_test.dart`
- `test/features/admin/create_lesson_student_search_test.dart`
- `test/features/admin/lesson_creation_architecture_test.dart` (new)
- `test/features/admin/lesson_editor_data_controller_test.dart`
- `test/features/admin/lesson_editor_decision_policy_test.dart`
- `test/features/admin/lesson_editor_models_test.dart` (new)
- `test/features/admin/lesson_editor_sections_test.dart`
- `test/features/admin/presentation/widgets/create_lesson_dialog_test.dart`
- `.superpowers/sdd/2026-08-25-lesson-creation-cluster-semantic-split/task-10-report.md`

## Concern

The open package concern is the explicit Sentrux quality shortfall above. The
participant's lower history/coverage score is recorded as an unchanged-structure
Task 9 exception. All functional, architectural, analyzer, formatting, depth,
cycle, and rule gates are green; no unrelated user changes or `progress.md`
edits are included.
