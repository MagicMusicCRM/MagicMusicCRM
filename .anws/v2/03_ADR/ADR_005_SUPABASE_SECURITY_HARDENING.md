# ADR-005 — Supabase Security Hardening as Release Blocker

**Status**: Accepted  
**Date**: 2026-05-30  
**Influence scope**: SYS-DATA, SYS-MEDIA, SYS-MSG, SYS-NOTIFY

## Context

The security scan found critical/high issues in Supabase role handling, RPCs, security-definer views, storage policies, profile visibility and notification dispatch. Because Supabase anon keys are public by design, security must be enforced by RLS and server-side checks.

## Decision

Treat Supabase hardening as the first release blocker:

- Revoke public execute from privileged RPCs unless explicitly safe.
- Bind user-sensitive functions to `auth.uid()`.
- Set immutable server-owned role assignment.
- Replace broad profile reads with self/staff/minimal-public projections.
- Convert security-definer views to `security_invoker` or guarded RPCs.
- Make private media private and signed.
- Move FCM tokens out of broadly readable `profiles`.
- Restrict notification Edge Function to staff and rotate bundled Firebase key.

## Options Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Harden Supabase in place | Directly fixes root risks | Requires careful migration/testing | Accepted |
| Hide risky UI paths only | Fast | Direct API access remains vulnerable | Rejected |
| Build custom backend before release | Strong control | Too slow for current publication task | Deferred |

## Consequences

- Some existing UI queries will break until they use safe views/services.
- RLS tests become mandatory.
- Direct Supabase calls in widgets remain technical debt but are less dangerous after backend hardening.

## Verification

- Supabase advisors have no unresolved ERROR-level security items relevant to exposed app data.
- Client/anon test matrix proves denial for role escalation, cross-user profiles, private media and privileged RPCs.
