# ADR-003 — Unified navigation, history and breadcrumbs

- **Status:** Proposed
- **Date:** 2026-08-04

## Context

Desktop users need parallel contexts and jumps to ancestors; mobile users need reliable Back. Tabs, history and hierarchy solve different problems. The current mixture of local navigation and typed entity routes cannot guarantee restoration.

## Decision

Use one canonical location descriptor shared by GoRouter, `WorkspaceController` and breadcrumb metadata.

- Workspace tabs represent parallel desktop contexts and persist per account.
- Back/Forward navigate history inside the active tab.
- Breadcrumbs navigate the route hierarchy and never synthesize history from labels.
- Mobile uses one route stack; overlays are dismissed before routes.
- UI Back and Android system/predictive Back use the same pop/dirty-state policy.
- Typed entity links use `EntityRouteRegistry`; direct deep links reconstruct location and breadcrumbs without prior history.

## Consequences

- A route owns its stable identity, parameters, parent metadata and restorable view state.
- Logout clears the account workspace cache; restoration validates route version and current access.
- The implementation must bridge existing mechanisms, not create a second navigation registry.

