# Supabase Export Runbook

Purpose: create a read-only export package for S5 dry-run migration. The package contains schema metadata, table NDJSON files, storage object manifest and `export-report.json` with counts and SHA-256 checksums.

## Environment

Required:

```bash
export SUPABASE_DB_URL='postgresql://...'
```

Optional:

```bash
export SUPABASE_EXPORT_DIR='exports/supabase/2026-06-11-dry-run-1'
export SUPABASE_EXPORT_SCHEMAS='public,auth,storage'
export SUPABASE_EXPORT_PAGE_SIZE='1000'
```

Use a read-only Supabase database connection where possible. Do not paste the connection string into logs, tickets or screenshots. The exporter redacts credentials in `export-report.json`.

## Command

Development:

```bash
cd server
npm run supabase:export
```

Built artifact:

```bash
cd server
npm run build
npm run supabase:export:prod
```

## Output

```text
exports/supabase/<run>/
├── data/<schema>.<table>.ndjson
├── schema/tables.json
├── storage/objects.ndjson
└── export-report.json
```

`export-report.json` is the handoff artifact for T5.2/T5.3. It must include:

- selected schemas;
- exported table list;
- column metadata;
- primary key columns;
- row counts;
- SHA-256 checksums per table;
- storage object count and per-bucket counts when `storage.objects` is available;
- warnings for skipped storage manifest or missing source tables.

## Acceptance Check

1. `npm run typecheck` passes.
2. `npm test` passes.
3. Export command completes with no credential leakage.
4. `export-report.json` exists and includes counts/checksums.
5. If `storage.objects` is available, `storage/objects.ndjson` exists and bucket counts are non-negative.
