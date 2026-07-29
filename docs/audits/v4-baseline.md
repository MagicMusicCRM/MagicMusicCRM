# MagicMusicCRM v4 — Clean Baseline Evidence

**Task:** T8.1.1
**Date:** 2026-07-25
**Result:** PASS
**Source revision:** `af0aa0b9abfc1cdf2c42798e57803111abbfe3d3`

## Scope

The v4 baseline was executed from a detached, clean Git worktree created from
the source revision above. The existing developer worktree and its
documentation changes were not used as proof of the clean-checkout criterion.

The clean worktree was removed after the gates completed.

## Toolchain

| Tool | Version |
|---|---|
| Windows | Windows 10 Pro, build 26200, x64 |
| PowerShell | 5.1.26100.8875 |
| Git | 2.53.0.windows.3 |
| Node.js | 24.14.0 |
| npm | 11.9.0 |
| Flutter | 3.41.4 stable, revision `ff37bef603` |
| Dart | 3.11.1 stable |
| PGlite | `@electric-sql/pglite@0.5.4` |

## Reproduction

Run from the repository root:

```powershell
npm --prefix server ci
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
flutter analyze
flutter test
```

The two PostgreSQL integration suites can be asserted explicitly with:

```powershell
npm --prefix server test -- --runTestsByPath src/db/demo-workflow-postgres.integration.spec.ts src/crm/finance-balance-postgres.integration.spec.ts
```

## Results

| Gate | Result | Evidence |
|---|---|---|
| Backend clean install | PASS | 681 packages installed from `server/package-lock.json`; PGlite 0.5.4 resolved |
| Backend typecheck | PASS | `tsc --noEmit`, exit 0 |
| Backend full test | PASS | 100/100 suites, 918/918 tests, 0 snapshots |
| PostgreSQL integration suites | PASS | 2/2 suites, 3/3 tests; both named paths executed |
| Backend build | PASS | `nest build`, exit 0 |
| Flutter analyze | PASS | No issues found |
| Flutter full test | PASS | 400/400 tests |
| Lock-file integrity | PASS | `server/package-lock.json` and `pubspec.lock` unchanged |

The complete clean-checkout command chain exited 0. The full server run took
97.841 seconds; the explicit PostgreSQL run took 14.484 seconds; the clean
Flutter analysis took 31.6 seconds. The first cold end-to-end chain completed
in 572.8 seconds.

## Observations

- `npm ci` reports four existing transitive advisories: one low and three high
  (`body-parser`, `brace-expansion`, `fast-uri`, and `js-yaml`). No dependency
  update was applied because T8.1.1 verifies the locked baseline and does not
  authorize dependency upgrades.
- Jest emits expected warning logs from negative-path tests and Node's
  experimental VM modules warning. They do not represent skipped or failed
  tests.
- Flutter dependency resolution reports newer incompatible releases, but the
  locked dependency graph resolves and neither lock file changes.
- In the temporary Windows worktree, Flutter touched generated registrant file
  timestamps/line endings under `core.autocrlf=true`; normalized Git diffs were
  empty. The primary worktree has no generated registrant diff.

## Acceptance

- Clean install from lock files: PASS.
- Both PostgreSQL integration suites executed: PASS.
- Full backend typecheck/test/build: PASS.
- Full Flutter analyze/test: PASS.
- No suite was excluded to obtain the result: PASS.
