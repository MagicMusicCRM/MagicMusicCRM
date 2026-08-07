# ADR-002 — Adaptive surface policy

- **Status:** Proposed
- **Date:** 2026-08-04

## Context

Fixed-width dialogs are cramped on phones, cannot be expanded, conflict with the keyboard and produce inconsistent Back behavior. Converting every interaction to a page would make simple choices unnecessarily heavy.

## Decision

Choose the container from the job:

- Primary or multi-step work: route/page; full-screen on compact, workspace page on desktop.
- Quick view or short contextual edit: draggable sheet on compact, side sheet/large modal only when desktop context should remain visible.
- Selection: sheet/drawer with search.
- Short irreversible confirmation: dialog.

Mobile sheets use full safe width, visible handle, explicit expand action, snap states, `maxChildSize = 1.0` and the supplied scroll controller. Dirty-state handling is identical regardless of container.

## Consequences

- Client card, payment, lesson edit, configuration and reports are navigable routes on phones.
- Existing modal content should be reused inside adaptive containers; do not duplicate forms.
- Every migrated surface requires keyboard-inset, safe-area, landscape and Back tests.

