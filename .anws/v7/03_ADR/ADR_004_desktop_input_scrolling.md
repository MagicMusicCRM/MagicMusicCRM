# ADR-004 — Desktop input and scrolling

- **Status:** Proposed
- **Date:** 2026-08-04

## Context

Many screens can currently be scrolled only with touchpad gestures. A global wrapper around every scrollable would be small but unsafe: nested views and multi-attached controllers can break pointer behavior.

## Decision

Style scrollbars globally but attach visible draggable bars only at explicit scroll-surface owners. Each axis owns one controller. On desktop, overflowing vertical and horizontal work areas show a visible track/thumb, support mouse drag and consistent wheel/Shift+wheel behavior. Mobile keeps non-persistent touch scrolling.

## Consequences

- Maintain a production inventory of scroll-surface owners.
- Boards, calendars, tables and tab strips require explicit horizontal behavior.
- No blanket nested `Scrollbar` wrapper and no shared controller across multiple scroll views.
- Keyboard focus, hover, tooltip and semantic labels are part of the same desktop acceptance gate.

