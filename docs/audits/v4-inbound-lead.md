# MagicMusicCRM v4 — Signed Inbound Lead Ingestion

**Task:** T3.2.1
**Result:** PASS
**Date:** 2026-07-25

## Contract

`POST /api/public/lead-webhook` is the only path that emits
`inbound.lead.created`.

Required headers:

- `X-Ingestion-Id`: UUID used as the idempotency key;
- `X-Webhook-Timestamp`: Unix timestamp in seconds, accepted within 300 seconds;
- `X-Webhook-Signature`: `sha256=<hex HMAC-SHA256>`.

The signed material is
`timestamp.ingestionId.sha256(canonical-json-payload)`. The shared
`LEAD_WEBHOOK_SECRET` is fail-closed when empty and must be at least 32
characters when configured through application environment validation.

The payload uses the strict v4 Lead minimum: `firstName`, `lastName`, `phone`
and active `sourceId`; optional email, discipline, comment and typed custom
fields remain inside the signed payload.

## Atomicity and replay

`PlatformIntegrityService` reserves the ingestion id, inserts the Lead with
`leads.inbound_id`, appends the audit fact, and enqueues exactly one
`inbound.lead.created` platform outbox event in one PostgreSQL transaction.
Migration `0080_inbound_lead_ingestion` adds a unique partial index on
`inbound_id` as a database-level second guard.

An identical replay returns the stored `leadId` and does not run domain
validation or mutation again. The integration suite verifies this remains
true even if the source is archived after the original request.

Manual CRM creation and chat/app auto-creation no longer call
`NotificationsService.notifyNewLead`; therefore only a signed inbound
ingestion creates the notification outbox fact.

## Verification

```powershell
npm --prefix server run db:rollback
npm --prefix server run db:migrate
npm --prefix server test -- --runTestsByPath src/crm/clients/inbound-lead-postgres.integration.spec.ts
npm --prefix server test -- --runTestsByPath src/crm/lead-webhook.controller.spec.ts src/crm/lead-intake.service.spec.ts src/crm/leads.service.spec.ts
npm --prefix server run test:actor-matrix:v4
npm --prefix server run typecheck
npm --prefix server run build
npm --prefix server test
pwsh -File scripts/v4_inventory.ps1 -Check
```

| Gate | Result |
|---|---:|
| Migration `0080` down → up | PASS |
| Exact PostgreSQL ingestion suite | 1/1 suite, 1/1 test |
| Targeted signature/manual/chat suites | 3/3 suites, 48/48 tests |
| Duplicate inbound result | 1 Lead, 1 outbox event |
| Manual notification delta | 0 |
| Actor Matrix + payload leak scan | 2/2 suites, 8/8 tests |
| Route decisions | 1464/1464 |
| Access coverage | 244/244 private routes |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 117/117 suites, 1050/1050 tests |
| Current-state inventory | 256 routes, 558 DTO fields, 0 unowned |
