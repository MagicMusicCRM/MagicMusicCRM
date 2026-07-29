# MagicMusicCRM v4 — Lead to Student Conversion

**Task:** T3.2.2
**Result:** PASS
**Date:** 2026-07-25

## Domain result

Migration `0081_client_conversion_links` introduces a durable one-to-one
`Lead → Student` conversion fact and backfills it from existing
`students.lead_id` history. Both the new conversion command and the retained
subscription-issue conversion write this link.

`POST /api/crm/clients/leads/:leadId/convert`:

- validates the strict Student minimum and active branch;
- serializes by Lead advisory lock;
- returns the existing Student on concurrent replay;
- creates account/profile/Student/link atomically;
- preserves compatible legacy and typed custom values;
- rebinds user links, chats, lessons, homework, tasks, comments and family
  membership to the Student.

`POST /api/crm/clients/leads/:leadId/archive-source` is restricted by domain
policy to Director/system_admin and only soft-archives a Lead with a conversion
link. The linked Student and all transferred facts remain intact.

## Verification

```powershell
npm --prefix server run db:rollback
npm --prefix server run db:migrate
npm --prefix server test -- --runTestsByPath src/crm/clients/conversion-postgres.integration.spec.ts
npm --prefix server run test:actor-matrix:v4
npm --prefix server run typecheck
npm --prefix server run build
npm --prefix server test
pwsh -File scripts/v4_inventory.ps1 -Check
```

| Gate | Result |
|---|---:|
| Migration `0081` down → up | PASS |
| Exact PostgreSQL conversion suite | 1/1 suite, 1/1 test |
| Concurrent conversion | 1 Student, 1 ConversionLink |
| Relation/custom-value preservation | PASS |
| Source cleanup | Manager 403; Director Lead-only archive |
| Actor Matrix + payload leak scan | 2/2 suites, 8/8 tests |
| Route decisions | 1476/1476 |
| Access coverage | 246/246 private routes |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 118/118 suites, 1051/1051 tests |
| Current-state inventory | 258 routes, 559 DTO fields, 0 unowned |
