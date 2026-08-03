# ADR-006 — UX quality and release evidence

- **Status:** Proposed
- **Date:** 2026-08-04

## Context

Previous isolated fixes and tests were reported as complete although production routes, real-account behavior and device workflows were not demonstrated.

## Decision

A surfaced feature is complete only with production mounting, role/scope coverage, state coverage, direct-link and Back behavior, platform input checks, unchanged service-call evidence where applicable, and real-account UAT. Security and rollback gates remain release blockers.

## Consequences

- Every task names an autonomous check and evidence artifact.
- Screenshot-only evidence is insufficient without route/API/result reconciliation.
- Missing seeded backend, account or device is `blocked`, never `passed`.
- Production remains `NOT APPROVED` while a Critical/High finding or rollback failure is open.

