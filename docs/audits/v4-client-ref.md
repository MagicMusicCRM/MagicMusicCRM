# MagicMusicCRM v4 — ClientRef Resolver & Scoped Search

**Task:** T3.1.1
**Result:** PASS
**Date:** 2026-07-25

## Contract

`ClientRefDto` requires an explicit `{type: lead|student, id: UUID}` pair.
The resolver never guesses an entity type from a UUID. Both schedule's
existing `clientRef` input and the new client endpoints use this shared DTO:

- `GET /api/crm/clients/resolve?type=student&id=<uuid>`;
- `GET /api/crm/clients/search?q=<name>&type=lead|student&limit=25`;
- `includeArchived=true` explicitly includes tombstones in search.

Each projection contains only `ref`, `label`, `lifecycleState`, `tombstone`
and `archivedAt`. Phone, e-mail, contacts, finance, payments, balance and
subscriptions are absent by construction.

## Resource scope

Scope is applied inside PostgreSQL before projection:

- Admin/Manager/Director/system_admin can resolve and search all clients;
- Client sees only the owned Student or an explicit active CRM link;
- Teacher sees clients attached to assigned lessons, groups or tasks;
- inaccessible and missing UUIDs both return the same safe `404`;
- an accessible archived record resolves as a stable tombstone.

The two ClientRef private routes map to `crm.client.read.basic` with `resource`
scope. Current access coverage is 244/244 private routes, with zero unmapped
routes, missing scopes or unexplained allows.

## Verification

```powershell
npm --prefix server test -- --runTestsByPath src/crm/clients/client-ref.integration.spec.ts
npm --prefix server run test:actor-matrix:v4
npm --prefix server run typecheck
npm --prefix server run build
npm --prefix server test
pwsh -File scripts/v4_inventory.ps1 -Check
```

| Gate | Result |
|---|---:|
| Exact PostgreSQL ClientRef suite | 1/1 suite, 6/6 tests |
| Controller contract tests | 1/1 suite, 2/2 tests |
| Actor Matrix + leak scan | 2/2 suites, 8/8 tests |
| Route decisions | 1464/1464 |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 116/116 suites, 1051/1051 tests |
| Current-state inventory | 256 routes, 561 DTO fields, 0 unowned |
