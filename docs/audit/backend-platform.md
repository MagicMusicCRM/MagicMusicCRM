# Backend Platform Audit — Auth / Security / Settings / Legal / Profile / Audit / Config

Audit date: 2026-06-21
Scope: `server/src/{auth,security,audit,settings,legal,profile,config}/**`

---

## 1. Overview

MagicMusicCRM is a NestJS/PostgreSQL backend for a Russian music school CRM. The platform uses JWT access tokens (short-lived, HS256) paired with opaque refresh tokens stored in the database. Authentication is email/password with mandatory email verification. Optional per-user email-OTP second factor is supported. Google OAuth routes exist in code but are intentionally tombstoned with `GoneException`. Five user roles are defined in a strict hierarchy. All mutating actions emit structured audit events to `app.audit_events`. Legal consent tracking and GDPR-style account-deletion workflows are first-class features.

---

## 2. Features

### Auth (`server/src/auth/`)

- **POST /auth/signup** — registers a new user with email + password + full name; always assigns `client` role; creates profile row; sends email-OTP verification challenge; emits `auth.signup` audit event.
- **POST /auth/login** — authenticates with email + password; enforces rate limit (10 failed attempts per 15 min window using audit event counts); blocks unverified emails; supports OTP-2FA gate: if `email_otp_2fa_enabled`, returns `emailOtpRequired: true` instead of tokens.
- **POST /auth/verify-email** — consumes a single-use email-verification token (SHA-256 hashed); sets `email_verified_at`; emits `auth.email_verified`.
- **POST /auth/otp/request** — sends a fresh 6-digit OTP (valid 10 min) to an existing user's email; rate-limited to 5 OTPs per 10 min window per email hash; emits `auth.otp_requested`.
- **POST /auth/otp/verify** — validates 6-digit OTP (stored as `email:code` SHA-256 hash); consumes it atomically; issues session tokens if `email_otp_2fa_enabled`, otherwise only confirms identity; emits `auth.otp_verified`.
- **POST /auth/password-reset/request** — issues a 6-digit reset code (30 min TTL); rate-limited to 3 requests per 15 min per user; emails the code; emits `auth.password_reset_requested`; always returns `{accepted:true}` to prevent enumeration.
- **POST /auth/password-reset/confirm** — consumes the reset token, sets new password hash, revokes all existing sessions; emits `auth.password_reset_completed`.
- **POST /auth/password** (JWT-guarded) — sets or changes password for the authenticated user without requiring old password; emits `auth.password_changed`.
- **GET /auth/identities** (JWT-guarded) — lists the authentication providers linked to the account (email if password_hash is set, plus any OAuth identities from `app.user_identities`).
- **POST /auth/refresh** — rotates refresh token; detects refresh-token reuse (token already revoked or replaced): revokes the entire token family and emits `auth.refresh_reuse_detected`; emits `auth.session_rotated` on success.
- **POST /auth/logout-all** (JWT-guarded) — revokes all active refresh sessions for the user; emits `auth.logout_all`.
- **POST /auth/google/start|callback|id-token|link-id-token** — all permanently disabled (return `GoneException`); Google OAuth is dead code in current deployment.
- **PasswordService** — passwords hashed with scrypt (salt 16 B random, key length 64 B); stored as `scrypt$<hex-salt>$<hex-derived>`; compared with `timingSafeEqual`.
- **SessionService** — access token is a signed JWT (`sub`, `role`); refresh token is 48 random bytes (base64url); refresh tokens stored as SHA-256 hashes in `app.refresh_sessions` with `family_id` for reuse detection; configurable TTLs via env.
- **Email notifications on auth errors** — failures to enqueue email are silently caught and logged as `notifications.email_enqueue_failed` audit event (non-fatal).

### Security Gate (`server/src/security/security-gate.ts`)

