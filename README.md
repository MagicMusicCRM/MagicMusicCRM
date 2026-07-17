# Magic Music CRM

Magic Music CRM is a private Flutter + NestJS CRM for music-school operations:
clients, leads, teachers, schedules, lessons, payments, subscriptions, homework,
messenger, files, notifications, legal consent and account deletion.

The app UI is Russian-first. The active runtime is the owned v3 backend:
Flutter talks to the Magic Music API, not directly to Supabase.

## Status Snapshot

Updated: 2026-07-17.

- App version: `1.2.1+142`.
- Current public v3 API: `https://api.magicmusiccrm.ru/api` (host
  `161.104.49.153`). The older `api.phantom-net.ru` is dead — do not use it.
- Client: Flutter/Dart, Riverpod, GoRouter, Dio, Socket.IO client, Sentry,
  Firebase Messaging and Syncfusion widgets.
- Backend: NestJS 11, TypeScript, PostgreSQL, Redis, Socket.IO realtime,
  private local file storage and encrypted backups.
- Active architecture: `.anws/v3` (Backend Independence).
- Active product track: v7 redesign migration onto the existing app, reskin
  and reflow first, no backend rewrite.
- Current database migration chain: `0001` through `0068` (prod deployed at
  `0068`).
- Windows desktop has an in-app self-updater (no store): the app polls
  `https://api.magicmusiccrm.ru/downloads/latest.json` on launch. Android/iOS
  update through their stores.
- Supabase is retained only as legacy export/import tooling. It is not a
  Flutter runtime dependency.
- HolliHop is a backend-only import/reference source. Keys never belong in
  Flutter, Git, Linear, logs or public docs.

## What Is Implemented

Core product:

- Email/password auth, OTP, password reset, refresh-token rotation, logout-all
  and optional Google OAuth backend boundary.
- Release/legal gate, current legal documents, consent capture and account
  deletion request lifecycle.
- Role-aware CRM for `client`, `teacher`, `admin`, `manager` and
  `system_admin`.
- Profiles, students, leads, teachers, staff, rooms, branches, groups,
  lessons, attendance, comments, tasks, families and data-quality tools.
- Lead board, lead-to-student conversion, student/lead client card, duplicate
  detection, merge/undo merge and phone review queue.
- Payments, expected payments, expenses, student balances, subscriptions,
  subscription-package catalog and hour-based subscription consumption.
- Homework with files, teacher assignment, client submission and file-backed
  attachments.
- Messenger REST plus Socket.IO realtime for direct/admin/group/channel flows,
  typing/presence, reactions, pinning, delete, forwarding and chat work history.
- Private file uploads and one-time download tokens for chat, voice, avatars
  and homework attachments.
- Notifications, device registration, in-app notification list, broadcast and
  provider fallback.
- Analytics namespace for overview, dashboards, funnel, branches, loss reasons,
  debts, forecast, churn risk, chat SLA, sources, data quality, responsible
  distribution, weekly report and monthly finance exports.

Operational state from the latest audits:

- Backend was deployed to the current API endpoint on 2026-06-25.
- Staging health and realtime smoke passed after the latest migrations.
- Latest recorded full backend suite: 43 suites / 432 tests passed.
- Latest recorded Flutter gate: `flutter analyze` clean and 233 tests passed.
- Windows release and Android debug builds were produced during the 2026-06-25
  business/realtime audit.
- The performance audit did not confirm 10-20 second latency for single REST
  endpoints; the main issues are screen waterfalls, heavy DTOs, two SQL hot
  paths and broad realtime refetch.

## Recent Changes (2026-07)

- Windows in-app self-update (manifest on our Caddy + version check + helper
  that swaps files and relaunches). See "Windows self-update" below.
- Client card cleanup: cross-half comment de-duplication for converted clients;
  removed the legacy Invoices, Contracts and Progress tabs and the
  "change price" / "edit contract" actions.
- Client card now surfaces HolliHop fields backfilled into `custom_data`
  (responsible, HolliHop status, ad source, appeal type, visit date, contacts,
  UTM, lead type) via a self-hiding "Дополнительно" section.
- HolliHop field backfill: gender, age, birthday, category, disciplines,
  levels, ad source, appeal date, responsible and status filled into existing
  lead/student cards from the exports (matched by stored `hollihopId`,
  fill-missing merge — no duplicates, no student→lead demotion).
