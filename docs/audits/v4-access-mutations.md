# T2.2.1 — Atomic Access Mutation API Evidence

**Date:** 2026-07-25

**Result:** PASS

## Delivered

- Authenticated v4 access API for:
  - listing/getting active role packages;
  - replacing a role package with an expected version;
  - assigning a user role with explicit override-reset confirmation;
  - setting a versioned personal capability override;
  - reading a user access snapshot.
- `AccessMutationsService` and `AccessMutationsRepository` backed by the
  T8.1.4 idempotency/version/audit/outbox transaction boundary.
- Migration `0077_access_mutation_versions`:
  - seeds `access:user` and `access:role-package` aggregate versions;
  - initializes both access-version records for every newly created user.
- Hard mutation boundaries:
  - Manager/Admin are denied;
  - Director mutates only users/packages strictly below Director and cannot
    mutate itself;
  - `system_admin` mutations require the explicit emergency surface;
  - locked/deny-only/hard-denied overrides are rejected;
  - role changes reset active overrides only after explicit confirmation.
- Complete package replacement: the next version always contains one explicit
  effect for every active capability.
- Before/after/reason audit and minimal access invalidation outbox event in the
  same PostgreSQL transaction as the business mutation.
- Idempotent replay for an identical actor/key/fingerprint and 409 for stale
  versions or key reuse.
- OpenAPI 3.1 snapshot:
  `docs/contracts/v4-access-mutations.openapi.json`.

## Verification

```powershell
npm --prefix server test -- --runTestsByPath src/access-control/access-mutations-postgres.integration.spec.ts
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
npm --prefix server run db:rollback
npm --prefix server run db:migrate
```

| Gate | Result |
|---|---:|
| Exact PostgreSQL suite | 1/1 suite, 6/6 tests |
| Manager 403 + zero partial facts | PASS |
| Director lower-role/package boundary | PASS |
| `system_admin` emergency-only mutation | PASS |
| Role + override reset + version + audit + outbox atomicity | PASS |
| Package completeness / stale conflict / hard-deny rollback | PASS |
| Idempotent replay | PASS |
| Migration `down → up` | PASS |
| App module graph | PASS |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 106/106 suites, 972/972 tests |

## Contract artifacts

- `server/src/access-control/access-mutations.controller.ts`
- `server/src/access-control/access-mutations.service.ts`
- `server/src/access-control/access-mutations.repository.ts`
- `server/src/access-control/dto/access-mutation.dto.ts`
- `server/db/migrations/0077_access_mutation_versions.up.sql`
- `docs/contracts/v4-access-mutations.openapi.json`
