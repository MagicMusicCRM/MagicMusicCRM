# T2.2.2 — Actor-Aware Client Projection Evidence

**Date:** 2026-07-25

**Result:** PASS

## Delivered

- Six explicit client projection profiles:
  `client_self`, `teacher_assigned`, `admin_scoped`, `manager_scoped`,
  `director_scoped`, `system_admin_emergency`.
- Resource-scope enforcement before serialization:
  - Client: self only, unrelated resource returns safe 404;
  - Teacher: assigned only, unrelated resource returns safe 404;
  - Admin/Manager/Director: branch-scoped, foreign branch returns 403;
  - `system_admin`: emergency projection, followed by resource validation at
    the caller boundary.
- One Teacher allowlist used before composition on all required surfaces:
  client, search, schedule, chat and export.
- Teacher output physically excludes contacts, representatives, finance,
  subscriptions, payments, balance, debt, price/cost/rate and private comments.
- List/search projection filters unauthorized clients before serialization.
- Projection cache keys are partitioned by profile, actor user, access version,
  surface and resource scope.
- OpenAPI 3.1 contains separate schemas for all six role projections and
  declares the cache partition contract.

## Verification

```powershell
npm --prefix server test -- --runTestsByPath src/access-control/teacher-projection.contract.spec.ts
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
```

| Gate | Result |
|---|---:|
| Exact projection contract suite | 1/1 suite, 19/19 tests |
| Teacher forbidden keys across five surfaces | 0 |
| Teacher forbidden sentinel values across five surfaces | 0 |
| Unrelated Teacher/Client resource | safe 404 |
| Foreign staff branch | 403 |
| Six OpenAPI projection schemas | PASS |
| Cache partition isolation | PASS |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 107/107 suites, 991/991 tests |

## Contract artifacts

- `server/src/access-control/actor-client-projection.factory.ts`
- `server/src/access-control/teacher-projection.contract.spec.ts`
- `docs/contracts/v4-client-projections.openapi.json`
