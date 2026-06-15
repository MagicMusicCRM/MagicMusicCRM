# HolliHop Importer V2

Date: 2026-06-14

## Safety Defaults

- Default mode is `dry_run`.
- `apply` requires `HOLLIHOP_IMPORT_MODE=apply` or `--apply`.
- Live HolliHop access requires `HOLLIHOP_AUTH_KEY` as a transient environment variable.
- The guarded staging helper can load ignored local env files and prints only file names/counts, never values.
- Do not write HolliHop keys into repo files, Linear, Flutter, reports or logs.

## Local Archive QA Without DB

From `server/`:

```powershell
$env:HOLLIHOP_IMPORT_SOURCE_DIR = '_archive/backups/hollihop_backup_2026-03-14T15-42-12'
$env:HOLLIHOP_IMPORT_VALIDATE_ONLY = 'true'
npm run hollihop:import
```

The importer resolves that archive path from either `server/` or the repo root and writes a report to `server/exports/`.

## DB-Backed Dry Run

Preferred guarded helper from the repository root:

```powershell
.\scripts\hollihop_staging_dry_run.ps1 `
  -BackupEvidencePath .supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence/<backup-evidence-file>
```

The helper forces `HOLLIHOP_IMPORT_MODE=dry_run`, writes the importer report to
the Supergoal evidence directory, requires a backup evidence file and refuses to
continue if `apply` is already set in the environment. By default it loads
`server/.env`, `infra/staging/.env` and `infra/staging/.backup.env` when present,
while preserving already-set process env values as the higher priority source.
Pass `-NoEnvFiles` for process-only env setup.

Manual equivalent from `server/`:

```powershell
$env:HOLLIHOP_IMPORT_SOURCE_DIR = '_archive/backups/hollihop_backup_2026-03-14T15-42-12'
$env:HOLLIHOP_IMPORT_VALIDATE_ONLY = 'false'
$env:HOLLIHOP_IMPORT_MODE = 'dry_run'
$env:MIGRATION_DATABASE_URL = '<staging-postgres-url>'
npm run db:migrate
npm run hollihop:import
```

This writes only import audit/source rows and the QA report. CRM entity writes are skipped.

## Apply

Run only after backup and reviewed dry-run report:

```powershell
$env:HOLLIHOP_IMPORT_MODE = 'apply'
npm run hollihop:import
```

## Current Archive QA

Validate-only against `_archive/backups/hollihop_backup_2026-03-14T15-42-12` produced:

| Dataset | Rows |
|---|---:|
| Locations | 2 |
| Offices | 2 |
| Lead statuses | 6 |
| Teachers | 20 |
| Derived staff from assignees | 12 |
| Students | 922 |
| Leads | 1,736 |
| Education units | 2,034 |
| Group memberships | 1,090 |
| Payments | 2,709 |

Warnings are expected for this archive: explicit staff, tasks and timeline/history files are not present.

## Current DB-Backed Staging QA

Archive DB-backed staging dry-run passed on 2026-06-15 after encrypted backup
`magicmusiccrm-staging-20260615T131610Z.tgz.enc`.

- Summary: `.supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence/hollihop-staging-dry-run-summary-20260615T164039.md`
- Report: `.supergoal/hollihop-crm-import-adaptation-loading-ux-Guw3IO/evidence/hollihop-import-2026-06-15T13-40-42-091Z.json`
- Batch: `3c4fc480-74a7-4801-a0e2-45c26972004a`
- Mode: `dry_run`
- Warnings: `tasks_source_missing`, `timeline_sources_missing`
- Source counts: `922` students, `1,736` leads, `2,034` education units, `1,090` memberships and `2,709` payments.
- Planned counts: `954` users/profiles, `922` students, `1,736` leads, `2,033` groups, `22,839` lessons, `22,778` lesson participations, `2,708` payments and `2,070` duplicate candidates.

Live HolliHop validate-only also passed on 2026-06-15 without DB writes:
`1,025` students, `1,944` leads, `2,264` education units, `1,211`
memberships and `3,166` payments. Live DB-backed `-UseLiveApi` dry-run remains
blocked at the connection/client stage before report generation.
