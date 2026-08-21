# Create Lesson Dialog Safe Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `CreateLessonDialog` safer to change by fixing the current date-picker defect, extracting pure rules, isolating save orchestration, preventing stale async writes, and moving view construction out of the state owner without changing product behavior.

**Architecture:** Keep `CreateLessonDialog.show`, its adaptive route behavior, local form ownership, `MagicCrmService`, `magicApiClientProvider`, and `showLessonDecisionFlow` as the existing runtime. Extract only presentation-layer rules and view code; do not introduce a second lesson model, finance engine, provider, command path, or backend contract.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter widget/unit tests, RepoWise, Sentrux.

**Spec:** Owner-approved plan in the Codex task; governing product contract is the inline comment in `lib/features/admin/presentation/widgets/create_lesson_dialog.dart:20-24`.

## Global Constraints

- Preserve `CreateLessonDialog.show(BuildContext, ...) -> Future<bool?>`, desktop `showDialog`, mobile fullscreen route name `lesson-editor`, and every existing `ValueKey`.
- Preserve create ordering: validate draft, preview schedule constraints, then call the authoritative `createLessonRaw`; the backend remains the final transactional constraint check.
- Preserve edit ordering: require version, select reschedule/planned-settlement/correction, then use `showLessonDecisionFlow`; never add a direct edit write.
- Preserve typed `clientRef`, independent trial marker, create-time financial snapshot, read-only edit snapshot, group-edit behavior, draft retention after a 422 race, and the `_saving` double-submit guard.
- Keep UI text Russian and code/comments English. Do not change backend, database, migrations, deployment, or production data.
- One task per commit. Do not stage unrelated files. Run the focused tests after every task.

---

## Task 1: Restore a green date-picker baseline

**Files:**
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Create: `test/features/admin/presentation/widgets/create_lesson_dialog_test.dart`
- Reuse fixtures from: `test/features/v4/lesson_form_test.dart`

- [ ] RED: add a regression that opens the date picker while editing a lesson whose selected date is more than 30 days old. The test must fail on the current `initialDate < firstDate` assertion.
- [ ] GREEN: compute a date-only rolling lower bound and use the earlier of that bound and the selected lesson date as `firstDate`; do not clamp or replace `initialDate`.
- [ ] Verify the regression and both existing edit/group-edit scenarios.
- [ ] Run:

```powershell
flutter test test/features/admin/presentation/widgets/create_lesson_dialog_test.dart
flutter test test/features/v4/lesson_form_test.dart test/features/admin/create_lesson_student_search_test.dart
```

- [ ] Commit: `fix(lessons): allow editing older lesson dates`

## Task 2: Extract pure form rules

**Files:**
- Create: `lib/features/admin/presentation/widgets/lesson_form_rules.dart`
- Create: `test/features/admin/presentation/widgets/lesson_form_rules_test.dart`
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Modify only if sharing the compensation helper removes the verified duplicate: `lib/features/admin/presentation/widgets/lesson_decision_flow.dart`

- [ ] RED: add literal table-driven tests for compensation parsing/formatting, schedule equality across snake/camel lesson fields, timezone-normalized scheduled timestamps, and invalid percentage/money inputs.
- [ ] GREEN: move those calculations into pure functions. Keep existing API map keys and minor-unit strings; do not create another lesson or finance runtime model.
- [ ] Replace dialog calculations with calls to the pure functions without changing payloads or labels.
- [ ] Run:

```powershell
flutter test test/features/admin/presentation/widgets/lesson_form_rules_test.dart test/features/v4/lesson_form_test.dart
```

- [ ] Commit: `refactor(lessons): extract lesson form rules`

## Task 3: Split save orchestration

**Files:**
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Modify: `test/features/v4/lesson_form_test.dart`
- Modify when the focused contract belongs in the mirrored suite: `test/features/admin/presentation/widgets/create_lesson_dialog_test.dart`

- [ ] RED: retain or add focused tests for missing version, no-op edit, financial-only edit, create preview conflict, authoritative 422 race, double click, and successful create/edit close results.
- [ ] GREEN: reduce `_save` to the `_saving` guard, immutable input capture, validation, create/edit dispatch, and shared UI result handling.
- [ ] Extract private validation, create, edit, and error-result helpers. Preserve the exact backend call order and error semantics from Global Constraints.
- [ ] Run:

```powershell
flutter test test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/v4/lesson_form_test.dart
```

- [ ] Commit: `refactor(lessons): isolate lesson save flows`

## Task 4: Reject stale async form loads

**Files:**
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Modify: `test/features/admin/presentation/widgets/create_lesson_dialog_test.dart`

- [ ] RED: use controlled completers to return branch/client resource requests in reverse order and prove the older response currently overwrites the latest selection.
- [ ] GREEN: add small request revisions or identity guards for rooms, decision catalog, and subscriptions. Apply results only when mounted and still current for the requested branch/client.
- [ ] Keep the last valid draft and expose the existing user-facing error behavior; do not add cancellation dependencies or global state.
- [ ] Run:

```powershell
flutter test test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/v4/lesson_form_test.dart
```

- [ ] Commit: `fix(lessons): ignore stale lesson form loads`

## Task 5: Move view construction behind a library-private seam

**Files:**
- Modify: `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- Create: `lib/features/admin/presentation/widgets/create_lesson_dialog_view.dart`
- Modify: `test/features/admin/presentation/widgets/create_lesson_dialog_test.dart`
- Verify: `test/features/v4/lesson_form_test.dart`

- [ ] RED: add/retain route, key, mobile page-mode, desktop dialog, conflict inspector, snapshot, and validation-banner assertions that protect the current view contract.
- [ ] GREEN: use the repository's established `part` pattern and a library-private view extension/helper to move build-only sections out of the state owner. Keep async actions and mutable state ownership in `create_lesson_dialog.dart`.
- [ ] Preserve every existing key, label, callback, enabled condition, focus behavior, scroll controller, and adaptive layout.
- [ ] Run all focused gates:

```powershell
flutter test test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/v4/lesson_form_test.dart test/features/admin/create_lesson_student_search_test.dart
flutter analyze lib/features/admin/presentation/widgets/create_lesson_dialog.dart lib/features/admin/presentation/widgets/create_lesson_dialog_view.dart lib/features/admin/presentation/widgets/lesson_form_rules.dart test/features/admin/presentation/widgets/create_lesson_dialog_test.dart test/features/admin/presentation/widgets/lesson_form_rules_test.dart
repowise update --index-only
sentrux check
sentrux gate
```

- [ ] Acceptance: all focused tests and analysis pass, Sentrux rules pass, quality does not fall below `4725`, `_save` is at most 40 lines, and no new dependency cycle appears.
- [ ] Commit: `refactor(lessons): split lesson dialog view`