- **CI/pre-deploy script** — run standalone (not a runtime HTTP endpoint); checks: `git diff --check` (whitespace/conflict markers); verifies `server/exports` and `server/storage` are git-ignored and docker-ignored; scans for tracked/unignored `.env` files; checks for generated `.map` source-map files; checks Flutter runtime for leaked legacy Supabase dart-defines or `HOLLIHOP_AUTH_KEY`; runs `npm audit --audit-level=moderate`; checks availability of `gitleaks`, `semgrep`, `trivy`, Docker daemon.
- **Strict mode** — `SECURITY_GATE_STRICT=1` env var turns `warn` results into `fail`; exits with code 1 on any `fail`.
- **Outputs** — JSON summary `{strict, summary:{pass,warn,fail}, results:[{name,status,detail}]}` to stdout.

### Audit (`server/src/audit/`)

- **AuditService.record()** — single method; inserts into `app.audit_events(actor_user_id, action, entity_type, entity_id, metadata::jsonb)`; metadata is passed through `redactSensitive()` before storage (PII scrubbing).
- **No query/read endpoint** — audit events are write-only from API perspective; no admin endpoint to retrieve them exists in this module.
- **Events recorded across modules**: `auth.signup`, `auth.login_password`, `auth.login_failed`, `auth.login_email_unverified`, `auth.login_email_otp_required`, `auth.otp_requested`, `auth.otp_verified`, `auth.otp_verify_failed`, `auth.otp_rate_limited`, `auth.otp_verify_rate_limited`, `auth.password_reset_requested`, `auth.password_reset_rate_limited`, `auth.password_reset_completed`, `auth.password_changed`, `auth.email_verified`, `auth.session_issued`, `auth.session_rotated`, `auth.logout_all`, `auth.refresh_reuse_detected`, `legal.consents_accepted`, `legal.deletion_requested`, `legal.deletion_status_updated`, `profile.updated`, `profile.note_created`, `profile.crm_student_linked`, `profile.crm_lead_linked`, `profile.crm_teacher_linked`, `profile.crm_staff_linked`, `profile.role_updated`, `settings.admin_chat_avatar_updated`, `settings.crm_custom_fields_updated`, `notifications.email_enqueue_failed`.

### Settings (`server/src/settings/`)

- **GET /settings/admin-chat-avatar** (JWT-guarded, all roles) — returns the current admin-chat avatar URL from `app.system_settings`.
- **GET /settings/crm-custom-fields** (JWT-guarded, all roles) — returns current custom field schema; falls back to hardcoded defaults if not yet configured.
- **PATCH /admin/settings/admin-chat-avatar** (JWT + RolesGuard, `admin` only) — sets or clears the admin chat avatar; accepts `storage://avatars/<path>` or `https://` URLs; rejects all others; audits change.
- **PATCH /admin/settings/crm-custom-fields** (JWT + RolesGuard, `admin` only) — replaces the full custom field schema; validates each field definition (entity in students/leads/teachers, type in text/number/date/phone/email/url/select/boolean, key regex `[A-Za-z][A-Za-z0-9_]*`, duplicate key detection, options required for `select`); max 80 fields; audits change.
- **Default CRM custom fields** — pre-seeded defaults in code: students: `hollihopId`, `middleName`, `discipline` (select), `level` (select), `individualPrice` (number); leads: `source` (select), `discipline` (select); teachers: `discipline` (select).

### Legal (`server/src/legal/`)

