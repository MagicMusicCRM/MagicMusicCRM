# MagicMusicCRM v4 — Compatibility & Shadow Parity

**Task:** T8.3.3  
**Result:** PASS

## Gate

| Corpus | Decisions | Differences | Unexplained |
|---|---:|---:|---:|
| Access routes × 6 roles | 1,650 | 1 | 0 |
| Seeded half-open schedule intervals | 2,000 | 0 | 0 |
| **Total** | **3,650** | **1** | **0** |

The one access difference is the already classified `legacy-stricter` route.
The compatibility intersection therefore keeps the deny and cannot widen
access. Safe diff payloads contain route/corpus IDs, roles and booleans only.

Access and schedule remain in `shadow` by default. `v4` enable is rejected
while any unexplained difference exists; domain kill switches force the
effective path to the compatibility fallback. Operational variables and the
rollback sequence are documented in
`docs/runbooks/v4-compatibility-flags.md`.
Runtime readiness publishes both resolved domain states and reports
`v4Rollout=blocked` for an unsafe enable request.

## Verification

- Shadow compare: 3,650 decisions, explained 1, unexplained 0.
- Feature flag/kill-switch, compare and readiness tests: 3 suites, 9/9 tests.
- Backend typecheck: PASS.
- Machine report: `docs/audits/v4-shadow-compare.json`.
- Package regression: backend 148/148 suites and 1,147/1,147 tests;
  Flutter analyze clean and 481/481 tests; inventory 287 routes, 658 DTO
  fields, 5 schema tables, unowned 0.

The release security audit is operational again after installing system
Node.js/npm. It reports an inherited `exceljs → uuid` issue at moderate
severity; no dependency was changed in that release candidate. This is explicit
input to T8.4.1, not an unexplained parity or migration failure.

```powershell
npm --prefix server run v4:shadow-compare -- --require-zero-unexplained
npm --prefix server test -- --runTestsByPath src/platform/v4-domain-flags.spec.ts src/platform/v4-shadow-compare.spec.ts
npm --prefix server run typecheck
```
