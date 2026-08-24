# Recurring Schedule Plan Health Cut Implementation Plan

> **Execution:** Work sequentially in the current branch. Preserve unrelated
> changes and commit every ownership boundary independently.

**Goal:** Turn `RecurringSchedulePlanSection` into a thin composition shell by
extracting pure constraint interpretation, review UI, plan presentation, and
mutation flows without changing scheduling behavior.

**Architecture:** Keep `RecurringSchedulePlanController` and
`MagicCrmService` as the canonical state/API boundary. New presentation files
communicate through typed values and callbacks. Pure preview interpretation has
no Flutter context, provider, service, or network dependency.

**Tech stack:** Flutter, Dart, Riverpod, flutter_test, RepoWise, Sentrux

**Spec:**
`docs/superpowers/specs/2026-08-25-production-code-health-recovery-design.md`

## Global constraints

- Preserve every existing widget key, Russian user-facing string, route, DTO,
  mutation identity, expected version, effective date, and preview-before-
  commit sequence.
- Do not add a second state model, direct Supabase/database access, or a new
  scheduling API wrapper.
- Do not move tests solely to improve RepoWise filename pairing.
- Keep new production files below 500 NLOC where practical and keep each class
  focused on one reason to change.
- Run the focused widget suite after every production extraction.
- After each structural commit run Sentrux scan/rules and
  `repowise update --index-only`.

## Baseline

RepoWise at `dd31e2a81c37`:

```text
file score: 1.0
file NLOC: 1947
weighted deficit: 13629
share of repository gap: 2.8%
max CCN: 20
_RecurringSchedulePlanSectionState: ~931 lines / 28 methods
```

The capability-grouped behavior suite is:

```text
test/features/schedule/recurring_schedule_plan_section_test.dart
```

---

## Task 1: Calibrate Flutter coverage and freeze behavior

**Files:**

- Generated locally: `coverage/lcov.info` (must remain uncommitted)
- Verify: `test/features/schedule/recurring_schedule_plan_section_test.dart`

1. Run the focused baseline:

   ```powershell
   flutter test test/features/schedule/recurring_schedule_plan_section_test.dart
   ```

   Expected: all current recurring-plan widget tests pass.

2. Generate truthful Flutter line coverage:

   ```powershell
   flutter test --coverage
   repowise coverage add coverage/lcov.info
   repowise coverage status
   ```

   Expected: LCOV is ingested for production Dart files. Do not commit the
   generated report.

3. Record fresh RepoWise health for the target and module. Treat missing
   per-test contexts as unknown, not as an untested finding.

4. Verify the worktree contains no generated coverage artifact intended for
   commit:

   ```powershell
   git status --short
   ```

---

## Task 2: Extract the pure constraint interpreter

**Files:**

- Create:
  `lib/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart`
- Create:
  `test/features/schedule/schedule_plan_constraint_interpreter_test.dart`
- Modify:
  `lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart`

1. Add failing unit tests for:

   - analyzer conflicts grouped by fingerprint and affected rows;
   - legacy row failures grouped by row/code/resource;
   - participant-label projection for client overlap;
   - suggestion ranking and eight-item cap;
   - preview-row to draft-row mapping;
   - positive/negative time offsets across midnight.

2. Run the new test and verify RED because the interpreter does not exist:

   ```powershell
   flutter test test/features/schedule/schedule_plan_constraint_interpreter_test.dart
   ```

3. Implement immutable `SchedulePlanConstraintIssue`,
   `SchedulePlanSuggestion`, and `SchedulePlanConstraintInterpreter`. Move the
   existing parsing and mapping logic without semantic rewrites.

4. Route the existing row-review state through the interpreter. Keep rendering
   and mutation state in the original file for this task.

5. Verify:

   ```powershell
   dart format lib/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart test/features/schedule/schedule_plan_constraint_interpreter_test.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart
   flutter test test/features/schedule/schedule_plan_constraint_interpreter_test.dart test/features/schedule/recurring_schedule_plan_section_test.dart
   flutter analyze
   git diff --check
   ```

6. Commit:

   ```powershell
   git add -- lib/features/crm/presentation/client_card/schedule_plan_constraint_interpreter.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart test/features/schedule/schedule_plan_constraint_interpreter_test.dart
   git commit -m "refactor(schedule): extract plan constraint interpreter"
   ```

7. Run Sentrux scan/health/rules and `repowise update --index-only`.

---

## Task 3: Extract the rows-review workspace

**Files:**

- Create:
  `lib/features/crm/presentation/client_card/schedule_plan_rows_review.dart`
- Modify:
  `lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart`
- Modify only if direct ownership assertions are needed:
  `test/features/schedule/recurring_schedule_plan_section_test.dart`

1. Add one ownership test that opens the review sheet and proves add/edit,
   preview failure, suggested fix, and successful submit still use the existing
   widget keys.

2. Move `_SchedulePlanRowsReview` and its state into the new file as
   `SchedulePlanRowsReview`. It may depend on design tokens, entity navigation,
   preferred-schedule editor, and the pure interpreter. It must not depend on
   `MagicCrmService` or providers.

3. Replace the two shell call sites with `SchedulePlanRowsReview`. Do not copy
   the implementation or leave a compatibility wrapper.

4. Verify:

   ```powershell
   dart format lib/features/crm/presentation/client_card/schedule_plan_rows_review.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart test/features/schedule/recurring_schedule_plan_section_test.dart
   flutter test test/features/schedule/schedule_plan_constraint_interpreter_test.dart test/features/schedule/recurring_schedule_plan_section_test.dart
   flutter analyze
   git diff --check
   ```

