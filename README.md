# Magic Music CRM

Flutter CRM for Magic Music school operations: clients, teachers, managers,
admins, schedules, leads, payments, messenger, files, notifications, legal
consent and account deletion.

## Current State

- Client: Flutter / Dart, Riverpod, Russian UI.
- Backend: owned NestJS API, PostgreSQL, Redis, private file storage and
  Socket.IO realtime.
- Staging API: `https://api.phantom-net.ru/api`.
- Android package: `magic.crm`.
- Active architecture docs: `.anws/v3`.
- Active Linear context: `Magic Music CRM`, `KVA-117` stabilization and cutover.

Supabase runtime access has been removed from the active Flutter app. The client
uses the v3 API through `MagicApiClient`, `MagicAuthService`,
`MagicCrmService`, `MagicMessengerService`, `MagicRealtimeService`,
`MagicNotificationsService` and the private v3 File API.

## Repository Layout

```text
lib/                  Flutter client
server/               NestJS v3 backend
server/db/migrations  PostgreSQL migrations
infra/                Docker Compose, Caddy, backup and restore scripts
docs/                 runbooks and import notes
.anws/v3/             architecture, ADRs, tasks and release evidence
scripts/              smoke/import helper scripts
integration_test/     Flutter integration smoke
```

## Backend

The staging backend runs on Selectel under Docker Compose:

```text
api.phantom-net.ru -> Caddy -> NestJS API -> PostgreSQL / Redis
```

Core backend capabilities:

- password signup/login, email OTP verification, password reset and refresh
  rotation with reuse detection;
- RBAC and audit events;
- CRM APIs for profiles, students, teachers, staff, rooms, groups, lessons,
  leads, payments, reports, balances, tasks and comments;
- messenger REST plus Socket.IO realtime at `/realtime`;
- private file uploads and one-time download tokens;
- notifications device registration, in-app notifications and provider fallback;
- legal document gate and account deletion flow;
- HolliHop metadata/read/import path owned by the backend.

## Frontend

Default API base URL:

```text
https://api.phantom-net.ru/api
```

Override for local builds:

```powershell
flutter run --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

The app displays a branded loading gate while auth/session/legal state is being
checked. Login clears stale local sessions before storing a new v3 session, and
API token refresh is single-flight to avoid invalidating refresh token families
with parallel requests.

## Staging Deploy

Ignored server env files are required on the host:

```text
/opt/magicmusiccrm/infra/staging/.env
/opt/magicmusiccrm/infra/staging/.backup.env
```

Deploy from the staging host:

```bash
cd /opt/magicmusiccrm/infra/staging
docker compose --env-file .env config -q
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
```

Apply/check migrations:

```bash
docker compose --env-file .env exec api node dist/db/migrate.js up
```

Health checks:

```bash
curl -fsS https://api.phantom-net.ru/api/health
curl -fsS https://api.phantom-net.ru/api/health/ready
```

Create an encrypted staging backup before DB-affecting deploy/import work:

```bash
cd /opt/magicmusiccrm/infra/staging
bash /opt/magicmusiccrm/infra/scripts/backup-staging.sh
```

Latest verified staging sync in this branch:

- backup: `magicmusiccrm-staging-20260615T232343Z.tgz.enc`;
- backup SHA-256:
  `3cc61a3400b05d761392a8e5ef395f19eb204b494c5e151656ab22a619b0bfb6`;
- applied migrations through `0020_runtime_migration_read_grant`;
- `/api/health` and `/api/health/ready` returned `ok`;
- public realtime smoke passed against `https://api.phantom-net.ru/api`.

## HolliHop Import

HolliHop access is backend-only. Keys must stay in ignored env files or transient
process env, never in Flutter, Git, Linear or logs.

Run guarded archive/live dry-runs from the repo root:

```powershell
.\scripts\hollihop_staging_dry_run.ps1 `
  -BackupEvidencePath .supergoal\hollihop-crm-import-adaptation-loading-ux-Guw3IO\evidence\<backup-evidence-file>
```

The staging live apply completed with:

- source counts: `1025` students, `1946` leads, `3167` payments;
- stored HolliHop counts after apply: `1946` students, `1946` leads,
  `3166` payments, `2330` duplicate candidates;
- known warnings: `tasks_source_missing` and `timeline_sources_missing`.

## Local Development

Install Flutter and Node.js, then:

```powershell
flutter pub get
cd server
npm install
```

Run Flutter checks:

```powershell
flutter analyze
flutter test
```

Run backend checks:

```powershell
cd server
npm run typecheck
npm test
npm run build
npm audit --audit-level=moderate
```

Run realtime smoke against staging:

```powershell
cd server
npm run smoke:realtime
```

For users created by the smoke script, email verification may need a staging DB
test helper or a real OTP flow before login.

## Release Artifacts

Windows release ZIPs are built from:

```powershell
flutter build windows --release
```

Current verified local Windows ZIP:

```text
build/releases/MagicMusicCRM-Windows-x64-auth-refreshfix-20260616-020617.zip
SHA256 81416A8E37189F9BC768C6F6A44E5F41D2CFC6C86AC156037494A4B8772B4B65
```

Android debug smoke artifact:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Build outputs are intentionally ignored by Git.

## Remaining Launch Gates

- Real Android device smoke for private file upload/download.
- Real Android device smoke for account deletion.
- Production host hardening evidence.
- Credential rotation for exposed migration-era credentials.
- History-aware secret scan, external SAST and container scan.
- Production cutover rehearsal and production cutover window.

## Documentation Index

- `.anws/v3/05_TASKS.md` - v3 task blueprint.
- `.anws/v3/09_S7_RELEASE_EVIDENCE.md` - release evidence.
- `docs/runbooks/hollihop-staging-dry-run.md` - guarded HolliHop dry-run.
- `docs/runbooks/android-real-device-smoke.md` - remaining Android smoke.
- `docs/runbooks/v3-staging-rollback.md` - staging rollback.
- `docs/import/` - HolliHop import mapping and gap reports.
- `infra/staging/README.md` - staging deployment notes.
