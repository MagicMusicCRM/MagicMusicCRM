# Lesson Creation Cluster Semantic Split Design

**Date:** 2026-08-25

**Status:** Approved by the owner on 2026-08-25

## Context

The lesson creation and decision UI is the next production-first package in the
approved code-health recovery program. At indexed commit `d1ce1b443b8d`:

- `create_lesson_dialog.dart` has RepoWise health `1.00`, 1,099 NLOC, max CCN
  `35`, weighted deficit `7,693`, 15 bug fixes in six months, nine dependents,
  and a 996-line/61-method `_CreateLessonDialogState` god class;
- `create_lesson_dialog_view.dart` has health `8.05`, 746 NLOC, and one
  494-line/CCN-69 `_buildLessonDialogView` method;
- `lesson_decision_flow.dart` has health `1.00`, 1,025 NLOC, max CCN `28`,
  weighted deficit `7,175`, eight static dependents, and a 175-line/CCN-28
  brain `build` method;
- `lesson_form_rules.dart` is already a narrow 60-NLOC pure boundary with
  health `8.80` and remains the canonical shared parsing/formatting owner.

The two structurally deficient owners carry `14,868` weighted-deficit points.
The current Flutter `part` relationship also makes the view depend on every
private field and method of the state class, so visual edits and workflow edits
cannot evolve independently.

The focused characterization baseline passes `52/52` tests across the dialog,
student search, form rules, decision flow, and lesson form suites. Device tests
also exercise mobile/desktop surfaces, create/edit flows, settlement, cancel,
and reschedule. RepoWise filename pairing under-reports some of this coverage;
the live tests are authoritative.

## Goal and acceptance contract

Replace both god-like owners with cohesive, directly tested semantic owners
without changing lesson routes, payloads, product rules, or user-visible
behavior. The package is accepted only when all of the following are true:

- `_CreateLessonDialogState` and the decision brain method no longer exist;
- the `part`/`part of` dependency cycle is deleted;
- the stable public entry points remain available at their current import
  paths, but contain composition/exports rather than compatibility delegates;
- each new structural owner targets RepoWise health `>= 7.0`, max CCN `<= 10`,
  and no god/brain finding; any lower shell score must be proven to contain only
  historical churn or coverage attribution, not current structural debt;
- combined weighted deficit falls by at least `85%`, with no Sentrux quality,
  depth, acyclicity, or architecture-rule regression;
- all focused tests, full Flutter tests, `flutter analyze`, RepoWise change
  risk, and Sentrux gates pass on one indexed commit.

## Public compatibility boundary

The following source contracts stay stable because production, widget,
integration, and device tests consume them directly:

- `CreateLessonDialog`, its constructor, `CreateLessonDialog.show`, adaptive
  desktop/mobile presentation, and `Future<bool?>` result semantics;
- `LessonDecisionOperation` and its five variants;
- `LessonDecisionCatalogItem`, `LessonDecisionCatalog`,
  `LessonDecisionPreview`, and `LessonDecisionParticipant`;
- `LessonDecisionController` behavior and `showLessonDecisionFlow`;
- current widget keys, Russian copy, route name `lesson-editor`, and dialog
  close/result behavior.

`create_lesson_dialog.dart` remains the real public composition shell.
`lesson_decision_flow.dart` remains the real decision entry module and exports
the public models/controller from their semantic files. Neither file may retain
the old implementation as forwarding methods or duplicate an extracted owner.

## Considered approaches

### 1. Extract a few long methods

Moving `_loadData`, `_save`, and `build` helpers would reduce individual CCN,
but the same state class would still own async reference loading, financial
policy, schedule analysis, command orchestration, controllers, and rendering.
The private `part` cycle and shotgun-change surface would remain. Rejected.

### 2. Replace the state with one `LessonEditorController`

A single controller would make the widget smaller but would merely move the god
class into a new file. It would also risk mixing reusable Riverpod state with a
short-lived modal draft. Rejected.

### 3. Semantic cluster split — selected

Create typed draft/reference models and narrow collaborators for initial
mapping, reference data, decision policy, schedule analysis, save commands,
decision commands, and view sections. The dialog remains the lifetime and
composition owner. This removes the god owner instead of hiding it.

