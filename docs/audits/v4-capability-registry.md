# T2.1.1 — Capability Registry & Role Packages Evidence

**Date:** 2026-07-25

**Result:** PASS

## Delivered

- Additive migration `0076_capability_registry`.
- Versioned `capability_definitions` with one-active-version constraint.
- Six versioned role packages with one-active-package-per-role constraint.
- Complete explicit matrix: `20 capabilities × 6 roles = 120 allow/deny facts`.
- Override mode (`allow_deny`, `deny_only`, `locked`) and risk metadata.
- Future-ready `user_capability_overrides` and monotonic
  `user_access_versions`.
- Typed NestJS registry/repository and OpenAPI 3.1 contract snapshot.
- Unknown/inactive capability and missing package entry fail closed to `deny`.

Seed mapping is equivalent-or-stricter than current access:

- Teacher: contacts, client finance and all schedule mutations denied.
- Manager: role/override management, school finance and package management
  denied; operational system settings allowed.
- Director: role/override management, school finance and package management
  allowed.
- `system_admin`: all registered domain capabilities allowed; hard invariants
  remain a code-policy responsibility of T2.1.2.

## Verification

```powershell
npm --prefix server test -- --runTestsByPath src/access-control/capability-registry-postgres.integration.spec.ts
```

| Gate | Result |
|---|---:|
| Exact PostgreSQL suite | 1/1 suite, 6/6 tests |
| Migration `down → up` | PASS |
| Registry ↔ DB ↔ OpenAPI parity | PASS |
| Complete six-role package matrix | PASS |
| Unknown capability fail-closed | PASS |
| One-active version/package constraints | PASS (`23505`) |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 104/104 suites, 935/935 tests |

## Contract artifacts

- `server/src/access-control/capability-registry.ts`
- `server/src/access-control/capability-registry.repository.ts`
- `docs/contracts/v4-capability-registry.openapi.json`
