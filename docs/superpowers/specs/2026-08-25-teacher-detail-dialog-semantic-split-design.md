# Teacher Detail Dialog Semantic Split

## Context

`lib/features/admin/presentation/widgets/teacher_detail_dialog.dart` is the
next production-first Flutter god-file target: RepoWise health `1.00`, `1,158`
NLOC, max CCN `19`, weighted deficit `8,106`, four bug fixes, 31 co-change
partners, and change entropy in percentile `96.5`. Its state object mixes
teacher draft normalization, employment validation, access and lifecycle
orchestration, versioned payroll commands, correction dialogs, history
rendering, summary metrics, and the complete form layout.

The current `part`/`part of` relationship with
`teacher_detail_widgets.dart` also creates an explicit dependency cycle. The
production dialog has one device-level payroll test and service contract
coverage, but no direct unit ownership for its legacy normalization, local
payroll state, or RBAC presentation boundaries.

## Decision

Split the dialog into independent Dart libraries with these responsibilities:

- `teacher_detail_model.dart` owns pure input normalization, legacy
  multi-value/date compatibility, display labels, number/date formatting, and
  the immutable initial editor model.
- `teacher_payroll_controller.dart` owns local payroll loading, version state,
  and versioned mutations through the existing `MagicCrmService` port.
- `teacher_detail_save_command.dart` owns normalized update payloads and the
  salary/rate version-and-reason preparation policy.
- `teacher_detail_access_flow.dart` owns credential loading and provision
  orchestration through an injected dialog callback.
- `teacher_payroll_dialogs.dart` and `teacher_payroll_entry_dialogs.dart` own
  typed confirmation/edit results and the payroll reason, payout, rate,
  deletion, and bonus/deduction dialogs. Route-owned text controllers are
  disposed by `teacher_payroll_dialog_controller_owner.dart` only after the
  animated dialog route unmounts.
- `teacher_payroll_history.dart` owns rate and payout history presentation and
  delegates permitted actions through explicit callbacks.
- `teacher_payroll_section.dart` owns payroll presentation orchestration and
  binds dialogs to the local controller.
- `teacher_detail_content.dart` owns the summary, credential affordances,
  identity fields, access-role row, and employment form composition.
- `teacher_detail_dialog.dart` remains the public shell and owns only editor
  lifetime, bounded command coordination, UI adapters, and dialog result
  semantics.

All files use normal imports. The legacy `teacher_detail_widgets.dart` part is
deleted, removing the cycle instead of renaming it.

## Preserved invariants

- Salary or rate changes require a successfully loaded payroll snapshot, its
  current aggregate version, and a non-empty reason before `updateTeacher`.
- Payout/rate corrections keep `expectedVersion`, reason text, existing API
  paths, post-mutation reload, and user-facing error mapping.
- Only `director` and `system_admin` see credential management and payroll
  history mutation controls; hidden actions never issue a request.
- Teacher cards remain saveable without an application account. Existing
  accounts first fetch current credentials before the provision dialog.
- Lifecycle changes stay in the canonical preview/commit dialog, and an
  archived teacher cannot be edited or reprovisioned.
- Names retain the profile fallback and first-token/remaining-tokens split.
  Levels/categories continue to read plural lists and legacy comma/semicolon
  strings; dates continue to accept ISO and `DD.MM.YYYY`.
- `TeacherEmploymentFields` stays the source of branch, discipline, custom
  data, salary, and rate validation. No new shared state or backend contract is
  introduced.
- UI text remains Russian and the Deep Charcoal/Gold theme is unchanged.

## Acceptance

- The public dialog is below `400` NLOC, max CCN at most `10`, and has no
  god/brain finding. Every new production owner is at most `500` NLOC, max CCN
  at most `10`, and has RepoWise health at least `7.0` once history is indexed.
- Combined replacement weighted deficit is at most `1,621`, an 80% reduction
  from the `8,106` baseline.
- Direct unit tests cover legacy model normalization, payroll version/reload
  behavior, and RBAC-sensitive rendering in addition to the existing device
  flow and service tests.
- Focused Flutter tests, full Flutter tests, `flutter analyze`, formatting, and
  `git diff --check` pass.
- RepoWise is exact at implementation HEAD and reports no broken consumer,
  missing test, conformance violation, or dependency cycle.
- Sentrux is rescanned after each structural step; acyclicity remains `10000`,
  depth remains at most `13`, both architecture rules pass, and overall quality
  does not regress without an explained root-cause dimension.

## Verified outcome

The semantic split is implemented and verified at `ab0f054baf67`.

- The cyclic `1,158`-NLOC part-based owner is deleted. The public shell is `234`
  NLOC with max CCN `5`; every replacement is below `500` NLOC, max CCN is
  `10`, and new-owner health ranges from `7.85` to `10.00`.
- Combined replacement weighted deficit is `800` versus `8,106`, a `90.1%`
  reduction. The shell headline remains `4.73` only because RepoWise retains
  historical scatter (`29` co-change files), four prior fixes, and no ingested
  line-coverage map; no god/brain or complex-method finding remains.
- Every live semantic owner has a direct contract test. Full Flutter verification
  passed `1,016/1,016`; focused RBAC, access, save, payroll version/reload,
  dialog lifecycle, and presentation tests pass, and `flutter analyze` reports
  no issues.
- RepoWise is exact at the verified commit and reports no dependency cycle,
  conformance violation, breaking change, or cross-repository break. Its sole
  `missing_tests` row is the deleted `teacher_detail_widgets.dart` diff entry,
  not a reachable production owner.
- Sentrux closed at quality `5748`, acyclicity `10000` with raw `0`, depth `13`,
  equality `6262`, modularity `5381`, redundancy `4889`, and both rules passing.

## Rollback

Land the pure model, payroll controller/dialogs, payroll view, content view,
and final shell wiring as separate commits. Revert in reverse order. The split
does not modify API, database, production state, routes, or migrations.