- **GET /legal/gate** (JWT-guarded) — returns `{role, profileComplete, legalAccepted, deletionPending}` in a single query; used by clients to determine if they must accept docs or complete profile before accessing the app.
- **GET /legal/documents/current** (JWT-guarded) — lists all documents where `is_current = true`; returns `id, type, title, version, url, fileId, publishedAt`.
- **POST /legal/consents/current** (JWT-guarded) — bulk-accepts all current documents; validates that the submitted `documentIds` set exactly matches the current documents set (rejects partial or superset); records IP hash and user-agent hash as evidence; uses `on conflict do nothing` for idempotency; audits.
- **POST /profile/deletion-request** (JWT-guarded) — creates an account-deletion request for self; if an active (pending/processing) request already exists, returns it instead of creating a duplicate.
- **GET /profile/deletion-request** (JWT-guarded) — returns the most recent deletion request for the current user (any status), or null.
- **GET /admin/deletion-requests** (JWT + RolesGuard, `manager|admin|system_admin`) — paginated list of all deletion requests with user email; filterable by `status`; max 100 per page.
- **PATCH /admin/deletion-requests/:id** (JWT + RolesGuard, `admin` only) — updates deletion request status with enforced state machine; on `completed`: soft-deletes user and profile rows, revokes all refresh sessions in the same transaction; records `resolved_by` and optional `resolution_note`.
- **LegalPolicy** — `assertCanListDeletionRequests`: manager+; `assertCanUpdateDeletionRequest`: admin+; `assertCanReadDeletionRequest`: own userId or manager+; transition rules enforced.
- **Document types** — `privacy_policy`, `terms_of_use`, `account_deletion`.
- **Deletion status machine** — `pending → processing | cancelled`; `processing → completed | rejected`; `completed`, `rejected`, `cancelled` are terminal.

### Profile (`server/src/profile/`)

- **GET /profile/me** (JWT-guarded) — returns own profile; auto-creates profile row if missing.
- **PATCH /profile/me** (JWT-guarded) — updates firstName, lastName, phone, dob, emailOtp2faEnabled, avatarFileId; validates avatar file ownership (`purpose = 'profile_avatar'`); when firstName+lastName+phone all become non-empty: marks `profile_completed = true`, `phone_verified_at = now()`, and triggers auto-link by phone; audits.
- **GET /admin/profiles** (JWT + RolesGuard, `manager|admin|system_admin`) — paginated list (max 100); filterable by role and free-text search (name+email+phone); includes linked/candidate CRM entity counts per profile.
- **GET /admin/profiles/:id** (JWT + RolesGuard, `manager|admin|system_admin`) — full profile detail; policy allows manager+ or own userId.
- **GET /admin/profiles/:id/notes** (JWT + RolesGuard, `manager|admin|system_admin`) — lists CRM notes on a profile (max 100, newest first) with author info.
- **POST /admin/profiles/:id/notes** (JWT + RolesGuard, `manager|admin|system_admin`) — creates a profile note; body must be non-empty; records author; audits.
- **GET /admin/profiles/:id/link-candidates** (JWT + RolesGuard, `manager|admin|system_admin`) — returns CRM entity candidates (students, leads, teachers, staff) matchable by phone; excludes already-linked or exclusively-linked-to-other-user entities.
- **POST /admin/profiles/:id/links/auto** (JWT + RolesGuard, `manager|admin|system_admin`) — triggers auto-link by phone for all entity types simultaneously; same logic as profile completion auto-link.
- **POST /admin/profiles/:id/links** (JWT + RolesGuard, `manager|admin|system_admin`) — manually links a specific CRM entity (student/lead/teacher/staff) to a profile by entity ID; validates phone match and exclusivity before linking; audits each link type.
- **PATCH /admin/profiles/:id/role** (JWT + RolesGuard, `manager|admin|system_admin`) — updates user role to any valid role; guards against removing the last `system_admin` (DB count check); audits.
- **ProfilePolicy** — `assertCanListProfiles`: manager+; `assertCanReadProfile`: manager+ or own userId; `assertCanUpdateRole`: manager+.
- **Phone normalization** — Russian phone numbers normalized to canonical form via `normalizePhoneRu`; matching uses a SQL expression for consistent comparison.
- **CRM link exclusivity** — a CRM entity (student/lead/teacher/staff) can only be linked to one user at a time (enforced in all linking queries via `not exists` subquery checking `user_crm_links.user_id <> current_user`).

### Config (`server/src/config/`)

