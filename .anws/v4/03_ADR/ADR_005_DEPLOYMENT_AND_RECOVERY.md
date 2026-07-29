# ADR-005 - Deployment and Recovery

**Status**: Accepted
**Date**: 2026-06-10
**Influence scope**: SYS-OPS, SYS-API, SYS-DATA, SYS-FILES

## Context

The first v3 production topology is one Moscow primary server. This is not HA, so stability depends on predictable deployment, monitoring and restore.

## Decision

Use Docker Compose for first production deployment with explicit image tags, health checks, reverse proxy TLS, PostgreSQL, Redis, API, worker and monitoring/log agent. Backups are encrypted and stored outside the primary server. Restore drill is required before DNS cutover.

## Consequences

- RPO target: 24 hours for first launch.
- RTO target: 4 hours after tested restore.
- No production launch without rollback and restore runbooks.

## Verification

- Health endpoint works.
- Backup restore drill passes.
- Deployment rollback command and smoke checks are documented.
