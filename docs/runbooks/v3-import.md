# MagicMusicCRM v3 Import Runbook

This runbook covers T5.2: transform a Supabase export package into the v3 `app` schema.

## Safety defaults

- The importer is dry-run by default: `MIGRATION_DRY_RUN=true`.
- Dry-run opens a database transaction, inserts the planned rows, writes `import-report.json`, and rolls back.
- Live import requires explicit `MIGRATION_DRY_RUN=false`.
- Reports redact database credentials and never store raw FCM tokens.
- Storage object download and file reference rewrite are deferred to T5.3.

## Inputs

Create the export first:

```bash
SUPABASE_DB_URL='postgresql://readonly:***@db.xblpnywnlhfgofskbdxb.supabase.co:5432/postgres' \
SUPABASE_EXPORT_DIR=exports/supabase/2026-06-11-dry-run-1 \
npm run supabase:export
```

Expected source package shape:

```text
exports/supabase/<run>/
  export-report.json
  schema/tables.json
  data/auth.users.ndjson
  data/public.profiles.ndjson
  data/public.lessons.ndjson
  storage/objects.ndjson
```

## Dry-run import

Run against a freshly migrated v3 PostgreSQL database:

```bash
TARGET_DATABASE_URL='postgresql://magiccrm_owner:***@localhost:5432/magiccrm_v3' \
SUPABASE_EXPORT_DIR=exports/supabase/2026-06-11-dry-run-1 \
MIGRATION_DRY_RUN=true \
npm run migration:import
```

Review:

```bash
jq '.totals, .tables, .skippedSources, .warnings' exports/supabase/2026-06-11-dry-run-1/import-report.json
```

Dry-run acceptance:

- `plannedRows` is close to source rows, excluding known system tables.
- `skippedRows` are explained in `skippedSources`.
- No database constraint error is raised.
- Warnings are limited to expected follow-ups: file references, legal content conversion, missing optional source files.

## Live import

Only after two passing dry-runs:

```bash
TARGET_DATABASE_URL='postgresql://magiccrm_owner:***@localhost:5432/magiccrm_v3' \
SUPABASE_EXPORT_DIR=exports/supabase/final-cutover \
MIGRATION_DRY_RUN=false \
npm run migration:import
```

## Current mapping notes

- Supabase `auth.users` and `public.profiles` become `app.users` and `app.profiles`.
- Supabase password hashes are not reused; users must use the v3 password reset or email verification flow.
- CRM tables map into `app.branches`, `rooms`, `lead_statuses`, `leads`, `students`, `teachers`, `groups`, `lessons`, `payments`, `subscriptions`, comments and notes.
- Direct messenger rows without `group_chat_id` get deterministic synthetic v3 direct chat IDs.
- `group_chats`, `group_chat_members`, channels and channel posts map into v3 messenger/channel tables.
- FCM tokens map to `app.notification_devices` as SHA-256 hashes only; raw tokens are intentionally not preserved in reports.
- Legacy `avatar_url`, `attachment_url` and Supabase Storage objects are left for T5.3 file migration.
