# Lesson feed, chronological coverage and calculation request fixes

Status: implemented and verified locally; not published. Production remains on
1.5.33+213. This is development evidence, not authorization for deployment or a
replacement for the next version's release gate.

## Behavior

- The student's timeline displays 30 calendar dates in two horizontal rows of
  15: today −3 through today +11, followed by today +12 through today +26.
  Today's inclusion was explicitly confirmed by the owner. Empty days retain
  their position; all pages and multiple lessons per day are included.
- Active compatible reservations are allocated by lesson date and ID across
  manual bookings and recurring plans. Creation order no longer determines
  coverage. Funding edits, cancellation, rescheduling and plan changes reconcile
  coverage transactionally. Unchanged reservations retain their IDs; displaced
  reservations become released and remain in history. Financial facts are not
  created by booking or planned preview. Historical exceptions are documented
  in CURRENT-PRODUCT-RULES.md.
- Production's read-only diagnostic showed HTTP 400 on planned-settlement preview:
  `property reasonCode should not exist`. Flutter's edit operation aliases the
  planned-settlement endpoint but previously sent this extra field. The request
  now omits it for both aliases and retains the entered `reasonText`.

## Verification

- Flutter: 60 tests passed in `dist/current-fixes-flutter.log`; analyzer found no
  issues across the nine changed Dart files (`dist/current-fixes-analyze-final.log`).
- Full server run: 313 suites / 4,082 tests; initially 4,080 passed and two failed.
  The new audit action lacked a presentation label, and one RBAC test double
  lacked `lockSettlementCoverage`. Both were fixed. Audit rerun: 106 tests passed
  (`dist/current-fixes-audit-final.log`); RBAC rerun: 35 tests passed
  (`dist/current-fixes-rbac-final.log`). The full 313-suite command was not repeated
  after these focused corrections. There are no unresolved failures from that run.
- Windows → real HTTP → PostgreSQL: 26 checks passed, 43 HTTP requests, zero server
  errors. Includes creation, edit with a reason and signed calculation, cancellation,
  refund, failure recovery, version conflicts and synthetic backup restoration.
  Evidence: `dist/http-journeys/c1e64a5d899f4beea048b75e624748c1/result.json`.
  Only the RBAC test double changed after this run; production code did not.
- Existing-data reconciliation CLI: an independent disposable database was seeded
  with a deliberately incorrect later reservation. Preview preserved reservations,
  audit and outbox byte-for-byte; apply covered the earlier lesson and retained the
  released record; repeated apply changed nothing. Result:
  `dist/current-fixes-coverage-cli.log`. Database was removed afterwards.
- Server typecheck and Nest build succeeded; `git diff --check` passed. RepoWise
  `update --index-only` completed. No new release artifacts were published and no
  production reservation or financial history was changed.

## Release dependency

Release Flutter and the bounded timeline endpoint together. Review the coverage
reconciliation CLI's preview against an isolated copy before an authorized
production apply; use a fresh backup and the established rollback/reconciliation
procedure. The next numbered release still needs its own fresh release gate and
packaging evidence.