- **Env validation schema (Joi)** — validates and applies defaults for: `NODE_ENV`, `PORT`, `CORS_ALLOWED_ORIGINS`, `DATABASE_URL` (required, postgres URI), `JWT_ACCESS_SECRET` (min 32 chars, has insecure default for dev), `ACCESS_TOKEN_TTL_SECONDS` (60–3600, default 900), `REFRESH_TOKEN_TTL_DAYS` (1–90, default 30), `FILE_STORAGE_ROOT`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `RESEND_TIMEOUT_MS`, `SMTP_FALLBACK_HOST/PORT/SECURE/USER/PASSWORD/FROM_EMAIL`, `FIREBASE_SERVER_KEY/PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY/TIMEOUT_MS`, `NOTIFICATION_TOKEN_ENCRYPTION_KEY`, `LESSON_REMINDERS_ENABLED`, `HOLLIHOP_BASE_URL/AUTH_KEY/TIMEOUT_MS`.

---

## 3. Per-Role Behavior / Permissions

| Role | Description | Key Permissions |
|---|---|---|
| `client` | End user (student/parent) | Auth flows, own profile R/W, own deletion request R/W, legal gate/consent |
| `teacher` | Music teacher | Same as client; no admin endpoints |
| `manager` | School manager | All client perms + list/read all profiles, list deletion requests, create profile notes, link CRM entities, update roles |
| `admin` | School administrator | All manager perms + update deletion request status (including executing account deletion), update system settings (avatar, custom fields) |
| `system_admin` | System superuser | Bypasses `RolesGuard` entirely (checked as first condition in guard); all endpoints accessible; cannot be the sole system_admin being demoted (protected) |

Role hierarchy in code: `isManagerOrAdminRole` = manager|admin|system_admin; `isAdminRole` = admin|system_admin; `isStaffRole` = admin|manager|system_admin.

`RolesGuard` note: `system_admin` is hardcoded as a bypass — it always returns `true` regardless of the `@Roles()` decorator value. All other roles must explicitly appear in the decorator.

---

## 4. Data / Schema Touched

| Table | Module | Notes |
|---|---|---|
| `app.users` | auth, profile, legal | `id, email, password_hash, role, email_verified_at, is_app_account, profile_completed, deleted_at, phone_verified_at` |
| `app.profiles` | auth, profile | `id, user_id, first_name, last_name, phone, dob, avatar_file_id, email_otp_2fa_enabled, deleted_at` |
| `app.refresh_sessions` | auth (session) | `id, user_id, token_hash, family_id, expires_at, revoked_at, replaced_by_id, last_used_at` |
| `app.otp_challenges` | auth | `id, user_id, email_hash, purpose ('email_verification'), code_hash, expires_at, consumed_at` |
| `app.email_verification_tokens` | auth | `id, user_id, token_hash, expires_at, consumed_at` |
| `app.password_reset_tokens` | auth | `id, user_id, token_hash, expires_at, consumed_at` |
| `app.user_identities` | auth | `user_id, provider` — OAuth identity linking (read-only in current code) |
| `app.audit_events` | audit | `id, actor_user_id, action, entity_type, entity_id, metadata::jsonb, created_at` |
| `app.legal_documents` | legal | `id, document_type, version, title, url, file_id, is_current, published_at` |
| `app.legal_consents` | legal | `user_id, document_id, version, ip_hash, user_agent_hash`; unique on `(user_id, document_id)` |
| `app.account_deletion_requests` | legal | `id, user_id, status, reason, requested_at, resolved_at, resolved_by, resolution_note, updated_at` |
| `app.system_settings` | settings | `key, value::jsonb, updated_by, updated_at`; keys: `admin_chat_avatar_url`, `crm_custom_fields` |
| `app.profile_notes` | profile | `id, profile_id, author_id, body, created_at, deleted_at` |
| `app.user_crm_links` | profile | `id, user_id, entity_type, entity_id, matched_phone, link_source, confirmed_at, created_by, deleted_at` |
| `app.students` | profile | `profile_id` field updated on student-to-profile link |
| `app.teachers` | profile | `profile_id` field updated on teacher-to-profile link |
| `app.staff_members` | profile | `profile_id` field updated on staff-to-profile link |
| `app.file_objects` | profile | Read-only: validates avatar ownership by `(id, owner_user_id, purpose='profile_avatar')` |

