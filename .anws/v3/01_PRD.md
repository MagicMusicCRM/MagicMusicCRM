# 01_PRD - MagicMusicCRM v3 Backend Independence

**Status**: Draft / Implementation baseline
**Version**: v3.0.0-draft
**Date**: 2026-06-10
**Owner**: Magic Music School
**Previous baseline**: `.anws/v2`

## 1. Цель версии

v3 должна убрать Supabase Cloud как runtime-зависимость и перевести MagicMusicCRM на собственный backend, размещенный на московском сервере, при сохранении функциональной полноты v2: auth, onboarding, legal consent, account deletion, CRM, messenger, private files, notifications and release security gates.

Главный критерий успеха: приложение работает в РФ без VPN, а данные, авторизация и файловый доступ контролируются инфраструктурой Magic Music.

## 2. Контекст

Custom Domain Supabase больше не решает проблему доступности из РФ. Reverse proxy на текущем московском VPS не подходит, потому что исходящий TLS до Google/Supabase нестабилен. Self-hosted Supabase снижает объем переписывания, но не дает желаемой независимости от платформы и оставляет чужую архитектурную модель.

Поэтому v3 выбирает собственный backend:

```text
Flutter app -> HTTPS/WebSocket API -> NestJS -> PostgreSQL / Storage / Workers
```

## 3. Целевые роли

- **Client / student / parent**: входит, проходит onboarding/legal, видит только свои данные, расписание, платежи, сообщения and files.
- **Teacher**: видит назначенных учеников, расписание, прогресс and permitted chats.
- **Manager**: работает с лидами, задачами, финансами and permitted communication surfaces.
- **Admin**: управляет ролями, пользователями, legal docs, deletion requests, announcements and security operations.
- **Operator / DevOps**: поддерживает сервер, backups, monitoring, deploy/cutover and incident response.

## 4. Product Scope

### In Scope

- Собственный NestJS backend API.
- PostgreSQL schema and migrations for current CRM data.
- Auth: email/password, email verification, OTP, refresh token rotation, password reset, logout-all-devices.
- Google OAuth as optional identity provider, not critical path.
- Profile, roles, onboarding, legal consent and account deletion.
- CRM APIs for current app entities.
- Messenger APIs plus WebSocket realtime for messages, presence, typing and notifications.
- Private file storage on primary NVMe with external encrypted backups.
- Notification API with Firebase optional fallback.
- Supabase full data and Storage migration.
- Big-bang cutover with 2-4 hour data freeze window.
- Security gates covering the 50-item security checklist.

### Non-Goals

- No automatic HA cluster in the first production version.
- No Kubernetes requirement for first launch.
- No public file bucket URLs.
- No frontend-only security checks.
- No reliance on Google OAuth, Resend or Firebase as single critical production path.
- No loss of existing user, CRM, chat, legal or file history.

## 5. Success Metrics

- App critical flows work from РФ without VPN after DNS cutover.
- 0 unresolved Critical/High security findings before production cutover.
- Full dry-run migration passes at least twice.
- Backup restore drill passes before production launch.
- Supabase direct SDK calls are removed from production app flows.
- Users cannot access other users' profiles, chats, files, payments or roles.
- Auth flows pass rate-limit, session, reset and token-lifecycle tests.
- Production logs contain no tokens, passwords, private file URLs or sensitive PII payloads.

## 6. Functional Requirements

### [REQ-V3-AUTH-001] Own auth and session service

**Priority**: P0
**Value**: Users can authenticate without Supabase Auth.

**Acceptance Criteria**

- Given a user signs up with email/password, When email verification succeeds, Then a profile is created with role `client`.
- Given a user logs in, When credentials are valid, Then backend issues short-lived access token and rotated refresh token.
- Given refresh token is reused after rotation, When backend detects reuse, Then affected session family is revoked and audit event is written.
- Given user requests password reset, When token is expired, reused or forged, Then reset is denied.

### [REQ-V3-AUTH-002] Optional Google OAuth

**Priority**: P1
**Value**: Google remains convenient but not required.

