# Magic Music CRM

Flutter CRM for Magic Music school operations: schedules, clients, teachers, leads, finance, messenger, onboarding, legal consent and Google Play release workflows.

## Current Release

- App version: `1.1.5+115`
- Android package: `magic.crm`
- Primary branch: `main`
- Active backend: Supabase project `xblpnywnlhfgofskbdxb`
- App Supabase URL: `https://api.magic-music.org`

## GitHub And Linear

Repository:

```text
MagicMusicCRM/MagicMusicCRM
```

Current development branch for release fixes:

```text
codex/release-main-merge
```

For Linear documentation and issue tracking, add the GitHub account `aleks10sadu` as a collaborator or member with access to this repository, then connect the same repository in the Linear GitHub integration.

## Product Scope

The app is an internal operational CRM. It supports:

- client, teacher, manager and admin dashboards;
- schedule, lessons, rooms, branches and groups;
- leads, tasks, payments and reports;
- personal `Администрация` chat and read-only `Объявления`;
- file, image and voice attachments in messenger;
- profile editing, auth methods, legal consent and account deletion;
- Google OAuth, email/password login and optional email-code step after password.

## Architecture

```text
lib/
├── core/
│   ├── constants/       environment constants
│   ├── providers/       shared Riverpod providers
│   ├── router/          GoRouter auth/profile/legal gates
│   ├── services/        Supabase-backed services
│   ├── theme/           app colors and Material themes
│   └── widgets/         shared UI and messenger widgets
└── features/
    ├── admin/
    ├── auth/
    ├── client/
    ├── manager/
    ├── messenger/
    ├── profile/
    └── teacher/
```

Backend boundaries:

- Supabase Auth for email/password, OTP and Google identity.
- Postgres with RLS for CRM data and role isolation.
- Storage for avatars and chat attachments.
- Realtime for messenger and operational updates.
- Edge Functions for push notification dispatch.

Architecture docs live in `.anws/v2/`.

## Auth

Google OAuth is configured through Supabase Auth. The Supabase Google provider must keep the Web OAuth client first, followed by Android clients:

```text
WEB_CLIENT_ID,ANDROID_DEBUG_CLIENT_ID,ANDROID_UPLOAD_CLIENT_ID,ANDROID_PLAY_SIGNING_CLIENT_ID
```

Current Web Client ID used by Flutter builds:

```text
1038036512599-vg813c70pl4qjv7kmtse94mgkorfatg6.apps.googleusercontent.com
```

Android release builds must pass it explicitly:

```powershell
flutter build appbundle --release --dart-define=GOOGLE_WEB_CLIENT_ID=1038036512599-vg813c70pl4qjv7kmtse94mgkorfatg6.apps.googleusercontent.com
```

Email OTP is 6 numeric digits. Supabase Auth generates the token; Resend only delivers the email. Set `OTP length = 6` in Supabase Auth email provider settings.

## Storage URL Policy

Do not store absolute Supabase Storage URLs in database columns. Use stable references:

```text
storage://avatars/<path>
storage://chat-attachments/<path>
```

`ChatAttachmentService` resolves those references through the current Supabase host. This prevents old `*.supabase.co` links from leaking into UI after switching to `https://api.magic-music.org`.

Relevant migration:

```text
supabase/migrations/20260605123145_normalize_storage_urls_for_custom_domain.sql
```

## Custom Domain Notes

`https://api.magic-music.org` is a Supabase custom domain. It still points to Supabase infrastructure. If a mobile operator blocks the route to Supabase/Cloudflare IPs, the custom domain alone may not restore access.

Useful checks from a phone without VPN:

```text
https://api.magic-music.org/rest/v1/
https://xblpnywnlhfgofskbdxb.supabase.co/rest/v1/
```

Expected successful backend reachability is a Supabase JSON error such as `UNAUTHORIZED_MISSING_API_KEY`, not a rendered web page.

## Local Setup

Prerequisites:

- Flutter SDK
- Android Studio / Android SDK
- Supabase CLI
- release signing file `android/key.properties`
- upload keystore referenced by `android/key.properties`

Install dependencies:

```powershell
flutter pub get
```

Run locally:

```powershell
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=1038036512599-vg813c70pl4qjv7kmtse94mgkorfatg6.apps.googleusercontent.com
```

Build Android App Bundle:

```powershell
flutter build appbundle --release --dart-define=GOOGLE_WEB_CLIENT_ID=1038036512599-vg813c70pl4qjv7kmtse94mgkorfatg6.apps.googleusercontent.com
```

Output:

```text
build/app/outputs/bundle/release/app-release.aab
```

## Verification

Run before release:

```powershell
flutter test
flutter analyze --no-fatal-warnings --no-fatal-infos
```

Current analyzer baseline has legacy info-level findings in archived scripts and older messenger/admin/manager files. Error-level analyzer failures are release blockers.

## Supabase Operations

Check migration state:

```powershell
supabase migration list
```

Be careful with `supabase db push`: local and remote migration histories may differ. For narrow data fixes, use reviewed SQL with:

```powershell
supabase db query --linked --file <path-to-sql>
```

Do not expose service-role keys in Flutter. New Supabase-facing app services should use the `Supa` prefix and stay outside widget `build()` methods.

## Release Checklist

1. Update `pubspec.yaml` version and build number.
2. Confirm Google OAuth clients in Supabase Auth.
3. Confirm Firebase `google-services.json` contains Android clients for debug, upload and Play signing SHA-1.
4. Run `flutter test`.
5. Run `flutter analyze --no-fatal-warnings --no-fatal-infos`.
6. Build AAB with `GOOGLE_WEB_CLIENT_ID`.
7. Upload AAB to Google Play testing track.
8. Smoke-test Google login, onboarding/legal gate, messenger, attachments and profile avatars without VPN.

## Documentation Index

- `.anws/v2/05_TASKS.md` - release task blueprint.
- `docs/release/google_oauth_setup.md` - Google OAuth setup.
- `docs/release/resend_supabase_otp_setup.md` - Resend and Supabase OTP setup.
- `docs/release/supabase_email_templates_ru.md` - Russian email templates.
- `docs/supabase_custom_domain_setup_guide.md` - custom domain notes.
- `docs/release/google_play_console_status.md` - Play Console status.
- `docs/legal/` - legal documents.
