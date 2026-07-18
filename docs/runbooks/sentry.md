# Sentry Runbook

## Purpose

Sentry is optional client-side observability for Flutter release builds. It captures unhandled Flutter errors plus explicit auth/API failures around login, signup and Google OAuth.

## Privacy Rules

- Do not store Sentry DSN in Git.
- Do not capture request bodies, passwords, refresh tokens, access tokens or emails.
- User context is limited to backend user id and role.
- API events use sanitized paths without query strings.

## Build Flags

Sentry is disabled unless `SENTRY_DSN` is provided at build time.

```powershell
flutter build appbundle --release --build-name=1.1.7 --build-number=117 `
  --dart-define=MAGIC_API_BASE_URL=https://api.magic-music.org/api `
  --dart-define=SENTRY_DSN=<sentry_flutter_dsn> `
  --dart-define=SENTRY_ENVIRONMENT=production `
  --dart-define=SENTRY_RELEASE=magic-music-crm@1.1.7+117 `
  --dart-define=SENTRY_TRACES_SAMPLE_RATE=0
```

For staging diagnostics:

```powershell
flutter run --release `
  --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api `
  --dart-define=SENTRY_DSN=<sentry_flutter_dsn> `
  --dart-define=SENTRY_ENVIRONMENT=staging `
  --dart-define=SENTRY_RELEASE=magic-music-crm@local
```

## First Triage

1. Filter Sentry by `auth.flow`.
2. Check `api_base_url`, `api.path`, `api.error_type` and `api.status_code`.
3. If all auth flows fail and `api.error_type=connectionError`, verify DNS/TLS for `MAGIC_API_BASE_URL`.
4. If only Google fails, check backend Google OAuth config and callback handling.

## Codex Read Access

Codex can read Sentry issues/events through the local Sentry plugin helper after a read-only token is stored on this machine.

Create a Sentry auth token with minimal read scopes:

- `org:read`
- `project:read`
- `event:read`

Store it in the Windows user environment:

```powershell
setx SENTRY_AUTH_TOKEN "<read_only_sentry_token>"
setx SENTRY_ORG "<sentry_org_slug>"
setx SENTRY_PROJECT "<sentry_project_slug>"
```

Restart Codex after `setx` so the new environment variables are visible to future sessions.

Local smoke command:

```powershell
.\scripts\sentry_read.ps1 -Command list-issues -Environment production -TimeRange 24h -Limit 10
```

Useful Codex prompts after setup:

```text
@sentry покажи unresolved production ошибки за последние 24 часа
@sentry разбери issue MAGIC-MUSIC-CRM-FLUTTER-1 и найди связанный код
@sentry покажи события с auth.flow=password_login
```