5. Commit:

   ```powershell
   git add -- lib/features/crm/presentation/client_card/schedule_plan_rows_review.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart test/features/schedule/recurring_schedule_plan_section_test.dart
   git commit -m "refactor(schedule): extract plan review workspace"
   ```

6. Run Sentrux scan/health/rules and `repowise update --index-only`.

---

## Task 4: Extract recurring-plan presentation

**Files:**

- Create:
  `lib/features/crm/presentation/client_card/recurring_schedule_plan_view.dart`
- Modify:
  `lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart`
- Verify:
  `test/features/schedule/recurring_schedule_plan_section_test.dart`

1. Add or retain assertions for loading, initial error/retry, empty fallback,
   active/ended grouping, responsive add action, tray next/back/retry, lesson
   navigation, and duplicate-open guarding.

2. Move plan cards, plan rows, tags, ended-plan expansion, lesson tray, tray
   tiles, fallback tray, and opening-progress ownership to
   `RecurringSchedulePlanView`.

3. Give the view explicit inputs: controller snapshot, `canWrite`,
   `canCreatePlan`, fallback lessons, and callbacks for create/edit/end/open.
   It may receive `MagicCrmService` explicitly for tray pagination; it must not
   read providers or own plan mutations.

4. Keep `RecurringSchedulePlanSection` responsible for controller lifecycle and
   composition only. Remove the moved methods and classes; do not delegate back
   into the old file.

5. Verify and commit:

   ```powershell
   dart format lib/features/crm/presentation/client_card/recurring_schedule_plan_view.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart
   flutter test test/features/schedule/recurring_schedule_plan_section_test.dart
   flutter analyze
   git diff --check
   git add -- lib/features/crm/presentation/client_card/recurring_schedule_plan_view.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart
   git commit -m "refactor(schedule): extract recurring plan view"
   ```

6. Run Sentrux scan/health/rules and `repowise update --index-only`.

---

## Task 5: Extract mutation workflows and end form

**Files:**

- Create:
  `lib/features/crm/presentation/client_card/schedule_plan_mutation_flow.dart`
- Create:
  `lib/features/crm/presentation/client_card/schedule_plan_end_form.dart`
- Modify:
  `lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart`
- Verify:
  `test/features/schedule/recurring_schedule_plan_section_test.dart`

1. Preserve assertions for create/edit, group participants, constraint preview,
   expected version, effective date, idempotent mutation identity, end reason,
   impact preview, commit, reload, success toast, and localized error handling.

2. Move the end widget unchanged to `SchedulePlanEndForm`. It owns form-local
   date/reason/preview/loading state only.

3. Implement `SchedulePlanMutationFlow` as presentation orchestration with
   explicit constructor dependencies: `MagicCrmService`, `MagicApiClient`,
   branches, subscriptions, group members, entity IDs, subject name, and
   default branch. It returns a typed committed/cancelled result and throws
   service errors to the shell.

4. Move reference loading, draft conversion, API row serialization, slot-time
   calculation, create, row edit, participant edit, and end-sheet orchestration
   into the flow. It must not own controller reload, toast rendering, or shared
   Riverpod state.

5. Reduce `_RecurringSchedulePlanSectionState` to controller lifecycle,
   eligibility, flow invocation, reload/toast, and view composition. Target:
   less than 300 lines and no method above CCN 10.

6. Verify and commit:

   ```powershell
   dart format lib/features/crm/presentation/client_card/schedule_plan_mutation_flow.dart lib/features/crm/presentation/client_card/schedule_plan_end_form.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart
   flutter test test/features/schedule/schedule_plan_constraint_interpreter_test.dart test/features/schedule/recurring_schedule_plan_section_test.dart
   flutter analyze
   git diff --check
   git add -- lib/features/crm/presentation/client_card/schedule_plan_mutation_flow.dart lib/features/crm/presentation/client_card/schedule_plan_end_form.dart lib/features/crm/presentation/client_card/recurring_schedule_plan_section.dart
   git commit -m "refactor(schedule): extract plan mutation workflows"
   ```

7. Run Sentrux scan/health/rules and `repowise update --index-only`.

---

## Task 6: Full acceptance and re-ranking

1. Run the full Flutter gate:

   ```powershell
   flutter test
   flutter analyze
   git diff --check
   ```

2. Run fresh Sentrux scan, health, and architectural rules. Acceptance:

   ```text
   acyclicity.raw = 1
   rules pass = true
   quality_signal >= baseline 4974
   ```

3. Refresh RepoWise and inspect all changed production files:

   ```powershell
   repowise update --index-only
   ```

   Confirm `indexed_commit` equals `HEAD`, `index_behind=false`, the original
   file and state-class spans shrink materially, no new cycle/consumer gap is
   reported, and the Flutter module score moves upward.

4. Use RepoWise `get_change_risk` for the design-base through final HEAD. Run
   every coverage-backed impacted test; when no per-test map exists, retain the
   full Flutter suite as the authoritative gate.

5. Record before/after evidence in the spec or a short verification appendix,
   commit it separately, then re-rank the global portfolio. The next package is
   chosen by fresh weighted deficit, not by the old list.

## Rollback

Revert commits in reverse order: mutation flow, view, review workspace, then
constraint interpreter. Because the package changes no API, schema, migration,
environment, or production data, rollback requires no database action.
