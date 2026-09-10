# Subscription replacement coverage and individual plan archive

Status: implemented locally after production 1.5.36+216; not published. No production writes, version bump or installer build in this task.

## Root cause and correction

Replacement moved existing reservations to the new issued subscription while immutable lesson snapshots/decisions kept the original subscription ID. The timeline required exact ID equality and displayed every transferred reserve as uncovered. Chronological allocation also discovered only directly linked contracts; released overflow could not refill when the package was enlarged again.

The shared replacement lineage follows existing lifecycle events, retains the same owner and terminates cycles with UNION. Timeline coverage accepts reserves in that lineage. Planning, allocation and new settlement resolve the active descendant; historical facts and snapshots remain intact. Coverage discovery includes ancestral contracts, including lessons whose old reservations were released. Replacement reconciles after writing its lifecycle event in the same transaction. Settlement coverage locks/fingerprints include successor subscriptions, and replay compares the original selection with the actual fact's lineage rather than creating a second charge. Corrections retain their explicit historical semantics.

## Archive behavior

The released application had no archive action. The new action is available on expanded, ended individual plans to staff with schedule write access. Preview shows the affected count and blockers; confirmation requires a reason. Active/group plans, non-cancelled lessons, any linked payment, nonzero client/teacher facts and reserved/consumed subscription units block archiving. The server rechecks current scope, impact and version inside the existing transaction/idempotency/audit/outbox boundary.

Migration 0155 adds archive metadata to plans and lessons. Rows and historical decisions are retained. The student timeline hides archived lessons; the plan moves into a collapsed archive section with its reason. Database guards serialize against financial inserts and prevent financial operations or a live lesson state after archiving. The ordinary payment command also rejects an archived lesson reference. The down migration refuses to discard populated archive history.

## Verification

- `dist/funding-archive217/replacement-red.log`: reproduced false timeline coverage after a real replacement.
- `backend-verified.log` / `backend-results.json`: nine relevant suites, 223 tests passed, no skips. Fresh migrated isolated PostgreSQL clone per suite. Includes replacement/back-to-original, shrink/refill, recovery with all reserves released, idempotent reconciliation, settlement preview/actual fact/replay, archive/payment blockers, stale impact, unauthorized branch/stale role, preserved lesson history and late-payment rejection.
- `flutter-verified.log`: 43 tests passed. Archive reason validation, network retry with identical command identity/payload, blocked/read-only UI, archive section, existing layout and timeline pagination.
- `analyze-verified.log`: Flutter lib/test analysis clean. `typecheck-final.log` and `build.log`: backend typecheck/build passed. Additional existing subscription issue and finance balance suites passed in `funding-final-verified.log`; that earlier combined run had a subsequent fixture-only preview failure, resolved and covered in the final run.
- Early failed runs are retained. An intermediate invocation named a nonexistent payment test file; it is not counted as a successful gate. The final nine-suite invocation completed successfully.

## Release requirements

A new release candidate still needs its full release gate, fresh encrypted backup/isolated restore, guarded deployment and post-deploy reconciliation. Deploy the API/migration before a client that sends `includeArchived`. The existing `reconcile-subscription-coverage` utility now discovers replacement ancestors and can repair old missing reserves; preview it first and apply only within an authorized production release after reviewing the impact. Do not rewrite snapshots or financial history.

After archive data exists, use a compatible forward fix: server 216 does not understand archive visibility or the new query field. Do not rewind the database or drop archive history. The separate subscription-renewal work queue remains outside this change.
