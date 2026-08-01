# MagicMusicCRM v4 — Data Migration Dry-Run

**Task:** T8.3.2  
**Result:** PASS  
**Environment:** restored PostgreSQL 17 staging copy

## Result

- Staging source backup SHA-256:
  `6b0b1b8571bdde0da9d1a61e36bf3ad244f8089e74a683c9d1d37da926490379`.
- Backup restore completed with all foreign keys enabled.
- Required migrations: 7/7 present (`0076`, `0083`, `0087`, `0089`–`0092`).
- Named invariants: 8/8; source/target rows 21/21; violations 0;
  pending restartable batches 0.
- Two read-only dry-runs produced the same logical SHA-256 digest.
- Recovery rehearsal reverted `0093` and `0092`, then reapplied both; the
  repeated dry-run remained 21/21 with zero violations.
- Reconciliation: 14 invariants, source/target facts 1/1, unexplained drift 0;
  report signature verified.
- PostgreSQL integration: 1/1 passed.

The first restore attempt exposed 93 orphan `user_access_versions` rows and 2
orphan issued-subscription version-backfill rows left by earlier local test
cleanup. They referenced no surviving domain rows and were removed from the
staging source after preserving the previous backup. The new
`platform.foreign-key-restore-readiness` invariant now fails future dry-runs
before such metadata can reach a restore rehearsal.

## Artifacts

- `docs/audits/v4-migration-dry-run.json`
- `docs/audits/v4-reconciliation-app-to-app.json`

## Reproduction

```powershell
npm --prefix server run v4:migrate:dry-run
npm --prefix server run v4:reconcile -- --require-zero
npm --prefix server test -- --runTestsByPath src/platform/v4-migrate-dry-run-postgres.integration.spec.ts
```
