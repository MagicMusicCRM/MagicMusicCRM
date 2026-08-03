# ADR-001 — Preserve v7 and existing runtime

- **Status:** Proposed
- **Date:** 2026-08-04

## Context

MagicMusicCRM already has an approved v7 visual direction, v7 tokens/components, GoRouter, an entity route registry and a desktop workspace implementation. The product gap is production integration and consistency, not absence of frameworks.

## Decision

Implement v6 as a reskin/reflow of the existing Flutter application. Preserve v7 gold/charcoal visual identity and existing API/service contracts. Mount and finish the existing workspace/navigation facilities. Add a shared primitive only after at least two production surfaces need the same behavior and no existing primitive covers it.

## Consequences

- No second router, tab engine, design system or state-management stack.
- UI work can be reviewed as focused screen migrations with network-call parity.
- Some old widgets must be split into reusable content plus route/sheet containers, but domain services stay unchanged.
- Missing prototype artifacts do not authorize inventing a new palette; current v7 tokens and approved specs remain authoritative.

