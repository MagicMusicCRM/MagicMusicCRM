# ADR-001 — Tech Stack and Release Quality Gates

**Status**: Accepted  
**Date**: 2026-05-30  
**Influence scope**: SYS-APP, SYS-DATA, SYS-REL, all v2 tasks

## Context

MagicMusicCRM already ships as a Flutter app using Riverpod, GoRouter, Supabase, Firebase Messaging and platform build projects for Android/iOS/desktop. The user goal is publication readiness, not a platform rewrite. The security scan shows the root risk is misplaced trust in client-visible Supabase controls rather than a missing framework.

## Decision

Keep Flutter + Riverpod + Supabase as the v2 technology stack. Add blocking release quality gates:

- `flutter analyze` must have no error-level issues.
- `flutter test` must include auth/onboarding/legal/chat/security regressions.
- Supabase RLS/function/storage tests must cover anon/client/staff paths.
- Android/iOS release configuration must pass signing, permissions and privacy disclosure checks.
- No unresolved critical/high security findings may remain without a documented owner-approved exception.

## Options Considered

| Option | Fit | Security | Delivery Speed | TCO | Decision |
|---|---:|---:|---:|---:|---|
| Keep Flutter + Supabase and harden boundaries | 5 | 4 | 5 | 4 | Accepted |
| Move backend logic to a custom API immediately | 4 | 5 | 2 | 2 | Rejected for release timeline |
| Rewrite mobile app before publication | 2 | 3 | 1 | 1 | Rejected |

## Consequences

Positive:

- Fastest path to store readiness.
- Keeps existing team/product knowledge useful.
- Security work targets the actual root controls.

Negative:

- Supabase RLS and Edge Function discipline becomes mandatory.
- Direct Supabase calls in UI must be refactored gradually.
- Test harness must include database policy verification, not only Flutter tests.

## Verification

Release cannot proceed until SYS-REL gates pass and the security report has no unresolved P0/P1 blockers.
