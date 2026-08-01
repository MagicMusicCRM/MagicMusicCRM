# MagicMusicCRM v4 — Production Preflight & Backfill

**Task:** T8.3.1  
**Result:** PASS  
**Environment:** local production-schema staging copy, PostgreSQL 17

## Evidence

- Backup: `magiccrm-t8.3.1-before.backup`, SHA-256
  `e0c1af7292ee17bfa27e9cc453dff793ef130f58f339244b3742ca824bafeb55`.
- Dry-run: 1 deterministic candidate, 0 writes, review queue 0.
- First apply: 1 access-link row, review queue 0.
- Second apply: 0 candidates, 0 writes, review queue 0.
- Final read-only preflight: 16 checks, findings/blockers/warnings = 0/0/0.
- PostgreSQL integration: 1/1 test passed; it proves dry-run isolation,
  one-time apply and restartability.

The resolved row had exactly one active application account, one profile, one
role-compatible staff entity and no competing active link. The backfill also
supports an explicit teacher-branch assignment only when all future lesson
evidence points to exactly one branch. Missing resources and non-valid lesson
snapshots remain in the safe ID-only review queue; the tool never guesses them.

## Artifacts

- `docs/audits/v4-production-backfill-dry-run.json`
- `docs/audits/v4-production-backfill-first-apply.json`
- `docs/audits/v4-production-backfill-apply.json`
- `docs/audits/v4-data-preflight.json`

## Reproduction

```powershell
npm --prefix server run v4:backfill -- --dry-run
npm --prefix server run v4:backfill -- --apply
npm --prefix server run v4:backfill -- --apply
npm --prefix server run v4:preflight -- --require-zero-blockers
npm --prefix server test -- --runTestsByPath src/platform/v4-backfill-postgres.integration.spec.ts
```
