# V6-505/506 and INT-S5 — Unified CRM configuration

**Date:** 2026-08-04
**Status:** PASS

## Production workspace

- `/crm/configuration` is the canonical production route opened from the existing client configuration entry point.
- The workspace uses the v7 tokens and responsive patterns already present in the application: three panes on desktop and a compact single-column flow on mobile.
- It owns categories, Lead/Student fields, placement and width, reusable option sets, allowlisted business numbers, Student funnel entry and immutable revision history.
- Supported field types are `text`, `textarea`, `number`, `money`, `duration`, `boolean`, `toggle`, `date`, `datetime`, `select`, `radio`, `multi_select`, `checkbox_group`, `email`, `phone` and `url`.
- Client creation consumes the effective field order, category, placement, width, required marker, type and configured options. System-backed selects remain dynamic and cannot be replaced by unsafe static values.

## Scope, lifecycle and integrity

- School configuration is the default. Branch configuration stores only changed allowlisted business settings; categories, fields and option sets remain inherited.
- Draft, validation/impact preview, publish and rollback share one normalized snapshot contract.
- Publish is serialized by scope, checks the expected version, syncs normalized client field definitions in the same transaction and rejects invalid impact atomically.
- Rollback creates a new revision; the database rejects update/delete of historical revisions.
- Type changes are blocked when existing typed values would become unsafe. Protected system fields cannot be removed or converted.
- Migration `0097_unified_crm_configuration` passed down/up and seeds the current production field definitions losslessly.

## Delegated access

- `config.crm.read`, `config.crm.edit` and `config.crm.publish` are registered typed capabilities and are part of the OpenAPI registry snapshot.
- Director/system administrator receive the package defaults. Director can delegate allowed lower capability overrides through the existing reasoned access editor and resource assignment flow.
- A delegated Manager can read/edit only an assigned branch and cannot access school scope. Admin, Teacher and Client are hard-denied; Manager cannot self-escalate or assign Director/system administrator.
- Publication writes actor, before/after version, reason and impact to audit, then emits the existing setting/access invalidation path for active sessions.
- The Flutter route waits for the capability projection before construction; a forbidden actor issues no configuration requests.

## Verification

- `flutter analyze` — PASS, 0 issues.
- Full Flutter suite — **601/601** PASS.
- Configuration/client-form widget regression — **9/9** PASS, including Director publish, delegated Manager branch-only and Admin zero-request denial.
- Configuration/access/backend regression — **6/6 suites, 89/89 tests** PASS.
- Full backend run reached **151/152 suites and 1172/1173 tests** before the only failure exposed the obsolete 20-capability preflight constant; after updating it to 23 capabilities/138 package entries and requiring migration 0097, the exact failing suite passed **1/1**.
- Backend typecheck/build — PASS.
- Migration `0097` down/up — PASS.
- `pwsh -NoProfile -File scripts/v6_ux_inventory.ps1 -Check` — PASS: routes=22, reachable=260, workspaceProduction=2, unowned=0.
- `git diff --check` — PASS.
