# T2.2.3 — Teacher Comment Sharing Evidence

**Date:** 2026-07-25

**Result:** PASS

## Delivered

- Additive migration `0078_comment_teacher_sharing` adds:
  - independent `shared_with_teacher` state;
  - positive per-comment `version`;
  - aggregate-version backfill and trigger for new comments;
  - a partial index for teacher-visible reads.
- Existing `teacher_note` rows are backfilled as shared. New teacher notes keep
  the compatibility `kind` stream and the explicit share flag in sync.
- Teacher comment reads require both:
  - an assigned student relation resolved by the existing CRM policy;
  - `shared_with_teacher = true` in the SQL projection predicate.
- The versioned toggle is available to Admin, Manager, Director and
  `system_admin`; Teacher and Client receive 403 before any write.
- The mutation uses the platform idempotency/version/audit/outbox transaction:
  stale versions roll back, identical replays do not duplicate evidence, and
  each committed toggle writes exactly one audit row.
- The outbox and best-effort realtime hint contain only structural invalidation
  data. The comment body is never included.
- The existing `visibleToTeacher` request field remains a compatibility alias;
  v4 callers can use `sharedWithTeacher`, `expectedVersion`, `reasonCode`,
  `Idempotency-Key` and `x-request-id`.

## Verification

```powershell
npm --prefix server test -- --runTestsByPath src/crm/clients/comment-sharing-postgres.integration.spec.ts
npm --prefix server test -- --runTestsByPath src/crm/timeline.service.spec.ts
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
npm --prefix server run db:rollback
npm --prefix server run db:migrate
pwsh -File scripts/v4_inventory.ps1 -Check
```

| Gate | Result |
|---|---:|
| Exact PostgreSQL suite | 1/1 suite, 8/8 tests |
| Assigned Teacher hidden/shared projection | PASS |
| Unrelated Teacher | safe 404 |
| Admin/Manager/Director/`system_admin` toggle | PASS |
| Teacher/Client mutation | 403, zero partial writes |
| One audit + one outbox row per committed toggle | PASS |
| Idempotent replay | no duplicate audit/outbox/realtime |
| Stale version rollback | PASS |
| Comment body in outbox/realtime evidence | 0 |
| Migration `down → up` | PASS |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 108/108 suites, 999/999 tests |
| Inventory | 246 routes, 523 DTO fields, 0 unowned |

## Contract artifacts

- `server/db/migrations/0078_comment_teacher_sharing.up.sql`
- `server/src/crm/clients/comment-sharing.service.ts`
- `server/src/crm/clients/comment-sharing-postgres.integration.spec.ts`
- `server/src/crm/dto/set-comment-visibility.dto.ts`
- `server/src/crm/timeline.service.ts`
