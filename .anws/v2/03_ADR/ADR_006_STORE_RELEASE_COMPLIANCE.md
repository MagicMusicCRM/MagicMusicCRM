# ADR-006 — Store Release Compliance Gates

**Status**: Accepted  
**Date**: 2026-05-30  
**Influence scope**: SYS-REL, SYS-APP, SYS-LEGAL, SYS-NOTIFY

## Context

The current Android release config uses debug signing and the app requests sensitive permissions. iOS lacks several privacy usage declarations and Google OAuth URL-scheme readiness. Store submission also requires privacy/data disclosures to match actual data collection and SDK behavior.

## Decision

Create hard release gates for Google Play and App Store:

- Android release cannot use debug signing.
- Android permissions are minimized and documented.
- iOS Info.plist has required usage descriptions for microphone/media/files/camera/photos as applicable.
- Google OAuth callback configuration is present for Android/iOS.
- Data Safety/App Privacy checklist is generated from actual features and dependencies.
- Privacy Policy and deletion URL are available before submission.

## Options Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Gate release configs now | Prevents rejection and unsafe release | Requires config cleanup before feature work | Accepted |
| Fix after feature implementation | Less interruption | Risk of late store blockers | Rejected |

## Consequences

- Build scripts must fail if release signing env is missing.
- Sensitive permissions require explicit product justification or removal.
- Firebase Analytics/Messaging, PII, media and notifications must be reflected in store forms.

## Verification

- Android AAB build uses production signing.
- iOS metadata includes OAuth and privacy usage entries.
- Store checklist is completed and linked from release docs.
