# Release 211 — unified schedule and commerce verification

**Verification window:** 2026-09-04 20:18–20:33 MSK  
**Candidate ref:** `176eda6a241eb67af7cda73f922ec76a5d82d692`  
**Branch:** `codex/unified-schedule-settlement`  
**Target:** `1.5.31+211`  
**Decision:** **BLOCKED — do not build, publish, or deploy this candidate.**

Production was not queried or changed. No production backup was opened, no
production reconciliation was run, and no image or client artifact was
published. This document records one bounded verification pass; failed gates
were not retried.

## Gate result

| Gate | Result | Evidence |
| --- | --- | --- |
| Backend schedule focus | PASS | 9/9 suites, 75/75 tests, exit 0 |
| Backend commerce focus | FAIL | 6/8 suites and 78/81 tests passed; 3 failed, exit 1 |
| Payroll + HTTP matrix + V8 data focus | PASS | 3/3 suites, 37/37 tests, exit 0; HTTP contract includes hard `5xx=0` |
| Full backend | FAIL | Functional failures were emitted, then Node exited 134 on heap OOM before a final Jest count |
| Backend typecheck/build | PASS | Both commands exited 0 |
| Flutter analyze | PASS | 0 findings, exit 0 |
| Full Flutter | FAIL | 1609 passed, 32 failed, exit 1 |
| Named Windows device tests | BLOCKED | 0 tests executed; Windows build failed on `sentry-native` paths longer than Win32 limit |
| Fresh production-like DB | PASS, limited | Migration `0149`, V7 reconciliation `issues=[]`, live/ready and fail-closed checks passed |
| Scrubbed restore reconciliation | NOT RUN | No clearly scrubbed and authorized local backup was present |
| Strict security preflight | FAIL | 9/11 checks passed; Git missing blob and unreachable Docker daemon |
| RepoWise structural gate | SKIPPED | Explicitly disabled because it repeatedly corrupts this worktree index |
| Gitleaks / Trivy scan | NOT RUN | Tools exist, but the pass stopped at the required Git missing-blob condition; Docker image scan was impossible |
| Exact image gate | NOT RUN | Docker daemon unavailable; no candidate image ID or digest exists |

## Exact commands and timestamps

All timestamps below use `Europe/Moscow` (`+03:00`).

| Start–end | Command | Exit/result |
| --- | --- | --- |
| 20:18:49–20:19:17 | `cd server; npm run test:schedule-v4` | 0; 9 suites, 75 tests |
| 20:19:21–20:19:37 | `cd server; npm run test:commerce-v4` | 1; 6/8 suites and 78/81 tests passed |
| 20:19:44–20:19:53 | `cd server; npm test -- --runInBand --runTestsByPath src/crm/payroll-postgres.integration.spec.ts src/crm/schedule/schedule-commerce-http.contract.spec.ts src/migration/commerce/v8/lesson-settlement-policy-data.spec.ts` | 0; 3 suites, 37 tests |
| 20:19:58–20:24:15 | `cd server; npm test -- --runInBand` | 134; functional failures, then heap OOM; no final Jest count |
| 20:24:20–20:24:24 | `cd server; npm run typecheck` | 0 |
| 20:24:29–20:24:39 | `cd server; npm run build` | 0 |
| 20:24:48–20:25:03 | `flutter analyze` | 0; no findings |
| 20:25:33–20:29:11 | `flutter test` | 1; 1609 passed, 32 failed |
| from 20:29:17 | `flutter test integration_test/client_calendar_device_test.dart integration_test/lesson_settlement_device_test.dart integration_test/modal_device_test.dart integration_test/recurring_plans_device_test.dart integration_test/teacher_payroll_device_test.dart -d windows` | Stopped after two identical build failures; 0 tests executed |
| 20:32:04–20:32:15 | `.\scripts\v7_production_like_gate.ps1 -DatabaseName magiccrm_v7_prodlike_release211 -Port 3211 -ExpectedMigrationId 0149_lesson_settlement_policy_revision` | 0; temporary DB removed |
| 20:32:43–20:32:48 | `cd server; SECURITY_GATE_STRICT=1 npm run security:gate` (PowerShell environment equivalent) | 1; 9 pass, 2 fail |

## Backend blockers

`test:commerce-v4` has three deterministic failures:

1. `lesson-settlement-postgres.integration.spec.ts` expected
   `SUBSCRIPTION_CAPACITY`, but received `SETTLEMENT_TYPE_NOT_ALLOWED`.
2. The same suite's five-rule snapshot expected different percent, fixed and
   hourly compensation amounts/defaults from those persisted by the candidate.
