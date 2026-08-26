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
- Raw integrated command: `repowise health --format json > .superpowers/campaign12/reports/tier1-health-raw.json`; exit 0; 134.437 seconds. The preserved stdout artifact is 2,824,420 bytes with SHA256 `2bcc58b1d9e88e9f1e2324d3dd231abbacb45d4fb691c8a0789a27e16638463a`.
- Coverage provenance command: `repowise coverage status --format json > .superpowers/campaign12/reports/tier1-coverage-status.json`; exit 0. The preserved JSON is 673 bytes with SHA256 `08340a87ed13c89767ecda7e31e7340a0f36d28c055642c5d05c379ef3c47cf1`.
- Deterministic extraction command: `pwsh -NoProfile -File .superpowers/campaign12/reports/validate-tier1-health.ps1 -Mode Write`; result: `PASS wrote 19 exact target rows; adjusted 4; raw sha256=2bcc58b1d9e88e9f1e2324d3dd231abbacb45d4fb691c8a0789a27e16638463a`.
- Deterministic verification command: `pwsh -NoProfile -File .superpowers/campaign12/reports/validate-tier1-health.ps1 -Mode Verify`; result: `PASS verified 19 exact target rows; adjusted 4; raw sha256=2bcc58b1d9e88e9f1e2324d3dd231abbacb45d4fb691c8a0789a27e16638463a`.
- Validator guard command: `pwsh -NoProfile -File .superpowers/campaign12/reports/validate-tier1-health.tests.ps1`; PASS for missing target, duplicate target, wrong impact, wrong coverage SHA, valid write, and byte-equivalent verify.
- The validator contains all 19 literal paths, rejects any missing/duplicate metric row, preserves each raw score and raw finding, and permits adjustment only for the four named owners when the same row has exactly one `untested_hotspot` impact `1.56` and coverage SHA equals `e86b1f555da5892d66e9d850f1bccb203af57949`.
- Compact exact-target JSON: `.superpowers/campaign12/reports/tier1-health.json` (29,508 bytes at validation; SHA256 `820af82b9bad573cf5f8c89237d0a530ca91a4fee0e5b845da63ec75739b0e71`).
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

## Controller review checks

Each command `git diff --quiet 9cb1f506a5c5418650926fe53b81fe2667ba9bd7..HEAD -- <path>` exited 0. Baseline and HEAD blob hashes are identical:

| Verify-only controller | Baseline = HEAD blob | Forwarding / metadata / header contract |
|---|---|---|
| `server/src/messenger/messenger.controller.ts` | `0118a931d970760f8a51314f4b0f9d37e4a6917e` | `@UseGuards(JwtAuthGuard)` and `@Controller("messenger")` remain. Ten facade-facing routes forward `actor` first, then unchanged UUID-piped IDs, query, and DTO in the original order to `listChats`, `getChat`, `getMessages`, `listChatMembers`, `sendMessage`, `createDirectChat`, `createGroup`, `updateGroupMembers`, `leaveGroup`, and `setChatMute`; this surface has no command-metadata headers. |
| `server/src/crm/crm-people.controller.ts` | `baa548ec7f9c1b97c168a0dd80b195eaac43ec24` | `@UseGuards(JwtAuthGuard)` and `@Controller("crm")` remain. Payroll reads/reports forward `actor` plus ID/query unchanged. Six payout/rate mutations forward `actor, id, [entryId], dto, metadata`; metadata preserves `idempotency-key` and `x-request-id` with `?? ""`. CSV export still awaits `exportTeacherStatsReport(actor, query)` and sets `Content-Type: text/csv; charset=utf-8` plus `Content-Disposition: attachment; filename="teacher-stats.csv"`. |
| `server/src/crm/subscription-commerce.controller.ts` | `384daf6567342fcbe9e4c12bee589e62bfb5612b` | `@UseGuards(JwtAuthGuard)` and `@Controller("crm/students")` remain. Preview forwards `actor, studentId, dto`; issue and purchase forward `actor, studentId, dto, metadata`. Metadata preserves `idempotency-key` and `x-request-id` with `?? ""`, and every `studentId` remains `ParseUUIDPipe`. |

No forwarding, metadata, header, route, DTO, guard, or controller mismatch was found. Controllers remain verify-only; no controller test or source edit was added.

## Review fix round 1 — guard integration

Evidence/provenance fix commit: `838d85e0018dfe1da2e2e099dbf83babaab2558e` (`docs(health): make Tier 1 evidence reproducible`). Its preserved raw artifact remains SHA256 `2bcc58b1d9e88e9f1e2324d3dd231abbacb45d4fb691c8a0789a27e16638463a`.

| Owner guard | Source commit | Applied commit | Scope | Post-pick diff check |
|---|---|---|---|---:|
| Payroll mutation AST guard | `a7ec45b891f3d7f7729aa842538faf3ea0c458df` | `82738c2fbbb732c56d7e237096a369ebf69e9fa8` | only `server/src/crm/payroll/payroll-service-boundary.spec.ts` | 0 |
| Subscription mutation AST guard | `61e0654def4f92d5eef9d54809df1bc66517ade5` | `245a1c92c744f20069ca51d7760ce963a9dd3151` | only `server/src/crm/commerce/subscription-issue-boundary.spec.ts` | 0 |

The Subscription cherry-pick had one same-file content conflict because the integration checkpoint had already inserted the private-wiring assertion at the start of the same `describe`. Resolution preserved that assertion and added the owner guard's AST mutation-counter assertion unchanged; no production or controller file was involved.

- Combined smoke: `npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand` — exit 0, 4/4 suites, 37/37 tests, 0 snapshots, Jest 19.995 seconds, wall 22.616 seconds.
- Typecheck: `npm --prefix server run typecheck` — exit 0, `tsc --noEmit`, wall 9.453 seconds.
- Range check: `git diff --check 3fda5c105bb0dde51dac1168ec0e6150b6273200..HEAD` — exit 0.
- Messenger controller resolution: baseline..HEAD diff exit 0 and blob remains `0118a931d970760f8a51314f4b0f9d37e4a6917e`; actor-first facade forwarding, UUID pipes, guard, routes, query/DTO order, and no command-metadata headers are unchanged.
- Payroll controller resolution: baseline..HEAD diff exit 0 and blob remains `baa548ec7f9c1b97c168a0dd80b195eaac43ec24`; actor/ID/entry/DTO order, `idempotency-key`, `x-request-id`, empty-string normalization, and CSV content headers are unchanged.
- Subscription controller resolution: baseline..HEAD diff exit 0 and blob remains `384daf6567342fcbe9e4c12bee589e62bfb5612b`; preview forwarding, issue/purchase metadata, header normalization, UUID pipe, routes, and DTO order are unchanged.

No controller mismatch was found. `.superpowers/campaign12/reports/tier1-review.md` remains intentionally absent pending the controller-dispatched fresh review.
