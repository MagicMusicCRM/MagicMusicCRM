# v7 T5.1.4 — Director Commerce Catalog UI

**Date:** 2026-08-07  
**Scope:** `REQ-LESSON-101`, `REQ-LESSON-102`

## Result

Unified CRM Configuration now owns both independent commerce catalogs already
present in the versioned `ConfigSnapshot`: lesson settlement types and teacher
compensation types. No second provider, service, model or backend contract was
introduced.

Director/system_admin can create and edit stable keys, archive entries, change
order and publish a school or branch revision through the existing
draft → impact preview → publish/rollback flow. Settlement preview always pairs
its color with an icon and text label. Teacher compensation stays independent:
the employee still selects it manually for every lesson decision.

Money and percentages are converted exactly between UI major units and backend
minor units/basis points without floating-point arithmetic. Published forms
continue to read the effective catalog from the existing lesson decision API;
historical facts retain their prior snapshot.

Manager has no catalog area or controls. Admin, Teacher and Client fail closed
before creating a configuration request. Local edits use the shared
Save / Discard / Cancel Back contract.

## Verification

| Gate | Result |
|---|---|
| Configuration role/dirty/back/publish/rollback | PASS — 10/10 |
| Lesson decision consumers + dirty contract | PASS — 23/23 |
| Backend configuration PostgreSQL contract | PASS — 7/7 |
| Flutter analyze | PASS — no issues |
| Flutter full | PASS — 642/642 |
| Backend diff | PASS — empty |
| v6 UX inventory | PASS — routes=22, reachable=260, wire=274/274, unowned=0 |
| v7 commerce/schedule inventory | PASS — finance=251, lessonWrites=7, unowned=0 |
