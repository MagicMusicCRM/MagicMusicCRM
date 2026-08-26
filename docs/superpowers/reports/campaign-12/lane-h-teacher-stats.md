# Campaign-12 Lane H — Teacher Statistics

- Tier dependency SHA: `37667c097e850092dbafaa0480c5e4b64e623025`
- Branch: `codex/campaign12-teacher-stats`
- Baseline: health `3.04`, NLOC `1074`, max CCN `22`, weighted deficit `5327`

## TDD evidence

`flutter test test/features/manager/teacher_stats_controller_test.dart`
failed before production code because `teacher_stats_controller.dart`,
`TeacherStatsController`, and `TeacherStatsQuery` did not exist. After the
extraction, the four required controller contract tests pass.

## Owners and structural gate

| Owner | Guard NLOC |
| --- | ---: |
| `teacher_stats_widget.dart` | 62 |
| `teacher_stats_models.dart` | 139 |
| `teacher_stats_controller.dart` | 226 |
| `teacher_stats_rate_dialogs.dart` | 157 |
| `teacher_stats_view.dart` | 390 |
| `teacher_stats_components.dart` | 289 |

The components part is the bounded continuation of the stateless report view;
it keeps rows/totals/badges out of the shell without compressing UI code into
the controller or models. The shell has 9 imports and none of the forbidden
report, mutation, export, filter-builder, or row-builder symbols.

## Contract proof

- External inclusive `2026-03-02..2026-03-08` becomes the exact UTC query
  `from=2026-03-02T00:00:00.000Z`, `to=2026-03-09T00:00:00.000Z`; external
  range skips the branch catalogue/control while retaining its branch value.
- Export forwards branch, teacher, unit type, status, discipline, and category;
  validates the UTF-8 BOM; and opens `teacher-stats-2026-03-02.csv`.
- Lesson repricing keeps numeric zero and performs one bulk request. Group rate
  performs one PATCH whose payload contains `teacherRate`, proving
  `setTeacherRate: true` was used.
- Reload clears selected units. Settled correction remains limited to
  `director`/`system_admin`; filter keys and the payroll lock text are retained.

## Lane gate

- Focused smoke: 10/10 PASS (`teacher_stats_bulk_rate_test.dart`,
  `teacher_stats_controller_test.dart`, `teacher_stats_architecture_test.dart`).
- `flutter analyze --no-pub` on the five named Task H files: PASS, no issues.
- Resolved Task H format check: 9 files, 0 changes.
- Contract `rg` and `git diff --check`: PASS.
- Verify-only paths: identical to Tier dependency SHA.

## RepoWise post-commit gate

The exact source commit `acf83efa496de2f44f38fdec7cbb0c8af01a98ae`
was indexed under `Global\MagicMusicCRM-Campaign12-RepoWise`. A single live
module-health query supplied the owner rows; after its only finding above the
desired CCN bound, a targeted components fallback verified the bounded fix.

| Owner | Raw health | NLOC | Max CCN | Live penalties |
| --- | ---: | ---: | ---: | --- |
| shell | 6.15 | 62 | 3 | DRY 0.35; historical churn 1.188, entropy 0.897, scatter 1.069, prior defect 0.346 |
| models | 8.09 | 139 | 7 | stale/absent coverage 1.56; DRY 0.35 |
| controller | 9.85 | 226 | 7 | DRY 0.15 |
| rate dialogs | 9.85 | 157 | 3 | DRY 0.15 |
| view | 8.78 | 390 | 8 | large filter 0.875; DRY 0.35 |
| components | 9.47 | 289 | 7 | low large-method 0.375; DRY 0.15 |

The shell's structural score is 10.00 before accumulated history/clone
penalties; its raw score therefore does not describe the 62-NLOC shell's
current complexity. Every newly extracted owner is raw `>= 8.09`, and every
owner is max CCN `<= 8` after the health-directed components cut.
