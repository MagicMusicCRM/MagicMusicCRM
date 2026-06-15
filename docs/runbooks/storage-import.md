# MagicMusicCRM v3 Storage Import Runbook

This runbook covers T5.3: move Supabase Storage objects into v3 private local storage and generate a file map for the data importer.

## Order

Run storage import before the final data import:

1. `npm run supabase:export`
2. `npm run storage:import`
3. `npm run migration:import` with `SUPABASE_FILE_MAP`

This allows the data importer to set `avatar_file_id`, `messages.attachment_file_id` and `channel_posts.attachment_file_id`.

## Required inputs

```bash
SUPABASE_URL='https://xblpnywnlhfgofskbdxb.supabase.co'
SUPABASE_SERVICE_ROLE_KEY='***'
SUPABASE_EXPORT_DIR='exports/supabase/2026-06-11-dry-run-1'
FILE_STORAGE_ROOT='/opt/magicmusiccrm/storage'
```

For database insertion of `app.file_objects`, also provide:

```bash
TARGET_DATABASE_URL='postgresql://magiccrm_owner:***@localhost:5432/magiccrm_v3'
MIGRATION_DRY_RUN=true
```

Without `TARGET_DATABASE_URL` / `DATABASE_URL`, the tool runs in manifest-only mode and still downloads files and writes `file-import-report.json`.

## Dry-run

```bash
SUPABASE_URL='https://xblpnywnlhfgofskbdxb.supabase.co' \
SUPABASE_SERVICE_ROLE_KEY='***' \
SUPABASE_EXPORT_DIR='exports/supabase/2026-06-11-dry-run-1' \
FILE_STORAGE_ROOT='/opt/magicmusiccrm/storage' \
TARGET_DATABASE_URL='postgresql://magiccrm_owner:***@localhost:5432/magiccrm_v3' \
MIGRATION_DRY_RUN=true \
npm run storage:import
```

Output:

```text
exports/supabase/<run>/file-import-report.json
```

The report contains:

- downloaded object count;
- skipped objects with reasons;
- local private storage keys;
- SHA-256 checksum per file;
- legacy lookup keys for URL/path rewrite;
- no service role key.

## Data import with file map

```bash
TARGET_DATABASE_URL='postgresql://magiccrm_owner:***@localhost:5432/magiccrm_v3' \
SUPABASE_EXPORT_DIR='exports/supabase/2026-06-11-dry-run-1' \
SUPABASE_FILE_MAP='exports/supabase/2026-06-11-dry-run-1/file-import-report.json' \
MIGRATION_DRY_RUN=true \
npm run migration:import
```

## Live cutover

Only after two passing dry-runs:

```bash
SUPABASE_URL='https://xblpnywnlhfgofskbdxb.supabase.co' \
SUPABASE_SERVICE_ROLE_KEY='***' \
SUPABASE_EXPORT_DIR='exports/supabase/final-cutover' \
FILE_STORAGE_ROOT='/opt/magicmusiccrm/storage' \
TARGET_DATABASE_URL='postgresql://magiccrm_owner:***@localhost:5432/magiccrm_v3' \
MIGRATION_DRY_RUN=false \
npm run storage:import
```

Then run the live data import with the generated `file-import-report.json`.

## Notes

- Bucket `avatars` maps to `profile_avatar`.
- Bucket `chat-attachments` maps to `chat_attachment`, or `chat_voice` for audio MIME/object names.
- Unknown buckets map to `crm_document`.
- Files are stored under `private/legacy/<bucket>/<object-id>/<safe-name>`.
- The service role key is required only to read private Supabase Storage objects; it is never written to reports.
