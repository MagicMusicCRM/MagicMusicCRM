# Teacher Detail Dialog Semantic Split Implementation Plan

**Goal:** Remove the `TeacherDetailDialog` god state object and its Dart part
cycle while preserving teacher editing, access, lifecycle, and payroll
contracts.

**Architecture:** Keep `TeacherDetailDialog` as the stable public shell. Move
pure input policy, local payroll state, payroll dialogs/history, and form
composition into independent semantic owners connected through typed values
and callbacks.

## 1. Lock the behavior and ownership contract

- Add failing tests for the intended pure model and payroll controller APIs.
- Add a structural boundary test that rejects `part`, caps the shell, and
  requires every semantic owner.
- Keep the existing payroll device flow and service request tests as external
  contract gates.

## 2. Extract the pure editor model

- Introduce `TeacherDetailInitialData` and public pure helpers for legacy
  levels/categories, profile fallback, date parsing, labels, and formatting.
- Replace private helpers in the shell and delete their duplicates from the
  legacy part.
- Run model and employment tests, analyze, Sentrux scan/rules, then commit.

## 3. Extract payroll state and commands

- Introduce `TeacherPayrollController` around the existing
  `MagicCrmService`, with explicit loading/error/mutating states and reload
  after every successful mutation.
- Move confirmation/edit forms into typed dialog functions/widgets.
- Verify expected-version forwarding, mutation reload, and error retention in
  direct tests; run Sentrux and commit state/dialog ownership separately.

## 4. Extract payroll and teacher presentation

- Move payroll block and histories into `TeacherPayrollSection` and
  `TeacherPayrollHistory` with RBAC passed explicitly.
- Move summary, credential controls, role row, identity fields, and employment
  composition into `TeacherDetailContent`.
- Add direct widget characterization for privileged and unprivileged roles;
  run focused tests, analyze, Sentrux, and commit each presentation boundary.

## 5. Close the public shell and verify

- Wire the semantic owners, keep save/access/lifecycle result behavior, and
  delete `teacher_detail_widgets.dart` plus all `part` directives.
- Require the shell to stay below 400 NLOC and prohibit payroll rendering or
  API mutation details there.
- Refresh RepoWise, record health/change risk, run Sentrux/rules, focused and
  full Flutter tests, analyze, formatting, and diff checks.
- Record the measured outcome in this package spec and the global recovery
  design, then re-rank the next production god file.
