# Candidate 223 preflight — 2026-09-16

Status: **NOT DEPLOYED; approved outbox recovery and release preparation in progress.**

The owner authorized regression checking and deployment of the local customer
revisions, including desktop search, financial filters, rate corrections,
anchored dropdowns and timeline sizing. No production mutations or publication
have been performed during the initial preflight. Candidate version is now 1.5.43+223.

## Current production blocker

Read-only checks confirmed the deployed source is still
`e8cbb20fd609716ff6b585c765adb19db397cd1c`, image
`magicmusiccrm-server:1.5.42-222-final`, schema0156.
Public `/api/health/ready` returned HTTP503 at 2026-09-16T13:11:08Z:
database, migrations, lesson completion and rollout were OK; platform outbox
had four dead letters and no pending events.

All four dead letters have type `crm.lesson_teacher_rate.changed`, ten attempts,
and sanitized last error `Error`. They occurred at 10:46–10:47 UTC and reached
dead-letter state at 11:07–11:08 UTC, before this preflight. Current
`LessonTeacherRateService` produces this type, while `entityFor` in
`PlatformOutboxWorker` throws for it. Its aggregate is a bulk/global scope:
it must not be emitted as a single lesson ID `global`.

The owner explicitly approved the handler fix and safe replay of these delivery
records without recalculating money or rewriting financial/audit history. Do not silently
delete dead letters, mark them delivered, reset their attempts, or suppress the
readiness failure. Any approved recovery needs tests, backup, compatible
rollback, actual delivery and financial reconciliation evidence.

The new handler maps this event to a global lesson invalidation (`id: null`),
without financial queries or notification creation. The regression test failed
before the fix, then all 8 worker/requeue cases passed. Migration0157 appends
the old delivery metadata to `audit_events` before rearming only eligible dead
letters; event identity and facts remain unchanged. Reapplication is a no-op.
The deployment exception requires the explicitly pinned event IDs, matching
teacher-rate aggregates, no other readiness fault, no pending events, and both
candidate/recovery images at schema0157. Post-cutover readiness is not relaxed.
14 recovery-baseline checks and the existing deploy contract/behavior tests pass.

## Local regression work

The first full Flutter run found two real UI regressions: compact dropdowns
expanded across a ListTile trailing slot, and focus-driven scrolling could close
a just-opened menu in a sheet. Both were fixed in shared dropdown widgets.
Focused funnel/dropdown/payroll/channel tests passed (22 cases), as did the
expense workflow suite (10 cases). The expense test used a positional TextField
finder that now selected the new search input; it now addresses the comment
field explicitly. Additional frame synchronization fixes preserve in-flight
save/branch-race tests. The ordinary-lesson corner assertion now matches the
owner's explicit request. Golden cursor blinking was made deterministic.

Full-run logs, including failures, are retained under ignored `dist/release223/`:
`flutter-full.log`, `flutter-full-final.log`, and `backend-full.log`.
These runs are not a release PASS. The backend run uses isolated local
PostgreSQL databases (run `c338cdc1e865fc91`); it reported PGlite test timeouts
and one PostgreSQL setup connection timeout while Flutter was also running.
Retry failed suites after resource contention ends; do not label failures PASS
without fresh evidence. A final full candidate gate is still required.

Sequential rechecks after the full runs:
- Flutter: all 94 cases across lesson forms, client-card save races, task editor,
  student-board controller and deterministic financial-dropdown golden passed
  (`final-failed-suites-recheck.log`). Branch-switch race cases also passed
  separately (3 cases, `branch-recheck.log`).
- Backend: all three previously timed-out suites passed, 8 cases, zero skips,
  isolated databases cleaned up (`backend-timeout-recheck.log`, run
  `45a6e02d163f3a7a`). This is selection evidence, not a successful full gate.
- Backend typecheck/build completed with exit 0; focused Flutter analysis reported
  no issues. `git diff --check` passed (line-ending warnings only).
- Financial-dropdown golden inspected: search anchor remains visible, options
  appear below it in a rounded menu, multiple selection is visible.

The final serial Flutter run completed with exit 0: **1823 passed, 0 failed,
4 intentional updater skips**, in 11m38s (`flutter-candidate-recheck.log`).
The four updater audit scenarios require their separate configured run; they
were not executed during this preflight. This Flutter result does not establish
the release artifacts, production readiness or a complete release-gate PASS.

No release commit/tag, fresh backup/restore drill, signed release artifacts,
client-channel publication or production cutover exists for candidate223 yet.

Before publication, prove the recovery image accepts the new schedule financial
filter parameters and inherited-rate restoration used by updated clients. An
unchanged build222 image is not established as a compatible rollback. If outbox
recovery is approved, its handler must also be present in the recovery image;
restoring an unsupported handler would recreate dead letters.
