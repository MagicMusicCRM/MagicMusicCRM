# ADR-005 — Capability-projected role and scope UX

- **Status:** Proposed
- **Date:** 2026-08-04

## Context

Different roles need different density and workflows. Hard-coded role menus drift from backend access and can trigger forbidden preloads. School-wide versus branch-specific behavior is also contextual, not a global toggle.

## Decision

Build navigation and visible actions from the current capability/resource-scope projection, then apply role-oriented information architecture. Each scope-aware route declares whether it supports `branch`, `school` or both; the selector offers only valid choices and defaults from route/resource context.

## Consequences

- Client: low-density self-service surfaces.
- Teacher: day/week schedule and assigned context, without forbidden finance/contact mutations.
- Admin: Chat, Schedule and Clients.
- Manager: operational workspace, excluding school-wide finance.
- Director: operational, financial, configuration and access surfaces according to capabilities.
- UI projection reduces confusion but server enforcement remains mandatory.