- Auth: fixed re-login-after-logout on Windows (token store now keeps an
  in-process authoritative cache so a lagging Credential Manager read can't
  resurrect a stale/empty session). Kanban column reorder is now an explicit
  save.
- Migrations `0066`–`0068` (section-view counters, deleted-message payload,
  task priority) deployed to prod.

## v7 Redesign Track

The approved v7 prototype is `docs/prototypes/crm-redesign-v7.html`. It is a
design and interaction spec, not the application.

The migration rule is strict: rebind v7 screens to the existing Flutter
services and backend endpoints. Pure frontend phases must keep `server/`
untouched, and every backend endpoint must keep a UI home.

Key tracking docs:

- `docs/migration/REDESIGN-MIGRATION-PLAN.md`
- `docs/migration/WIRE-TO-SERVICE-CHECKLIST.md`
- `docs/migration/P7-REGRESSION-EVIDENCE.md`
- `docs/audit/REDESIGN-COVERAGE-REPORT.md`
- `docs/audits/business-realtime-2026-06-25/report.md`
- `docs/audits/performance-2026-06-25/report.md`

Current notable remaining work:

- Complete runtime/device validation for v7 gesture-heavy and media-heavy
  surfaces: schedule drag/sticky headers, voice playback, gallery attachment
  and Windows manager re-audit.
- Run the P6 data-cleanup track against real data with dry-run evidence before
  apply: overlaps, fake emails, phone normalization, lesson split and missing
  comments.
- Continue performance hardening: lighter DTOs, fewer screen waterfalls,
  targeted realtime invalidation, `/admin/profiles` and room-availability SQL
  rewrites.
- Owner per-window acceptance against the v7 prototype.

## Repository Layout

```text
lib/                         Flutter client
lib/core/api/                Magic API client, token store and API providers
lib/core/services/           v3 service layer for CRM, messenger, files, etc.
lib/features/                Role and feature UI: auth, CRM, manager, client...
server/                      NestJS backend
server/src/                  API modules, services, smoke scripts and workers
server/db/migrations/        PostgreSQL migrations
infra/                       Docker, Caddy, deploy, backup and monitor scripts
docs/                        Runbooks, audits, migration plans and evidence
.anws/v3/                    Architecture, ADRs, tasks and release evidence
scripts/                     Helper scripts for Android, imports and staging
integration_test/            Flutter integration smoke
test/                        Flutter unit/widget tests
```

## Runtime Architecture

```text
Flutter app
  -> HTTPS REST: NestJS API
  -> Socket.IO: /realtime gateway

NestJS API
  -> PostgreSQL app schema
  -> Redis
  -> private file storage
  -> notification providers
  -> audit and security gates
```

The backend is the authorization source of truth. Files are referenced by
backend file IDs and downloaded through one-time tokens. Realtime room joins are
server-authorized. Flutter stores v3 session tokens in platform secure storage.

## Local Development

Prerequisites:

- Flutter SDK compatible with Dart `^3.11.1`
- Node.js and npm
- PostgreSQL/Redis when running the backend locally
- Android Studio or Windows build tooling when building platform artifacts

Install dependencies:

```powershell
flutter pub get
cd server
npm install
```

Run the Flutter app against the current API:

```powershell
flutter run --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api
```

Optional runtime/build defines:

```text
MAGIC_API_BASE_URL          API base URL, defaults to https://api.magicmusiccrm.ru/api
MAGIC_PROFILE               local secure-storage namespace for multi-window sessions
SENTRY_DSN                  enables Sentry when non-empty
SENTRY_ENVIRONMENT          defaults to production
SENTRY_RELEASE              release label
SENTRY_TRACES_SAMPLE_RATE   defaults to 0
```

## Verification

Flutter:

```powershell
flutter analyze
flutter test
```

Backend:

```powershell
cd server
npm run typecheck
npm test
npm run build
npm audit --audit-level=moderate
```

Staging realtime smoke:

```powershell
cd server
npm run smoke:realtime
```

Security gate:

```powershell
cd server
npm run security:gate
```

For documentation-only changes, at minimum run:

```powershell
git diff --check
```

## Backend And Migrations