## Target architecture

### Typed lesson editor state

`lesson_editor/lesson_editor_models.dart` owns immutable value types:

- `LessonClientRef` and typed individual/group/lead identity;
- `LessonEditorDraft` for schedule, participant, trial, completion, settlement,
  compensation, funding, subscription, and reason selections;
- `LessonEditorReferenceState` for teachers, clients, branches, rooms,
  subscriptions, and the server decision catalog;
- `LessonEditorSnapshot` for frozen edit facts and financial baselines;
- typed load/save/validation outcomes instead of stringly state flags.

`lesson_editor/lesson_editor_initial_mapper.dart` is the only owner of legacy
map normalization. It maps constructor arguments and edit payload aliases into
the typed draft/snapshot, including Moscow/UTC conversion, frozen group/client
identity, old lesson dates, and immutable trial state.

### Reference loading and revision safety

`lesson_editor/lesson_editor_data_controller.dart` depends on the existing
`MagicCrmService`. It owns:

- initial teacher/client/branch and selected-client resolution;
- branch-scoped rooms and lesson-decision catalog loading;
- student subscription loading;
- client/branch cascading defaults;
- request revision tokens that discard stale rooms, catalog, subscription, and
  initial-load continuations.

It owns no `BuildContext`, Riverpod `Ref`, `TextEditingController`, navigation,
or widget state. It returns immutable reference/draft patches for the shell to
apply only while mounted.

### Decision policy and payloads

`lesson_editor/lesson_editor_decision_policy.dart` owns pure selection and
validation rules:

- allowed catalog choices and configured duration defaults;
- legal combinations of settlement, teacher compensation, funding source, and
  subscription;
- compensation-value parsing through `lesson_form_rules.dart`;
- snapshot-lock/no-op/edit validation;
- create payload and edit decision request construction.

The policy never calculates authoritative money, remaining subscription
capacity, teacher payroll, or settlement facts. Those remain backend results.
It only validates and serializes the user's three independent decisions.

### Schedule analysis and network boundary

The presentation-layer `schedule_conflicts_api.dart` is removed. Its immutable
analysis models move to `core/models/lesson_schedule_analysis.dart`, and the
existing `MagicCrmSchedule` extension receives methods for:

- lesson constraint analysis;
- authoritative constraint preview;
- raw V4 lesson creation;
- lesson-decision catalog, preview, and commit calls.

`lesson_editor/lesson_editor_schedule_controller.dart` depends only on
`MagicCrmService`, turns a typed draft into an analysis request, and applies a
typed suggestion patch. Widgets no longer call `MagicApiClient` directly.
Existing non-dialog consumers migrate to the canonical model/service imports;
no legacy API extension remains.

### Save orchestration

`lesson_editor/lesson_editor_save_flow.dart` owns command sequencing and typed
outcomes:

- prevent duplicate in-flight saves;
- validate and build a create/edit command;
- run create constraint preview;
- preserve the current fail-open preview transport behavior because the
  authoritative create transaction repeats all constraints;
- convert authoritative `422` violations into a keep-draft result;
- emit a `LessonDecisionRequest` for edits without owning `BuildContext`;
- preserve expected version, idempotency, signed preview identity, and the
  create/edit success result.

The dialog shell launches violation and decision surfaces from typed outcomes,
owns navigation/result feedback, and never reproduces command logic.

### Lesson editor presentation

Normal Dart imports replace the `part` relationship. The presentation is split
into bounded widgets under `lesson_editor/`:

- `lesson_editor_view.dart` — adaptive dialog/page shell and section ordering;
- `lesson_participant_section.dart` — client/group, branch, room, teacher;
- `lesson_schedule_section.dart` — date, time, duration, analyzer, suggestions;
- `lesson_financial_section.dart` — completion, settlement, compensation,
  reason, funding, subscription, immutable snapshot preview;
- `lesson_editor_feedback.dart` — validation, constraint links, errors, and
  actions.

Sections receive typed values and callbacks. They do not read private shell
state, call services, mutate providers, or navigate. Constraint links emit an
intent; the composition shell performs `scheduleNavigationProvider` updates
and closes the appropriate surface.

