# ADR-006 - Security Gates

**Status**: Accepted
**Date**: 2026-06-10
**Influence scope**: SYS-SEC, all systems

## Context

v3 creates a new backend security boundary. The project must avoid repeating client-side trust, public secrets and overbroad data access.

## Decision

Launch is blocked by security gates covering:

- Secrets and frontend exposure.
- Auth/session lifecycle.
- Authorization and IDOR.
- Data isolation.
- Input validation and API security.
- File upload safety.
- Dependency/container vulnerabilities.
- Monitoring, audit logs, backups and restore.
- External integration fallback and webhook signatures.

## Consequences

- Security checks are implementation tasks, not post-launch cleanup.
- Critical/High findings block cutover.
- Actor matrix tests are required for every user-facing data domain.

## Verification

- CI scans pass.
- Actor matrix passes.
- 50-point checklist is completed and attached to release evidence.
