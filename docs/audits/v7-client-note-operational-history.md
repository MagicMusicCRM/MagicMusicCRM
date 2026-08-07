# v7 T5.1.2 — Client Note and Operational History

**Date:** 2026-08-07  
**Scope:** `REQ-CLIENT-102`

## Result

Lead and Student now share one versioned internal note. Optimistic writes are
serialized per client lineage; a stale `expectedVersion` fails without losing
the newer text. Conversion attaches the created Student to the existing row
without changing its id, version, author or edit timestamp.

Admin, Manager, Director and system administrator see the note in Overview and
the bounded operational history in History. The history reuses the immutable
audit log and an explicit action allowlist for subscriptions, payments,
reversals, lesson decisions, recurring-plan endings and note changes. Every row
shows its exact recorded reason, actor and timestamp; pagination defaults to 30
and is capped at 100.

Teacher and Client are rejected before note/history data access. The Flutter
card also projects the same rule before provider creation, so these roles mount
neither the field nor hidden API requests. Purchase audit now preserves the
entered cross-payer reason for the same staff history.

No second note store, client timeline or audit mechanism was introduced.

## Contracts verified

- Concurrent note edits produce one winner and one stale-version conflict.
- Lead-to-Student conversion preserves the same note row and version.
- Admin actions expose reason, author and time to all permitted staff roles.
- Client is rejected by the backend; Teacher creates zero Flutter note/history
  requests.
- Both new routes are owned by the capability route policy and ClientRef scope.

## Verification

| Gate | Result |
|---|---|
| Backend note/conversion/route targeted | PASS — 68/68 |
| Flutter note/history targeted | PASS — 2/2 |
| Flutter analyze | PASS — no issues |
| Flutter full | PASS — 635/635 |
| Backend typecheck/build | PASS |
| Backend full | PASS — 155/155 suites, 1227/1227 tests |
| v7 reconciliation | PASS twice — `issues=[]` |