### Lesson decision flow

The decision module is split into:

- `lesson_decision/lesson_decision_models.dart` — public operation, catalog,
  preview, participant, request, and form-draft types;
- `lesson_decision/lesson_decision_controller.dart` — catalog/preview/commit,
  group participant normalization, expected-version recovery, and signed
  preview identity through `MagicCrmService`;
- `lesson_decision/lesson_decision_form.dart` — bounded modal form lifecycle,
  text-controller ownership, preview/commit orchestration, and recovery state;
- `lesson_decision/lesson_decision_sections.dart` — settlement, group override,
  completed-reschedule notice, summary, preview, error, and action widgets.

The small `lesson_decision_flow.dart` entry constructs the controller and opens
the adaptive surface. Completed reschedule still forces `free_lesson/none` and
shows consequences; group settlement still uses the common decision plus
sparse participant overrides from the frozen participant snapshot.

## Data and command flow

```text
CreateLessonDialog
  -> LessonEditorInitialMapper -> LessonEditorDraft/Snapshot
  -> LessonEditorDataController -> MagicCrmService -> reference state
  -> LessonEditorView/sections  -> typed edit intents
  -> LessonEditorScheduleController -> authoritative analysis
  -> LessonEditorSaveFlow
       -> create preview -> authoritative create
       -> edit request -> showLessonDecisionFlow
            -> LessonDecisionController -> preview token -> commit
```

There is one Flutter runtime, one CRM service boundary, and one backend lesson
model. This cut adds no parallel repository, provider graph, schedule engine,
financial model, endpoint, migration, or database access.

## Preserved product and transaction invariants

- Backend authorization and resource scope remain authoritative; hidden or
  disabled controls do not send requests.
- Client/group identity, frozen participants, immutable trial marker, and
  completed facts remain locked on edit.
- Schedule edits change only time, duration, teacher, branch, and room; no-op
  edits are rejected before preview.
- Lesson creation keeps three independent decisions: settlement type, teacher
  compensation rule, and client funding source; subscription additionally
  requires its id, while `none` remains legal only for zero-charge settlement.
- Preview suggestions use the same authoritative schedule engine; create and
  commit transactions recheck hard constraints.
- Reschedule/cancel/settle/planned-settlement/correction preserve expected
  version, idempotency, signed preview, stale recovery, transaction, audit,
  outbox, reservation, and append-only financial facts.
- Preview transport failure before create remains non-blocking; authoritative
  create failure remains blocking and keeps the draft open.
- UI text remains Russian and the Deep Charcoal & Sophisticated Gold theme and
  current accessibility/widget keys remain unchanged.

## Test strategy

Every implementation step follows red-green-refactor. Existing tests remain
behavior gates, and new direct tests pair with the extracted owners:

- initial mapper tests cover legacy aliases, client/group/lead mapping, frozen
  snapshot, trial, Moscow/UTC, and old-date edit behavior;
- data-controller tests cover all four stale-request guards and branch/client
  cascade defaults;
- decision-policy tests cover the validation matrix, independent choices,
  funding defaults, compensation parsing, payloads, and no-op edit detection;
- schedule/save tests cover analysis, suggestion patches, preview fail-open,
  authoritative violations, double-submit, create payload, and edit request;
- decision controller/form/section tests cover preview-before-commit, signed
  identity, stale recovery, all operations, group overrides, forced completed
  reversal, adaptive surfaces, keys, and errors.

Focused tests run after each cut. Structural checkpoints also run `flutter
analyze`, `git diff --check`, `repowise update --index-only`, RepoWise health
and risk, plus Sentrux rescan/health/rules. The final package runs the complete
Flutter suite and a fresh full production health re-ranking.

## Delivery and rollback

The implementation lands as independent commits: typed models/mapper, canonical
CRM API boundary, data controller, decision policy, schedule/save flows,
decision models/controller, decision form/sections, editor sections, shell
wiring and old-file deletion, direct owner tests, and evidence.

Each commit must compile and pass its focused tests. No production deploy,
schema change, data migration, or history rewrite is part of the package.
Rollback is normal reverse-order Git revert; backend and persisted lesson facts
need no repair because external contracts and data semantics do not change.
