# Campaign-12 Tier 2 integration evidence

Status: INTEGRATED; independent Tier 2 review is pending.

## Accepted source and integration history

- Tier 2 base: `2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`.
- Lane D Profile: `e57ad45fad6212e206ac1aa48948e6777dd4c1ef`.
- Lane E Auth: `6a1c4dbd774fe9b0af0d0b77c7539f6c4f6aedc4`.
- Lane F LessonTransition: `bb88b9e96097c57c49cd07e20259ae120c0aa781`.
- D/E/F no-ff merge commits, in approved order: `dbd19ab6deac0713994b96c24da3ec8bba8217c6`, `8acd9f369e763d541fda675dc60f6681e987d8fb`, `9403bfbd8fb1c951cbea96085f0cbfc3a914eb68`.
- Reviewer test-only sources: D `8f95d338cb8322a73eb3d4b0501d213e6c0d6ed7`, F `7b59cb7051c07026c855fc39eb3b3b2228e622e6`.
- Applied review-fix commits: D `83db18ee663a372246f9388108996a607f6381a8`, F guard hardening `f5ec03d6646a390a76b8cc8ab5e23e1acf6da29b`.
- Final F test-quality source: `42d06532e53f99f459253fb04605976112a9eb3f`; applied final HEAD: `43f47e363e39c20b0e958900fa539b0969714a81`.

Every commit-producing integration command used `REPOWISE_SKIP_HOOK=1`. The
three lane branches matched the approved full SHAs before merging, all merges
used the `ort` strategy without conflicts, and the review fixes changed tests
only.

## Module and metadata ownership

- D changes only `profile.module.ts`: `ProfileRecordRepository`,
  `MyProfileService`, `ProfileDirectoryService`, and `ProfileNotesService` are
  private providers; the public export stays `ProfileService`.
- E changes only `auth.module.ts`: the seven workflow owners are private
  providers; the public exports remain the established Auth facade, password,
  and session services.
- F changes only `crm.module.ts`: the six LessonTransition workflow owners are
  private providers; controllers still consume the compatibility facade.
- `schedule-plan.service.ts` imports `LessonCommandMetadata` directly from the
  neutral `lesson-command-metadata.ts`; the historical lesson-command path only
  re-exports the type. The wiring grep and lane ownership diffs found no module
  collision.

## Integrated smoke evidence

Initial integrated graph at `9403bfbd8fb1c951cbea96085f0cbfc3a914eb68`:

| Lane | Command scope | Result | Jest time | Wall time |
|---|---|---:|---:|---:|
| Profile | six approved Profile suites | 6 suites, 23/23 PASS | 19.923 s | 22.965 s |
| Auth | six approved Auth suites | 6 suites, 52/52 PASS | 23.526 s | 26.557 s |
| Transition | metadata + boundary suites | 2 suites, 8/8 PASS | 18.322 s | 21.338 s |
| PostgreSQL | three named transition cases | 1 suite, 3/3 PASS, 5 filtered | 17.120 s | 19.603 s |

`npm run typecheck -- --pretty false` passed in 11.040 s wall time and
`git diff --check 2c08eab6..9403bfbd` passed.

After the D/F reviewer test-only fixes at final HEAD:

| Lane | Command scope | Result | Jest time | Wall time |
|---|---|---:|---:|---:|
| Profile | six approved Profile suites | 6 suites, 25/25 PASS | 15.904 s | 18.383 s |
| Transition | metadata + hardened boundary suites | 2 suites, 13/13 PASS | 14.996 s | 17.462 s |
| PostgreSQL | same three named transition cases | 1 suite, 3/3 PASS, 5 filtered | 10.517 s | 12.818 s |

The final backend typecheck passed in 7.812 s wall time and
`git diff --check 2c08eab6..f5ec03d6` passed. Auth production/test sources were
unchanged by the review-fix round, so its 52/52 integrated result remains the
applicable Tier 2 synchronization evidence. No full suite, fresh coverage, or
Sentrux scan was run in this tier.

The final test-quality split moved ordering fixtures into a dedicated third
spec without changing production code. The exact metadata/boundary/order run
passed 3 suites and 13/13 tests in 7.477 s Jest time / 8.630 s wall time;
typecheck passed in 3.979 s wall time and the final diff check passed. Physical
spec NLOC is `193/356/309`, respectively.

## RepoWise index repair and exact snapshot

All RepoWise writes and reads were serialized with
`Global\\MagicMusicCRM-Campaign12-RepoWise`.

The first ordinary incremental update selected `e57ad45f..9403bfbd` from the
shared lane index. Although it wrote the merge HEAD, a targeted read exposed a
merge-DAG defect: Profile still had the 656-NLOC baseline facade and four new
owners were `not_indexed`. Those rows were rejected and are not evidence.

The repair ran exactly:

`repowise update --index-only --since 2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`

It refreshed all 42 D/E/F files in 4m55s. After the first two test-only review
fixes, an incremental update refreshed exactly four spec files in 4m25s. The
last test-quality fix then refreshed exactly three scheduling specs in 2m33s.
`repowise status --format json` now reports
`last_sync_commit=43f47e363e39c20b0e958900fa539b0969714a81`.
The final batched health read matched all 21 literal targets with `missing=[]`:
the 20 Campaign-12 owner/facade rows were unchanged, and the prerequisite-only
SchedulePlan row was also present.