**Acceptance Criteria**

- Given Google OAuth is unavailable, When user chooses email/password, Then login still works.
- Given Google callback returns identity, When identity email matches or is linked, Then backend creates/links identity without trusting client-controlled role.
- Given callback has invalid state/redirect, When backend receives it, Then request is rejected and full token payload is not logged.

### [REQ-V3-DATA-001] Backend-enforced data isolation

**Priority**: P0
**Value**: Data privacy survives direct API calls.

**Acceptance Criteria**

- Given client A calls any endpoint with client B ID, When A lacks staff permission, Then API returns 403/404 and writes audit event where appropriate.
- Given request includes `role`, `user_id`, `created_by` or ownership fields, When backend processes it, Then trusted values are derived from authenticated session.
- Given manager/teacher/admin accesses CRM data, When role scope is evaluated, Then only permitted records are returned.

### [REQ-V3-MSG-001] Messenger and realtime

**Priority**: P0
**Value**: Current messenger behavior survives Supabase Realtime removal.

**Acceptance Criteria**

- Given a client sends a message to `Администрация`, When staff is online, Then staff receives realtime update.
- Given client A subscribes to a chat, When client B sends message in B's chat, Then A receives nothing.
- Given WebSocket reconnects, When session is valid, Then subscriptions are restored only for authorized rooms.

### [REQ-V3-FILES-001] Private file storage

**Priority**: P0
**Value**: Avatars and chat attachments are private by default.

**Acceptance Criteria**

- Given user uploads a file, When MIME/size/path validation passes, Then backend stores file outside web root and creates metadata row.
- Given user requests another user's private file, When no permission exists, Then API denies access.
- Given signed download token expires, When file URL is reused, Then download is denied.

### [REQ-V3-MIG-001] Full Supabase migration

**Priority**: P0
**Value**: v3 launches without losing history.

**Acceptance Criteria**

- Given Supabase export is available, When migration dry-run runs, Then users, roles, profiles, CRM data, chats, legal records and files are transformed into v3 schema.
- Given migration completes, When integrity checks run, Then record counts, required relationships and file references match expected report.
- Given cutover fails, When rollback decision is made within window, Then Supabase read-only reference and old app path remain available.

### [REQ-V3-OPS-001] Backups, monitoring and incident response

**Priority**: P0
**Value**: One primary server does not mean unbounded data-loss risk.

**Acceptance Criteria**

- Given daily backup job runs, When backup completes, Then encrypted DB and file backups exist outside primary server.
- Given restore drill runs, When backup is restored to clean environment, Then health and smoke checks pass.
- Given API health degrades, When alert threshold is crossed, Then operator receives alert within 5 minutes.

### [REQ-V3-SEC-001] Security gates

**Priority**: P0
**Value**: Launch is blocked by security regressions.

**Acceptance Criteria**

- Given CI runs, When secrets, dependency and container scans execute, Then Critical/High findings block merge.
- Given actor matrix tests run, When anon/client/teacher/manager/admin scenarios execute, Then no cross-user data access is possible.
- Given production build is prepared, When checklist runs, Then no public env files, source maps, debug routes or admin dashboards are exposed.

## 7. Non-Functional Requirements

- **Availability**: first v3 target is stable single-primary with fast restore, not automatic HA.
- **Security**: backend authorization is the only trusted access boundary.
- **Privacy**: logs redact tokens, passwords, OTP, private URLs and unnecessary PII.
- **Performance**: p95 API response for common CRM reads under 500 ms on normal load.
- **Recovery**: RPO target 24h for first launch, RTO target 4h after tested restore.
- **Localization**: visible app text remains Russian.

## 8. Edge Cases

- User loses email access after migration.
- Existing Google-only user needs password setup.
- File exists in Supabase Storage but metadata is missing.
- Chat references deleted or pending-deletion user.
- Refresh token is stolen and reused.
- SMTP primary provider is down.
- Firebase push is unavailable.
- Cutover fails after partial migration.
- Backup succeeds but restore fails due missing file snapshot.