---

## 5. Notable Business Rules / Edge Cases

1. **Signup upsert**: if an email already exists as a non-app-account (e.g., imported CRM record), signup upgrades it in-place (sets password, name, role=client, is_app_account=true). If `is_app_account=true` already, throws `ConflictException`. This means a CRM-imported user can self-register without creating a duplicate.

2. **Rate limiting via audit log**: login and OTP rate limits are computed by counting audit events with specific actions within a time window — no Redis/in-memory counter. This means rate limit state survives restarts but creates coupling between audit data integrity and security enforcement. A bulk audit table purge would silently disable rate limiting.

3. **Email OTP dual purpose**: the same `otp_challenges` table and flow handles both initial email verification (for new signups) and 2FA at login. The `purpose` column is always `'email_verification'`; there is no separate 2FA purpose — the distinction is contextual.

4. **OTP verify session issuance logic is inverted**: `verifyOtp` issues a session only when `email_otp_2fa_enabled = true`; when 2FA is disabled it only verifies identity without issuing tokens. This is intentional (OTP without 2FA is used purely for email verification, not login).

5. **Password reset does not require old password**: `POST /auth/password` (set password while logged in) also does not verify the existing password. Any authenticated session can reset the password without friction — relevant for session hijack scenarios.

6. **Refresh token reuse detection revokes entire family**: detecting a reused (already-consumed or replaced) refresh token triggers revocation of all tokens in the same `family_id`, logging the user out of all devices. This is a correct security pattern.

7. **Account deletion is soft-delete only**: marking a deletion request `completed` soft-deletes `app.users` and `app.profiles` (sets `deleted_at`) and revokes all sessions, all in a single transaction. No hard deletion, no data purge, no anonymization occurs. GDPR erasure requirements are not fulfilled by this flow alone.

8. **Legal gate consent exactness check**: clients must submit exactly the full set of current document IDs — no subset, no superset allowed. This prevents partial consent and ensures the consent record covers every document in force at acceptance time.

9. **Last system_admin protection**: the service (not the policy) checks at DB level that at least one other active `system_admin` exists before allowing role demotion. This is the only such guard; no equivalent guard exists for `admin` role.

10. **CRM link exclusivity enforced per-link**: the same CRM entity cannot be linked to two different app users simultaneously; this is enforced by `not exists` checks in every linking query (both candidates discovery and the actual link insertion). However, the exclusivity check and the insert are not in a single transaction — a race condition between two concurrent link attempts for the same entity could theoretically succeed for both. The `insert ... where not exists` approach is not atomic without a unique constraint or advisory lock.

11. **`system_admin` role bypass in RolesGuard is unconditional**: the guard hardcodes `if (actor.role === 'system_admin') return true` before checking required roles. This is correct by design but means any future endpoint marked with a restrictive `@Roles()` decorator will automatically grant access to system_admin regardless of intent.

12. **JWT_ACCESS_SECRET has an insecure development default**: the Joi schema provides a default value `'dev-only-change-me-dev-only-change-me'`. If this is not overridden in production, JWTs are trivially forgeable.

13. **Admin chat avatar URL validation**: accepts `storage://avatars/` scheme (internal) or `https://` URLs only. HTTP and other schemes are rejected. No SSRF validation beyond scheme check.

14. **Profile completion auto-triggers CRM phone link**: when a user saves their profile with first name, last name, and phone all non-empty, the system immediately scans CRM for matching students/leads/teachers/staff and links them. This is silent from the user's perspective and may link unexpected records if phone numbers collide.

15. **Settings service double-validates custom fields**: validation occurs both in the DTO (class-validator decorators) and again in the service's `normalizeCustomFields()` method. The service-level check is more strict (e.g., the regex `^[A-Za-z][A-Za-z0-9_]*$` on keys is enforced in service but only by `@Matches` in DTO — these must stay in sync).

16. **No audit log retrieval API**: audit events are written from many modules but there is no endpoint to query or export them. Compliance use cases (export audit trail for a user) are unsupported at the API level.
