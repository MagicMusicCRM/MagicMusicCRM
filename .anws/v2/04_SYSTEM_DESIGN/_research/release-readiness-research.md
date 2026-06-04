# Research — Release Readiness and Security Baseline

**Date**: 2026-05-30  
**Systems**: SYS-APP, SYS-DATA, SYS-MSG, SYS-LEGAL, SYS-REL

## Sources

- Google Play User Data policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Google Play account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Apple account deletion guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Supabase Google OAuth docs: https://supabase.com/docs/guides/auth/social-login/auth-google
- Supabase RLS docs: https://supabase.com/docs/guides/database/postgres/row-level-security
- Local security scan: `C:\Users\potyl\AppData\Local\Temp\codex-security-scans\MagicMusicCRM\2a38b85_20260530_120237\report.md`

## Findings Used In Design

- Account creation implies account deletion must be available and discoverable.
- Privacy disclosures must match real data collection: profile PII, media, FCM tokens, Firebase SDKs and notifications.
- Supabase anon keys are public; RLS/function/storage policies are the security boundary.
- Google OAuth needs platform callback configuration and safe deep-link handling.
- The app needs release gates because current analyzer/build/security state is not publication-ready.

## Design Implications

- Legal consent is part of onboarding, not a settings-only link.
- Deletion requires privileged backend flow and public web URL.
- Storage must move from public URLs to signed/authorized access for chat media.
- Personal admin chat and announcements must be separate database concepts or explicitly separated by RLS-safe type fields.
- Security regression tests must include direct Supabase API behavior, not only UI behavior.
