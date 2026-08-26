Campaign baseline: 9cb1f506a5c5418650926fe53b81fe2667ba9bd7

# Tier 1 Lane B — Payroll semantic owners

## Implemented boundary

- `PayrollService` is a behavior-free four-owner facade with the original nine public methods and exported type path.
- Payroll calculation, read SQL, payroll query, integrity mutations, report projection, and CSV export now have cohesive owners.
- Rate/payout corrections preserve expected versions, idempotency/request metadata, capability checks, audit envelopes, outbox payloads, and response shapes.
- Rate/payout deletion remains append-only soft voiding; no physical history delete or direct database transaction was introduced.
- The permanent TypeScript AST guard enforces the constructor, nine direct delegations, mutation owner, soft-delete invariant, and every NLOC ceiling.

## TDD evidence

- RED: `npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts --runInBand` exited 1 before extraction because the six owners/four-argument facade did not exist and the soft-void command boundary was empty.
- GREEN: the same command exited 0 with 2 suites and 24 tests passed.

## Lane smoke

- `npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts --runInBand` — PASS, 2 suites / 24 tests.
- `npm --prefix server run typecheck` — PASS, `tsc --noEmit` exit 0.
- `git diff --check` — PASS, exit 0 (Git emitted only the existing LF-to-CRLF working-copy notices).
- `repowise update --index-only` — PASS under `Global\MagicMusicCRM_Campaign12_RepoWise`; output: `Already up to date.`

## Targeted RepoWise CLI health

Executed under the same named mutex with `repowise health --file <path> --format json`; the mutex covered the complete update and health block and was released in `finally`.

| Production file | Health | Max CCN | NLOC | god_class / brain_method |
|---|---:|---:|---:|---|
| `server/src/crm/payroll.service.ts` | 7.09 | 1 | 115 | none |
| `server/src/crm/payroll/payroll-accrual-calculator.ts` | 9.40 | 6 | 113 | none |
| `server/src/crm/payroll/payroll-read.repository.ts` | 9.30 | 3 | 243 | none |
| `server/src/crm/payroll/teacher-payroll-query.service.ts` | 9.30 | 4 | 87 | none |
| `server/src/crm/payroll/teacher-payroll-command.service.ts` | 7.80 | 6 | 449 | none |
| `server/src/crm/payroll/teacher-stats-report.service.ts` | 9.10 | 4 | 364 | none |
| `server/src/crm/payroll/teacher-stats-csv.service.ts` | 9.50 | 3 | 112 | none |

All new production owners and the compatibility facade satisfy health `>= 7.0`, max CCN `<= 10`, and the required NLOC ceilings.
