# ADR-002 — Auth-First Onboarding and Server-Owned Roles

**Status**: Accepted  
**Date**: 2026-05-30  
**Influence scope**: SYS-AUTH, SYS-DATA, SYS-APP, SYS-LEGAL

## Context

New users must register through Google Account and then provide ФИО and phone. The current system also lets authorization depend on `profiles.role`, while security findings show that role assignment is reachable from user-controlled metadata and own-profile updates.

## Decision

Adopt auth-first onboarding:

1. User authenticates with Google OAuth through Supabase Auth.
2. Backend creates a profile with default role `client`.
3. Router sends incomplete profiles to onboarding.
4. User enters ФИО and phone and accepts legal documents.
5. Only a completed profile with required consent can enter CRM surfaces.

Roles are server-owned. Clients can never set or update staff role values through signup metadata, profile update or direct REST calls. Staff role changes require staff-only policy/function and audit data.

## Options Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Keep profile role column but guard it fully | Minimal schema churn | Must be tested carefully; existing code depends on `profiles.role` | Accepted as first implementation path |
| Move roles to dedicated `user_roles` table | Stronger separation | More app query refactor | Preferred target if migration cost is acceptable |
| Trust app UI to hide role input | No migration | Fails direct Supabase client threat model | Rejected |

## Consequences

- `create_profile_for_new_user()` must ignore `raw_user_meta_data.role`.
- `profiles` UPDATE policy must block role and sensitive fields for ordinary users.
- Router may read role, but role source must be backend-guarded.
- Onboarding state becomes a first-class routing condition.

## Verification

- Signup with `role=admin` metadata still creates `client`.
- Authenticated client cannot update own role.
- Incomplete profile cannot access `/client`, `/admin`, `/manager` or `/teacher`.