## Final raw health rows

These are raw deterministic scores from the exact final index. `+1.56` is shown
only where the final finding array explicitly contains `untested_hotspot`; it
is not substituted for the raw value.

| File | Raw | Explicit stale penalty | Tier view | NLOC | CCN | god/brain |
|---|---:|---:|---:|---:|---:|---|
| `profile.service.ts` | 5.95 | 0.00 | 5.95 | 36 | 1 | none |
| `profile-record.repository.ts` | 7.49 | 1.56 | 9.05 | 195 | 2 | none |
| `my-profile.service.ts` | 8.63 | 0.00 | 8.63 | 155 | 10 | none |
| `profile-directory.service.ts` | 9.85 | 0.00 | 9.85 | 356 | 2 | none |
| `profile-notes.service.ts` | 9.65 | 0.00 | 9.65 | 94 | 3 | none |
| `auth.service.ts` | 5.32 | 0.00 | 5.32 | 88 | 1 | none |
| `auth-account.service.ts` | 8.90 | 0.00 | 8.90 | 147 | 6 | none |
| `auth-email-challenge.service.ts` | 7.79 | 1.56 | 9.35 | 106 | 5 | none |
| `auth-login.service.ts` | 9.30 | 0.00 | 9.30 | 169 | 4 | none |
| `auth-password-recovery.service.ts` | 9.65 | 0.00 | 9.65 | 132 | 3 | none |
| `auth-rate-limit.service.ts` | 7.59 | 1.56 | 9.15 | 137 | 2 | none |
| `auth-registration.service.ts` | 9.28 | 0.00 | 9.28 | 114 | 5 | none |
| `auth-verification.service.ts` | 8.93 | 0.00 | 8.93 | 186 | 4 | none |
| `lesson-transition.service.ts` | 6.22 | 0.00 | 6.22 | 86 | 1 | none |
| `lesson-transition-preparation.service.ts` | 5.64 | 1.56 | 7.20 | 436 | 8 | none |
| `lesson-transition-financial.service.ts` | 7.79 | 1.56 | 9.35 | 159 | 4 | none |
| `lesson-transition-commit.service.ts` | 7.06 | 1.56 | 8.62 | 331 | 8 | none |
| `lesson-transition-preview.service.ts` | 9.30 | 0.00 | 9.30 | 80 | 3 | none |
| `lesson-transition-command.service.ts` | 6.67 | 1.56 | 8.23 | 162 | 8 | none |
| `lesson-bulk-transition.service.ts` | 8.58 | 0.00 | 8.58 | 210 | 7 | none |
| `schedule-plan.service.ts` (prerequisite-only) | 1.53 | 0.00 | 1.53 | 1148 | 19 | god class |

All 17 newly extracted owners are within the 500-NLOC and CCN<=10 gates and
have no god/brain finding. The three compatibility facades are 36/88/86 NLOC
and CCN 1; their raw history/duplication scores are preserved rather than
presented as owner-gate scores.

Coverage remains stale by approved policy: LCOV was ingested at commit
`e86b1f555da5892d66e9d850f1bccb203af57949`, before the Tier 2 files. The seven
explicit 1.56 markers therefore remain a Task M fresh-LCOV blocker. Final
campaign acceptance must use fresh raw scores and cannot rely on the tier view.

## Final risk arrays

All four targets report `test_gap=false`, `security_signals=[]`,
`index_behind=false`, and indexed commit `43f47e363e39`.

| Target | Hotspot | Dependents | Risk / pattern | Risk health | Top biomarkers | Impact surface |
|---|---:|---:|---|---:|---|---|
| `profile.service.ts` | 0.962859 | 3 | churn-heavy / primarily refactored | 8.75 | low_cohesion, dry_violation, prior_defect | app.module, profile.controller, profile.module |
| `auth.service.ts` | 0.921514 | 4 | bug-prone / fix-heavy | 7.05 | prior_defect, low_cohesion, dry_violation | crm.module, auth.controller, auth.module |
| `lesson-transition.service.ts` | 0.971969 | 3 | churn-heavy / feature-active | 9.05 | low_cohesion, dry_violation | crm.module, crm-schedule.controller, app.module |
| `schedule-plan.service.ts` | 0.950245 | 3 | churn-heavy / feature-active | 1.90 | function_hotspot, co_change_scatter, god_class | crm.module, crm-schedule.controller, app.module |

`schedule-plan.service.ts` was prerequisite-import-only in Tier 2. Its existing
god-class signal is preserved as a later campaign target; Tier 2 did not claim
to remediate it.

## Handoff to independent reviewer

Review the complete range `2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8..43f47e363e39c20b0e958900fa539b0969714a81`, including all test-only fix
commits. Confirm public signatures, fail-closed RBAC and authentication
behavior, transaction/post-commit ordering, neutral metadata direction,
private module owners, facade guards, and no new dependency cycle. Do not start
Tier 3 until independent Critical/Important counts are `0/0`.
