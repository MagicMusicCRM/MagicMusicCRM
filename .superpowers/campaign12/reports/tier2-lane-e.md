# Campaign-12 Tier 2 — Lane E Auth

- Base: `2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`
- Commit: `6a1c4dbd774fe9b0af0d0b77c7539f6c4f6aedc4`
- Commit message: `refactor(auth): split authentication workflows`
- Scope: `server/src/auth` only; controller, DTO, PasswordService, and SessionService production sources are unchanged.

## Structure

`AuthService` is now an 88-NLOC compatibility facade with five typed `private readonly` workflow owners and twelve explicit-return-type direct delegations. `AuthModule` registers seven new private providers and still exports exactly `AuthService`, `PasswordService`, and `SessionService`.

The extracted production owners are registration, login, verification, password recovery, account, rate limiting, and email challenge delivery. Shared records/contracts moved to `auth.types.ts`; pure hashing and normalization moved to `auth-normalization.ts`. No `DatabaseService.transaction` boundary was introduced.

## Security evidence

- Unknown OTP and password-reset identities both return `{ accepted: true }` without email or audit disclosure.
- Required OTP delivery failure consumes the inserted challenge and issues no session.
- Client `setPassword` supplies `managed_password_ciphertext = null`; managed set/reset flows call `encryptForManagedAccess`.
- Password reset, password change, and email change revoke sessions before their success audit.
- Duplicate email maps PostgreSQL `23505` to the exact Russian conflict message without revoking sessions.
- A valid email verification token audits once; replay returns `Код подтверждения недействителен или истек.`
- Controller routes and DTO/public shapes are unchanged.

## Verification

- RED: `auth.service.spec.ts` passed 38 tests while `auth-boundaries.spec.ts` failed at the first missing owner file, as intended (17.495 s).
- Focused GREEN: 42/42 tests passed (17.713 s).
- Final lane smoke: 6 suites, 52/52 tests passed (22.053 s).
- `npm run typecheck -- --pretty false`: PASS.
- `git diff --check`: PASS.
- Verify-only production diff: empty.
- Lane worktree status after commit: clean.

## Raw RepoWise health

| File | Score | CCN | NLOC |
| --- | ---: | ---: | ---: |
| `auth-account.service.ts` | 8.90 | 6 | 147 |
| `auth-verification.service.ts` | 8.93 | 4 | 186 |
| `auth-rate-limit.service.ts` | 9.15 | 2 | 137 |
| `auth-registration.service.ts` | 9.28 | 5 | 114 |
| `auth-login.service.ts` | 9.30 | 4 | 169 |
| `auth-email-challenge.service.ts` | 9.35 | 5 | 106 |
| `auth-password-recovery.service.ts` | 9.65 | 3 | 132 |
| `auth.service.ts` facade | 5.55 | 1 | 88 |

All seven new owners exceed the `>=7` health gate and the login split stays below CCN 10. The facade's remaining score drag is historical change entropy and five prior-defect commits, not current complexity. Module health returned `line_coverage_pct=null`; no coverage adjustment was applied. Fresh LCOV remains a final global-gate responsibility.

Post-commit `repowise update --index-only` queued SHA `6a1c4dbd` behind the already-running shared updater PID 47528; final exact index status is recorded by the tier integrator.
