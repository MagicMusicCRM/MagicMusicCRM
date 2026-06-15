# ADR-001 - Backend Stack

**Status**: Accepted
**Date**: 2026-06-10
**Influence scope**: SYS-API, SYS-DATA, SYS-MSG, SYS-OPS, SYS-APP

## Context

v3 must remove Supabase Cloud runtime dependency while preserving CRM, auth, messenger, files and legal flows. The existing Flutter app has many direct Supabase calls, so v3 needs a stable backend contract and disciplined migration boundary.

## Decision

Use **NestJS + TypeScript** for the backend API, PostgreSQL for data, Redis for rate limits/cache/worker coordination, WebSocket gateway for realtime and Docker Compose for first production deployment.

## Options Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| NestJS + TypeScript | Modular guards, DTO validation, WebSocket/workers, strong API shape | New server codebase | Accepted |
| FastAPI + Python | Fast API iteration | More mismatch with frontend/TS tooling | Rejected |
| Dart backend | Shared language with Flutter | Less mature backend ecosystem for this scope | Rejected |
| Self-hosted Supabase | Lowest app refactor | Does not meet independence goal | Rejected as final v3 |

## Consequences

- Backend modules must own authorization.
- Flutter must stop depending on Supabase SDK for production flows.
- API contracts become first-class release artifacts.

## Verification

- Backend compiles, tests pass, OpenAPI/DTO contract generated.
- Flutter integration uses `MagicApiClient`, not Supabase runtime calls.