3. `commerce-schema-postgres.integration.spec.ts` expected one subscription
   backfill, but the result was two.

The full backend run reproduced these and emitted at least 15 observed failing
tests across 11 suites before Node exhausted its approximately 2 GB heap. Jest
did not print its final suite/test totals, so this evidence does not infer a
complete count. The observed additional failures were:

- `lesson-compensation-rbac.spec.ts`: rejection-order test reached an
  undefined query result instead of the expected typed 422.
- `crm-configuration-postgres.integration.spec.ts`: two catalog source and
  validation-order mismatches.
- `audit-presentation.coverage.spec.ts`: four unresolved
  `this.auditAction(operation)` producers.
- analytics/status/backfill dry-run suites: fixture counts differed from
  expected values.
- `payroll-service-boundary.spec.ts`: semantic owner is 432 NLOC over a ceiling
  of 420.
- `schedule-plan-postgres.integration.spec.ts`: three settlement/occurrence/
  cancelled-count mismatches.

Some count mismatches are compatible with shared local PostgreSQL fixture
pollution, but they remain failed release gates until reproduced cleanly or
fixed. The OOM is itself a gate failure and prevents a full-suite PASS claim.

## Flutter and Windows blockers

`flutter test` completed with 1609 passes and 32 failures. The observed failures
cluster around the new adaptive lesson modal and stale test contracts:

- multiple `lesson_form_test.dart` cases still require an `AlertDialog` inside
  `SafeArea`, while the production editor now uses the shared adaptive modal;
- `lesson_editor_sections_test.dart` rejects the new direct
  `magic_sheet.dart` import in `lesson_editor_view.dart`;
- `representative_modal_set_test.dart` reports
  `lesson_decision_form.dart` outside the shared modal/picker entrypoint;
- additional interleaved failures occurred in schedule/recurring modal tests.

The compact runner interleaved and truncated detailed output, so this report
does not invent per-test names for all 32 failures. The total and exit code are
from the runner's final line. Per the bounded-pass rule, the suite was not
rerun solely to collect prettier output.

The named Windows command never reached a device test. CMake/MSBuild failed
while cloning `sentry-native`/Breakpad/Crashpad under the long worktree path,
with `Filename too long`. The first two test files produced the same build
failure; the command was then stopped to avoid three identical rebuilds.
No 390 or 1440 device evidence exists for this candidate.

## Reconciliation and image limits

The repository contains SQL fixtures and migrations, but no clearly scrubbed
and explicitly authorized production-like backup. Existing encrypted real-data
production backups were not opened. Therefore the required V8 dry-run/apply/
second-apply proof against a restore was not performed; V8 counts, report hash,
mutation count, and idempotent second-apply count are unavailable.

A safe fresh-database substitute was run in the dedicated
`magiccrm_v7_prodlike_release211` database. It migrated to
`0149_lesson_settlement_policy_revision`, rejected invalid production flags,
returned live/ready with `access:v4,schedule:v4`, and reported V7
`issues=[]`. The script removed the temporary database. This proves clean
bootstrap behavior only; it does not replace a scrubbed restore or V8 legacy
classification evidence.

Docker Desktop's Linux daemon was unreachable. No candidate image was built,
so image ID, OCI revision label, digest, Trivy image result, healthy/degraded
exact-image result, and artifact hashes are all unavailable.

## Security and structural limits

Strict security preflight reported 9 pass, 0 warn, 2 fail. NPM audit reported
zero vulnerabilities; ignore coverage, Docker context exclusions, public env,
source-map, frontend secret-default and external-tool availability checks
passed. Failures:

1. `git diff --check` could not read blob
   `7c818a20b03eb46a9f91bcca2056995854198bb8` from the corrupted worktree
   index.
2. Docker daemon was unreachable.

After that required stop condition, no standalone history-aware Gitleaks,
Trivy filesystem/image, or Semgrep scan was started. RepoWise was intentionally
not invoked: prior invocations repeatedly replaced this worktree index with
foreign/missing object entries. Structural assessment used direct source,
diff-independent tests and compile evidence only.

The parent task resynchronized the exact worktree index after this pass and
reported a clean tracked tree with only the pre-existing untracked `.claude/`
directory. Failed gates were not rerun, so that repair is not represented as a
release PASS.

## Required next action

Do not start artifact build or release deployment. Fix the backend/Flutter
gate failures, run the full candidate pass from a short Windows checkout, make
Docker available, and provide a clearly scrubbed/authorized restore for V8
dry-run/apply/idempotency evidence. Production deployment still requires a new
explicit owner command after all gates and rollback evidence pass.
