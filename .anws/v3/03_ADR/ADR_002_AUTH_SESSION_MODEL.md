# ADR-002 - Own Auth and Session Model

**Status**: Accepted
**Date**: 2026-06-10
**Influence scope**: SYS-AUTH, SYS-API, SYS-APP, SYS-SEC

## Context

Supabase Auth currently owns sessions, OAuth, OTP and account identity. v3 requires independent login while preserving Google as optional convenience.

## Decision

Implement backend-owned auth:

- Primary: email/password with email verification and OTP support.
- Session: short-lived access tokens and rotating refresh tokens.
- Reset: one-time hashed password reset tokens with expiry and audit events.
- Google OAuth: optional identity provider, not required for access.
- Roles: server-owned and never accepted from client payloads.

## Consequences

- Existing users need migration path to set password or verify email after cutover.
- Refresh token reuse detection becomes a security requirement.
- Mobile token storage must use secure platform storage.

## Verification

- Token lifecycle unit tests.
- Password reset abuse tests.
- Actor matrix verifies roles cannot be forged.
