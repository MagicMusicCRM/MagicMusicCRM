Campaign baseline: 9cb1f506a5c5418650926fe53b81fe2667ba9bd7

# Campaign 12 Tier 1 review

## Final status: ACCEPTED

- Initial reviewer: `/root/campaign12_tier1_reviewer`.
- Initial reviewed range: `9cb1f506a5c5418650926fe53b81fe2667ba9bd7..3fda5c105bb0dde51dac1168ec0e6150b6273200`.
- Initial totals — Critical: **0**; Important: **2**; Minor: **1**; controller checks: **3 ⚠**.
- Scoped fix reviewer: `/root/campaign12_tier1_rereviewer`.
- Final reviewed/fixed code and evidence HEAD before this report: `1e1772fa61eaac360aa28b55b03a68f7d9960bcd`.
- Final accepted totals — Critical: **0**; Important: **0**. One test-hardening Minor is explicitly deferred below.

## Initial findings

### Important 1

> The targeted-health evidence is not reproducible. T1 requires the exact command for all nineteen targets, but the committed evidence records only bare repowise health --format json, with neither target paths nor the filtering/extraction command that produced nineteen rows. Record the complete invocation or deterministic extraction command and preserve its raw result.

### Important 2

> The permanent mutation-count guards are bypassable. Subscription counts only generic calls containing <, so an additional untyped mutation remains invisible; payroll counts only calls immediately followed by (, so an additional typed mutation remains invisible. Count TypeScript CallExpression nodes by callee identity regardless of type arguments.

### Minor

> Messenger and subscription facade guards do not assert constructor dependency types or private readonly modifiers. Current facades comply, but the permanent boundary permits dependency drift; add the same AST assertions already used by payroll.

### Controller ⚠ checks

1. `Messenger controller check: add a focused spy test proving JwtAuthGuard, UUID parsing, and exact actor/query/DTO forwarding for the ten facade-backed routes.`
2. `Payroll controller check: verify argument order, empty-string metadata fallback, expected-version DTO forwarding, and CSV headers for all nine facade routes.`
3. `Subscription controller check: verify guard, actor/student scope, DTO forwarding, and idempotency/request metadata for issue, preview, and purchase.`

The controller checks were resolved read-only because all three controllers are verify-only in T1. No controller test or controller source was added or changed.

## Fix round 1

Reviewer: `/root/campaign12_tier1_rereviewer`.

| Commit | Evidence / disposition |
|---|---|
| `838d85e0018dfe1da2e2e099dbf83babaab2558e` | Preserved raw health and coverage-status JSON, added the deterministic 19-path validator/extractor, exact SHA/size/command provenance, rejection tests, raw scores, and the final coverage blocker. Important 1: **ADDRESSED**. |
| `82738c2fbbb732c56d7e237096a369ebf69e9fa8` | Replaced the Payroll regex with a TypeScript `CallExpression` guard and added typed/untyped/text-decoy meta-coverage. |
| `245a1c92c744f20069ca51d7760ce963a9dd3151` | Replaced the Subscription regex with a TypeScript `CallExpression` guard and added typed/untyped/optional/text-decoy meta-coverage. |
| `6fb9ad0f556737cd1cd5ae674c70df13e95a251c` | Recorded focused smoke, typecheck, diff, raw-health provenance, and controller resolutions. |

Round-1 verdict: health provenance and all three controller checks **ADDRESSED**. The mutation-guard finding was **partially open only for a missing Payroll optional-chain meta-test**; the guard implementation already parsed the syntax. New breakage totals — Critical: **0**; Important: **0**; Minor: **0**.

## Fix round 2

Reviewer: `/root/campaign12_tier1_rereviewer`.

| Commit | Evidence / disposition |
|---|---|
| `f24e34ae09840f89424879765d0008287a922ea5` | Added the Payroll optional-chain `executeVersionedMutation` meta-case and raised the expected AST count from 2 to 3. |
| `1e1772fa61eaac360aa28b55b03a68f7d9960bcd` | Recorded exact Payroll smoke, typecheck, scope, and range-diff evidence. |

Round-2 finding verdict: **ADDRESSED**. The scoped reviewer confirmed the Payroll guard counts untyped, typed, and optional-chain calls while ignoring string/comment decoys. New breakage totals — Critical: **0**; Important: **0**; Minor: **0**. Verdict: **all Important findings addressed**.

## Controller resolution evidence

For each path, `git diff --quiet 9cb1f506a5c5418650926fe53b81fe2667ba9bd7..1e1772fa61eaac360aa28b55b03a68f7d9960bcd -- <path>` exited 0, and the baseline and reviewed-HEAD blobs are identical.

| Controller | Baseline = reviewed HEAD blob | Read-only forwarding inspection |
|---|---|---|
| `server/src/messenger/messenger.controller.ts` | `0118a931d970760f8a51314f4b0f9d37e4a6917e` | `JwtAuthGuard`, UUID pipes, routes, actor-first ordering, and exact query/DTO forwarding remain intact for all ten facade-backed routes; no command-metadata header exists on this surface. |
| `server/src/crm/crm-people.controller.ts` | `baa548ec7f9c1b97c168a0dd80b195eaac43ec24` | All nine Payroll facade routes preserve argument order and DTO forwarding. Mutations preserve `idempotency-key` / `x-request-id` with `?? ""`; CSV export preserves `text/csv; charset=utf-8` and `attachment; filename="teacher-stats.csv"`. Expected-version DTOs are forwarded unchanged. |
| `server/src/crm/subscription-commerce.controller.ts` | `384daf6567342fcbe9e4c12bee589e62bfb5612b` | `JwtAuthGuard`, actor/student scope, UUID parsing, DTO order, preview forwarding, and issue/purchase idempotency/request metadata remain intact. |

All three ⚠ checks are **RESOLVED** by identical blobs plus exact source inspection under the verify-only scope. No runtime or controller-test gap was accepted as a Critical or Important finding.

## Health acceptance and final-gate blocker

Raw integrated health remains visible and is not replaced by adjusted evidence:

| Owner | Raw health | Stale-only LCOV impact | Coverage-adjusted health |
|---|---:|---:|---:|
| `messenger-chat-query.service.ts` | 5.51 | 1.56 | 7.07 |
| `teacher-payroll-command.service.ts` | 6.24 | 1.56 | 7.80 |
| `subscription-purchase-preview.service.ts` | 6.41 | 1.56 | 7.97 |
| `subscription-purchase-command.service.ts` | 6.24 | 1.56 | 7.80 |

The adjustment is provisional because the ingested LCOV commit `e86b1f555da5892d66e9d850f1bccb203af57949` predates Campaign baseline. The final global gate must ingest fresh LCOV containing every new owner, remove the stale `untested_hotspot` penalty through real coverage evidence, and prove raw health `>= 7.0` for every new owner. Adjusted scores cannot satisfy final acceptance.

## Minor deferred ruling

The Messenger/Subscription facade guard constructor type and `private readonly` assertions are deferred to the final whole-campaign review because the current constructors comply and the issue is test hardening only. Cost if wrong: one test-only guard fix before merge. No runtime dependency drift is accepted.

Tier 1 is accepted for progression with Critical/Important `0/0`, the explicit Minor ruling above, and the fresh-LCOV final blocker retained.