Common backend scripts:

```powershell
cd server
npm run start:dev
npm run db:migrate
npm run db:rollback
npm run migration:import
npm run hollihop:import
npm run storage:import
```

Production/staging scripts use the compiled `dist/` commands:

```bash
node dist/db/migrate.js up
node dist/migration/v3-import.js
node dist/migration/hollihop-import.js
node dist/migration/storage-import.js
```

Real env files are ignored. Do not commit secrets, database URLs, service-role
keys, HolliHop keys, Firebase private keys, Telegram tokens, backup archives,
storage objects or generated release binaries.

## Staging Operations

Staging runtime lives under `infra/staging/` and is driven by ignored env files.
Use `infra/staging/README.md` and the runbooks before deploying.

Basic host flow:

```bash
cd /opt/magicmusiccrm/infra/staging
docker compose --env-file .env config -q
docker compose --env-file .env up -d --build
docker compose --env-file .env exec api node dist/db/migrate.js up
docker compose --env-file .env ps
```

Health checks:

```bash
curl -fsS https://api.magicmusiccrm.ru/api/health
curl -fsS https://api.magicmusiccrm.ru/api/health/ready
```

Create an encrypted backup before DB-affecting deploy/import work:

```bash
cd /opt/magicmusiccrm/infra/staging
bash /opt/magicmusiccrm/infra/scripts/backup-staging.sh
```

Rollback runbook: `docs/runbooks/v3-staging-rollback.md`.

## Release Builds

Always pass the live API URL. For Windows also pass `APP_BUILD_NUMBER` (the
build number from `pubspec.yaml`) so the in-app self-updater knows which build
is running — without it the updater stays disabled.

Windows:

```powershell
flutter build windows --release `
  --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api `
  --dart-define=APP_BUILD_NUMBER=142
```

Android APK / App Bundle (updated through the store, no build-number define
needed):

```powershell
flutter build apk --release --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api
flutter build appbundle --release --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api
```

Android release signing needs `android/key.properties` + `android/upload-keystore.jks`
(both git-ignored). Build outputs under `build/` are intentionally ignored.

### Windows self-update

Windows has no store, so the app updates itself from a manifest we host on our
own server. On launch it polls `https://api.magicmusiccrm.ru/downloads/latest.json`;
if the published `buildNumber` is higher than the running one, it offers to
install. A detached PowerShell helper waits for the app to exit, downloads and
SHA-256-verifies the zip, unpacks it over the install directory and relaunches
(on any failure it just relaunches the current build).

Publishing a new Windows release:

1. Build Windows with `APP_BUILD_NUMBER` set (above) and package the
   `dist/MagicMusicCRM-<x.y.z-build>-windows-x64.zip`.
2. Run the publish helper — it hashes the zip, writes `dist/latest.json` and
   uploads both to the server:

   ```powershell
   ./scripts/publish-windows-update.ps1 -BuildNumber 143 -Version "1.2.1+143" -Notes "Что нового"
   ```

Caddy serves `/downloads/*` from `/opt/magicmusiccrm/downloads` (a read-only
bind mount). Clients below the published build get the in-app prompt on their
next launch. Code signing is not yet configured, so Windows SmartScreen still
warns on first run.

## Documentation Index

- `AGENTS.md` - current agent protocol, project state and active priorities.
- `.anws/v3/01_PRD.md` - v3 requirements.
- `.anws/v3/02_ARCHITECTURE_OVERVIEW.md` - backend independence architecture.
- `.anws/v3/03_ADR/` - architecture decisions.
- `.anws/v3/05_TASKS.md` - v3 task and acceptance ledger.
- `.anws/v3/09_S7_RELEASE_EVIDENCE.md` - pre-release evidence.
- `docs/migration/REDESIGN-MIGRATION-PLAN.md` - v7-to-prod plan.
- `docs/migration/P7-REGRESSION-EVIDENCE.md` - redesign regression ledger.
- `docs/audits/` - latest business, UX, realtime and performance audits.
- `docs/runbooks/` - operational runbooks.
- `infra/staging/README.md` - staging deployment notes.

Agent note: read `AGENTS.md` first. The existing `.nexus-map/` was generated
before the v3 backend cutover and is useful as historical context, not as the
current source of truth.
