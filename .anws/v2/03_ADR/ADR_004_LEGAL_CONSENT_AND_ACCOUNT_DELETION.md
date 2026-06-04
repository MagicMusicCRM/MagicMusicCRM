# ADR-004 — Legal Consent and Account Deletion

**Status**: Accepted  
**Date**: 2026-05-30  
**Influence scope**: SYS-LEGAL, SYS-APP, SYS-DATA, SYS-REL

## Context

Google Play requires privacy/data disclosures and account deletion paths for apps that allow account creation. Apple also requires account deletion to be available when account creation is offered. MagicMusicCRM currently has no in-app legal consent capture or account deletion workflow.

Official sources:

- Google Play User Data policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Google Play account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Apple account deletion guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

## Decision

Add legal documents, versioned consent and account deletion as product features:

- User must accept current Privacy Policy and Terms during onboarding.
- Consent records are immutable for clients.
- Settings exposes legal documents and accepted versions.
- Settings exposes `Удалить аккаунт`.
- A public web deletion URL must exist for Google Play metadata.
- Deletion is executed through a privileged backend flow; no service-role key is ever shipped to Flutter.

## Options Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| In-app legal gate + backend deletion request | Store-aligned, auditable | Requires schema/UI/backend work | Accepted |
| Static policy link only | Fast | No consent audit, no deletion flow | Rejected |
| Client directly deletes Auth user with admin secret | Immediate | Critical credential exposure | Rejected |

## Consequences

- Onboarding depends on legal consent.
- Account deletion state must block or limit app access.
- Retention exceptions must be reflected in Privacy Policy.
- Store forms must match actual Firebase/profile/media/notification behavior.

## Verification

- User cannot enter CRM without accepting current legal versions.
- Client can request only own deletion.
- Public deletion URL is available before Google Play submission.
