# HolliHop Staging Dry-Run

Use this runbook for the Phase 03 DB-backed HolliHop dry-run gate on staging.
The helper never runs `apply`; it forces `HOLLIHOP_IMPORT_MODE` to `dry_run`
and passes `--dry-run` to the importer.

## Preconditions

- A fresh encrypted staging backup exists and the backup artifact or SHA/evidence
  note is available as a local file.
- `MIGRATION_DATABASE_URL` or `DATABASE_URL` is available either in the current
  shell or in an ignored local env file loaded by the helper. Do not write the
  value to this file, repo docs, Linear or logs.
- For live HolliHop source reads, `HOLLIHOP_AUTH_KEY` is available either in the
  current shell or in an ignored local env file loaded by the helper. Local
  archive mode does not need the key.
- The target is staging. Do not use this helper for production cutover.

## Local Env Loading

By default, the helper loads these ignored files if they exist and keeps any
already-set process values as the higher priority source:

- `server/.env`
- `infra/staging/.env`
- `infra/staging/.backup.env`

The helper prints only file names and key counts; values remain hidden. To force
manual process-only env setup, pass `-NoEnvFiles`.

## Backup Gate

On the staging host, create the encrypted backup:

```bash
cd /opt/magicmusiccrm/infra/staging
/opt/magicmusiccrm/infra/scripts/backup-staging.sh
```

Copy either the encrypted backup, its `.sha256`, or an evidence note that records
the backup name and SHA-256 to the local machine. The helper requires this file
through `-BackupEvidencePath` because DB-backed dry-run can write migration,
import batch and source-record audit rows.

## Local Archive Dry-Run

Run from the repository root after the staging DB URL is present in either the
current PowerShell process or one of the ignored env files above:

```powershell
.\scripts\hollihop_staging_dry_run.ps1 `
  -BackupEvidencePath .supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence/<backup-evidence-file>
```

Optional controls:

```powershell
.\scripts\hollihop_staging_dry_run.ps1 -CheckOnly
.\scripts\hollihop_staging_dry_run.ps1 -NoEnvFiles -CheckOnly
.\scripts\hollihop_staging_dry_run.ps1 -SkipMigrate -BackupEvidencePath <backup-evidence-file>
.\scripts\hollihop_staging_dry_run.ps1 -SourceDir _archive/backups/hollihop_backup_2026-03-14T15-42-12 -BackupEvidencePath <backup-evidence-file>
```

The default source is
`_archive/backups/hollihop_backup_2026-03-14T15-42-12`.

Unless `-SkipMigrate` is passed, the helper runs `npm run db:migrate` before
the importer so migrations such as `0019_hollihop_import_audit` are present.

## Live Read-Only Source

Use live HolliHop only when the key is already present as a transient environment
secret:

```powershell
.\scripts\hollihop_staging_dry_run.ps1 -UseLiveApi -BackupEvidencePath <backup-evidence-file>
```

The helper checks only that the key exists and never prints the value. HolliHop
is read-only; no HolliHop create/update/delete calls are part of this importer.

## Review

The helper writes evidence under
`.supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence`:

- `hollihop-staging-dry-run-migrate-*.log`
- `hollihop-staging-dry-run-import-*.log`
- `hollihop-staging-dry-run-summary-*.md`
- `hollihop-import-*.json`

Review before any separate apply discussion:

- `sourceCounts` vs the expected archive/live source counts.
- `plannedCounts` for CRM entities and `sourceRecords`.
- `storedCounts` after dry-run; CRM counts should not unexpectedly jump in
  dry-run mode.
- `skippedCounts`, `warnings`, `monthlyRevenue` and `duplicateSummary`.
- Logs contain no raw DB URLs, HolliHop auth keys, passwords or tokens.

## Apply Boundary

Do not run `apply` from this helper. A future apply needs a reviewed dry-run report,
a fresh backup, explicit user approval, staging-only execution first,
API health smoke and rollback evidence.
