Campaign baseline: 9cb1f506a5c5418650926fe53b81fe2667ba9bd7

# Campaign 12 Tier 1 integration

## Result: PASS — COVERAGE DEFERRED

Lane A, B, and C applied cleanly in the required order and the integrated Nest graph passes every focused Jest invocation, typecheck, and diff check. Centralized private wiring is present and guarded. Four raw integrated health rows are below `7.0` solely because the currently ingested LCOV predates Campaign 12 and assigns each new path the same stale-only `untested_hotspot` penalty of `1.56`. The coverage-adjusted scores exactly match live lane/module health and provisionally pass Tier 1. No lane-owned production owner was rewritten.

Integrated lane range: `9cb1f506a5c5418650926fe53b81fe2667ba9bd7..43fc7c7072b400105f1372b3793a14571d104c74`.

| Lane | Source commit | Applied commit | Post-pick diff check |
|---|---|---|---:|
| A Messenger | `14665146118f41d5d6160322edf7b3b6858ee046` | `37e2ee72` | 0 |
| B Payroll | `957fcbf976e8a22b1434d8b03c761c9873bebc8e` | `0e59445d` | 0 |
| C SubscriptionIssue | `792a76da2bb8e0bbfa12053407ccd98f63f0b865` | `43fc7c70` | 0 |

## Private wiring assertions

- `MessengerModule`: all five owners occur exactly once in `providers`, before `MessengerService`; none is exported; exports remain exactly `MessengerService`, `MessengerPolicyModule`, `RealtimeGateway`.
- `CrmModule` Payroll: all six owners occur exactly once immediately before `PayrollService`; the facade remains once; owners and facade remain private.
- `CrmModule` SubscriptionIssue: all five owners occur exactly once immediately before `SubscriptionIssueRepository`; repository and facade remain once; all seven remain private.
- Controllers are unchanged. Existing providers and both module export arrays are preserved.

## Focused smoke evidence

| Phase | Exact command | Exit | Suites/tests | Wall duration |
|---|---|---:|---:|---:|
| T1.2 | `npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts src/messenger/messenger-service-boundary.spec.ts src/messenger/messenger-policy.module.spec.ts --runInBand` | 0 | 3 / 54 | 8.868 s |
| T1.3 | `npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand` | 0 | 4 / 35 | 8.438 s |
| T1.4 Messenger | `npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts src/messenger/messenger-service-boundary.spec.ts --runInBand` | 0 | 2 / 53 | 5.429 s |
| T1.4 Payroll | `npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts --runInBand` | 0 | 2 / 25 | 4.952 s |
| T1.4 SubscriptionIssue | `npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand` | 0 | 2 / 10 | 4.970 s |
| T1.4 App/Policy | `npm --prefix server test -- --runTestsByPath src/app.module.spec.ts src/messenger/messenger-policy.module.spec.ts --runInBand` | 0 | 2 / 12 | 10.664 s |
| T1.4 typecheck | `npm --prefix server run typecheck` | 0 | `tsc --noEmit` | 4.588 s |
| T1.4 diff | `git diff --check` | 0 | no whitespace errors | 0.046 s |

## RepoWise evidence

- One `repowise update --index-only` processed `14665146..43fc7c70`, 25 changed files (7 modified, 18 added). Follow-up `repowise status` resolved last sync exactly to `43fc7c7072b400105f1372b3793a14571d104c74`. Observed command duration was approximately 162 seconds; the detached tool stream did not retain its millisecond footer.
- One already-started `repowise health --module server/src/messenger --format json` completed before the efficiency ruling.
- Authoritative integrated query: `repowise health --format json`; exit 0; 119.359 seconds; exactly 19 requested target rows, with duplicate/missing rows rejected.
- Full exact-target JSON: `.superpowers/campaign12/reports/tier1-health.json`.
- All 19 rows have max CCN `<= 10`; none has `god_class` or `brain_method`.
- `repowise coverage status --format json` confirms the active LCOV was ingested from `e86b1f555da5892d66e9d850f1bccb203af57949`, older than Campaign baseline `9cb1f506a5c5418650926fe53b81fe2667ba9bd7`; it cannot contain any Campaign-12 owner path. The test map is older again at `dca72f598cc2c80af03152366cec37d05a3e5472`.
- Repository coverage is deferred because the approved Campaign-12 process permits it only at the single final global gate.

| Coverage-deferred owner | Raw health | Stale-only penalty | Coverage-adjusted score | NLOC | Max CCN | Exact biomarker impacts |
|---|---:|---:|---:|---:|---:|---|
| `messenger-chat-query.service.ts` | 5.51 | 1.56 | 7.07 | 425 | 10 | untested 1.56; listChats large 1.008; conditional 0.931; cohesion 0.35; complex method 0.341; getMessages large 0.151; DRY 0.15 |
| `teacher-payroll-command.service.ts` | 6.24 | 1.56 | 7.80 | 449 | 6 | untested 1.56; DRY 0.35; cohesion 0.35; five large methods 1.07; five primitive-parameter findings 0.43 |
| `subscription-purchase-preview.service.ts` | 6.41 | 1.56 | 7.97 | 196 | 6 | untested 1.56; conditional 0.931; cohesion 0.6; DRY 0.35; primitive parameters 0.15 |
| `subscription-purchase-command.service.ts` | 6.24 | 1.56 | 7.80 | 250 | 5 | untested 1.56; purchase large 1.364; DRY 0.35; cohesion 0.35; constructor parameters 0.136 |

Provisional Tier 1 acceptance is `PASS — COVERAGE DEFERRED`. The final global gate must ingest fresh LCOV that includes every new owner, remove the stale `untested_hotspot` penalty through real coverage evidence, and produce raw health `>= 7.0` for every new owner; adjusted scores are not acceptable at that gate. Tier review has not yet been performed and `.superpowers/campaign12/reports/tier1-review.md` was not created.
