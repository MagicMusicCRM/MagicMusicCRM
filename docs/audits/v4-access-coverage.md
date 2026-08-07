# MagicMusicCRM v4 — Access Coverage & Shadow Parity

**Task:** T2.3.1
**Result:** PASS

## Coverage

| Metric | Value |
|---|---:|
| inventory routes | 292 |
| JWT private routes | 280 |
| capability + resource-scope mapped | 280 |
| public/external routes | 12 |
| unmapped private routes | 0 |
| missing resource scopes | 0 |
| unexplained capability allows | 0 |

Runtime enforcement is an intersection: the dynamic capability decision
runs in `JwtAuthGuard`, then the existing domain service/repository policy
must also allow the target resource. Capability rollout therefore cannot
expand legacy access.

## Capability distribution

| Capability | Private routes |
|---|---:|
| `access.user.override.manage` | 1 |
| `access.user.role.assign` | 5 |
| `commerce.client_finance.read` | 2 |
| `commerce.client_finance.write` | 7 |
| `commerce.package.manage` | 4 |
| `commerce.package.read` | 1 |
| `commerce.school_finance.read` | 10 |
| `commerce.subscription.issue` | 2 |
| `config.crm.edit` | 12 |
| `config.crm.publish` | 2 |
| `config.crm.read` | 3 |
| `crm.client.read.basic` | 111 |
| `crm.client.read.contacts` | 2 |
| `crm.client.write` | 40 |
| `crm.comment.read.shared` | 2 |
| `report.export.xlsx` | 6 |
| `report.status.read` | 17 |
| `schedule.lesson.read.assigned` | 21 |
| `schedule.lesson.write` | 19 |
| `system.settings.manage` | 6 |
| `workflow.task.read` | 4 |
| `workflow.task.write` | 3 |

## Shadow comparison

Every route carries its legacy policy name and expected role envelope.
Differences are classified as legacy-stricter or capability-stricter;
the compatibility intersection preserves the stricter decision. Resource
scope remains enforced in the existing SQL/service layer.

Machine-readable route-by-route evidence:
`docs/audits/v4-access-coverage.json`.

## Verification

```powershell
npm --prefix server run v4:access-coverage -- --require-complete
npm --prefix server test -- --runTestsByPath src/access-control/capability-route-policy.spec.ts src/access-control/capability-request-authorizer.spec.ts src/common/security/jwt-auth.guard.spec.ts src/crm/crm.service.spec.ts
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
pwsh -File scripts/v4_inventory.ps1 -Check
```

| Gate | Result |
|---|---:|
| Exact access coverage | 280/280 private routes |
| Registry/resource-scope mapping | 100% / 100% |
| Unmapped / unexplained allow | 0 / 0 |
| Targeted capability/JWT/repository tests | 4/4 suites, 56/56 tests |
| Backend typecheck/build | PASS / PASS |
| Full backend regression | 110/110 suites, 1026/1026 tests |
| Current-state inventory | 292 routes, 683 DTO fields, 0 unowned |
