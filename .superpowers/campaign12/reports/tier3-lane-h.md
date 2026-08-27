# Tier 3 Lane H — Teacher statistics owners

Campaign baseline: `37667c097e850092dbafaa0480c5e4b64e623025`

Lane commit: `6910b207daf37499c9eada0d1c0b16661ebc8a6b`

## Implemented boundary

- `TeacherStatsWidget` is a 62-NLOC Riverpod lifecycle shell with the unchanged public constructor.
- `TeacherStatsController` owns references/report loading, exact queries, selection, rate commands, export validation/opening, formatting, and settled-payroll policy.
- Models, rate dialogs, stateless view, and bounded view components are separate semantic owners; all six production files stay below 500 NLOC.
- A permanent architecture guard enforces shell NLOC/import/symbol limits and every extracted-owner NLOC ceiling.

## Preserved behavior

- Inclusive external end becomes exclusive `end + 1 day`; external period/branch controls stay hidden and its branch is still forwarded.
- All query filters reach report/export; CSV keeps UTF-8 BOM validation and `teacher-stats-yyyy-MM-dd.csv`.
- Selection clears on reload; one bulk request preserves numeric zero; group update keeps `setTeacherRate: true`.
- Settled corrections remain restricted to `director`/`system_admin`; keys `branch-*`, `teacher-*`, `unit-*`, `status-*`, `disc-*`, `cat-*` and the lock text remain intact.

## TDD and lane smoke

- RED: controller test exited 1 because the controller/model files and required symbols did not exist.
- Final focused smoke: 3 files / 10 tests passed, 0 failed.
- Exact Task H `flutter analyze --no-pub`: PASS, no issues.
- Resolved 9-file format check: 0 changes; contract `rg` and `git diff --check`: PASS.
- All eight verify-only paths are byte-identical to the Tier dependency SHA.

## RepoWise evidence

All scans were serialized with `Global\MagicMusicCRM-Campaign12-RepoWise`. The module scan was indexed at `b9cca7b0e49d4501b5378683f6c59bedf75e17cd`; the only health-directed source change split components helpers, and its targeted live row was indexed at `acf83efa496de2f44f38fdec7cbb0c8af01a98ae`. The other five production blobs are unchanged between those SHAs and the final commit. Final `repowise status` matched `6910b207daf37499c9eada0d1c0b16661ebc8a6b` after the report-only reindex.

Weighted deficit is `round(max(0, 8.0 - raw health) * NLOC)`.

| Production owner | Raw health | Coverage penalty | NLOC | Max CCN | Weighted deficit | god/brain |
|---|---:|---:|---:|---:|---:|---|
| shell | 6.15 | 0.00 | 62 | 3 | 115 | none |
| models | 8.09 | 1.56 | 139 | 7 | 0 | none |
| controller | 9.85 | 0.00 | 226 | 7 | 0 | none |
| rate dialogs | 9.85 | 0.00 | 157 | 3 | 0 | none |
| view | 8.78 | 0.00 | 390 | 8 | 0 | none |
| components | 9.47 | 0.00 | 289 | 7 | 0 | none |

Every new owner passes raw health `>=7.0`, max CCN `<=8`, NLOC `<=500`, and no god/brain finding. The shell's structural score is 10.00 before path-history/clone penalties; its raw score is driven by accumulated churn, entropy, scatter, prior defects, and duplication on the pre-existing path. Combined replacement weighted deficit is 115 versus baseline 5,327, a 97.8% reduction.

## Commit

`refactor(reports): split teacher statistics owners`
