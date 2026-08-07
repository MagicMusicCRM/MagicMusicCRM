# v7 T5.1.3 — Canonical Client Card Composition

**Date:** 2026-08-07  
**Scope:** `REQ-CLIENT-101`

## Result

The production Client Card remains one routed desktop canvas inside the shared
CRM shell. A keyboard-accessible section-jump row reaches every card section in
one action and updates the existing typed route state without reloading the
client. Compact layouts keep the horizontal section navigation; Tasks or
History require at most the main section choice plus one inner choice.

Subscriptions and Progress are now first-class sections for both Lead and
Student. Lead subscription issue was removed from the bottom action bar and is
owned only by Subscriptions; its existing conversion transaction is unchanged.
Homework assignment is owned only by Progress and now uses the correct Lead or
Student reference. Archive remains the separate protected action.

On expanded layouts Subscriptions and Progress share a compact row, followed by
the full-width Payments section and then Tasks/Comments/History. Payment
movements and installment obligations remain collapsed by default. The general
`Actions` menu and duplicate commands are absent.

No backend, API contract, dependency or parallel card implementation changed.

## Contracts verified

- One visible command owner for subscription issue and homework assignment.
- Desktop section jump changes the canonical `section` route state without a
  second client fetch.
- Compact Lead reaches issue/homework through their named sections.
- Payment movements and installments start collapsed.
- Desktop 840/1200 and compact 360 layouts keep canonical sections, Back and
  route state without overflow.

## Verification

| Gate | Result |
|---|---|
| Card/action/navigation targeted | PASS — 24/24 |
| Action ownership inventory | PASS — 2/2 |
| Flutter analyze | PASS — no issues |
| Flutter full | PASS — 637/637 |
| Backend diff | PASS — empty |
| v6 UX inventory | PASS — routes=22, reachable=260, wire=274/274, unowned=0 |
| v7 commerce/schedule inventory | PASS — finance=251, lessonWrites=7, unowned=0 |
