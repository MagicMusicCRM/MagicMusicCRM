# Magic Music CRM

Magic Music CRM is a private Flutter + NestJS CRM for music-school operations:
clients, leads, teachers, schedules, lessons, payments, subscriptions, homework,
messenger, files, notifications, legal consent and account deletion.

The app UI is Russian-first. The active runtime is the owned v3 backend:
Flutter talks to the Magic Music API, not directly to Supabase.

## Status Snapshot

Updated: 2026-06-26.

- App version: `1.1.23+134`.
- Current public v3 API: `https://api.phantom-net.ru/api`.
- Client: Flutter/Dart, Riverpod, GoRouter, Dio, Socket.IO client, Sentry,
  Firebase Messaging and Syncfusion widgets.
- Backend: NestJS 11, TypeScript, PostgreSQL, Redis, Socket.IO realtime,
  private local file storage and encrypted backups.
- Active architecture: `.anws/v3` (Backend Independence).
- Active product track: v7 redesign migration onto the existing app, reskin
  and reflow first, no backend rewrite.
- Current database migration chain: `0001` through `0049`.
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
flutter run --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Optional runtime/build defines:

```text
MAGIC_API_BASE_URL          API base URL, defaults to https://api.phantom-net.ru/api
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
curl -fsS https://api.phantom-net.ru/api/health
curl -fsS https://api.phantom-net.ru/api/health/ready
```

Create an encrypted backup before DB-affecting deploy/import work:

```bash
cd /opt/magicmusiccrm/infra/staging
bash /opt/magicmusiccrm/infra/scripts/backup-staging.sh
```

Rollback runbook: `docs/runbooks/v3-staging-rollback.md`.

## Release Builds

Windows:

```powershell
flutter build windows --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Android APK:

```powershell
flutter build apk --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Android App Bundle:

```powershell
flutter build appbundle --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Build outputs under `build/` are intentionally ignored.

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
