# T2.1.2 — Hard-Invariant Evaluator Evidence

**Date:** 2026-07-25

**Result:** PASS

## Delivered

- `EffectiveAccessEvaluator` with the accepted evaluation order:
  active actor → known/active registry contract → `system_admin` root or hard
  invariant → role package → permitted personal override → resource scope.
- Fail-closed handling for unknown/inactive capabilities, registry metadata
  drift, missing package effects and invalid stored overrides.
- Immutable Teacher denies for client contacts/write, client finance,
  subscription issue and every schedule mutation.
- Director-only business boundaries for role/override management, school
  finance and package management.
- Role mutation policy:
  - Admin and Manager are denied;
  - Director manages only other users strictly below Director;
  - `system_admin` uses the explicit emergency surface and may manage any role.
- Protection against demotion or deactivation of the last active
  `system_admin`.
- Override mutation validation for `allow_deny`, `deny_only`, `locked` and
  hard-denied capabilities.
- NestJS provider exports for the evaluator and invariant policy.

## Verification

```powershell
npm --prefix server test -- --runTestsByPath src/access-control/effective-access-evaluator.spec.ts
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
```

| Gate | Result |
|---|---:|
| Exact evaluator suite | 1/1 suite, 30/30 tests |
| Six-role table matrix | PASS |
| Teacher hard deny > incompatible personal allow | PASS |
| `system_admin` root allow + resource validation | PASS |
| Last active `system_admin` protection | PASS |
| Director hierarchy / Admin+Manager deny | PASS |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 105/105 suites, 965/965 tests |

## Contract artifacts

- `server/src/access-control/effective-access-evaluator.ts`
- `server/src/access-control/hard-invariant.policy.ts`
- `server/src/access-control/effective-access-evaluator.spec.ts`
