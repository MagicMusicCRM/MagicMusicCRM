# Campaign 12 Tier 4 review

## Final status: ACCEPTED

- Tier 4 base: `624f36c560ed7fb2de5f92612c3a9b2445339d68`.
- Final reviewed code/test HEAD: `b84a201ff83b639a2831d11013ffd7250cedb629`.
- Initial totals: Critical **0**, Important **5**, Minor **0**.
- Final totals: Critical **0**, Important **0**, Minor **0**.
- RepoWise index SHA: `b84a201ff83b639a2831d11013ffd7250cedb629`.

## Accepted lanes and integration

| Lane | Source and hardening commits | Integration merge |
|---|---|---|
| J — Schedule plan | `cb36e126`, `981d6701` | `fde1509f` |
| K — Staff detail | `91348a62`, `73e97409` | `01b39ef` |
| L — Schedule reference | `bcc1cd0a`, `6cee14c8`, `b8a5816f`, `cb609c1c`, `65e21fbd`, `48f5b5bc` | `7c80bc07`, `fac99d86` |

All 25 verify-only paths are blob-identical to the Tier 4 base. The K and L
branches contain zero backend changes. Five private schedule-plan providers
are registered in `CrmModule`; all three production
`LessonCommandMetadata` imports use the neutral module and no production
owner imports the metadata type from `lesson-command.service`.

## Integrated verification

- Schedule-plan unit/AST suites: **10/10 PASS**.
- Selected PostgreSQL schedule-plan cases: **4/4 PASS**, five unrelated cases skipped.
- Backend TypeScript typecheck: **PASS**.
- Schedule-reference plus G/H/I architecture suites: **42/42 PASS**.
- Staff-detail suites: **21/21 PASS**.
- Existing named shared workspace tests: **4/4 PASS**.
- Targeted Flutter analyzer: **22 targets, no issues**.
- Exact formatting and `git diff --check`: **PASS**.

No campaign-wide backend or Flutter suite was run here; the single global
suite, fresh LCOV, recount, Sentrux gate, and full-range risk remain Task M.

## Findings and dispositions

| Finding | Disposition | Fix evidence |
|---|---|---|
| Important — Nest injected collaborators emitted invalid `Function`/`Object` metadata | Closed | `981d6701`; value imports plus a permanent `TestingModule.compile()` regression cover facade and five private owners. |
| Important — Staff Detail ownership guard allowed callable tear-offs | Closed | `73e97409`; analyzer-AST ownership guard catches callable and provider-read tear-offs. |
| Important — Staff Detail async requests could commit after disposal | Closed | `73e97409`; branch, provision, and save success/error paths are generation/disposal guarded. |
| Important — Schedule Reference controls could replace a draft during an in-flight save | Closed | `48f5b5bc`; mutators and controls fail closed while saving and preserve expected-version chaining. |
| Important — provider ownership could cross expression boundaries undetected | Closed | `48f5b5bc`; conditional, switch, cast, await, catch/finally, and alias flows are permanently guarded. |

Final independent re-review verdict: Critical/Important/Minor **0/0/0 NEW**;
ready for the single Task M global gate.

## RepoWise evidence

RepoWise is indexed exactly at the reviewed code/test HEAD. Every extracted
production file is at most `500` NLOC and max CCN is at most `10`; the three
former god owners are absent from the production god-file set.

The history-sensitive headline scores still include stale pre-Tier-4 LCOV and
new-file `untested_hotspot` deductions. Fresh coverage ingestion is therefore
retained as a Task M requirement. Representative exact indexed results are:

| Owner | Health | NLOC | CCN | Maintainability |
|---|---:|---:|---:|---:|
| `schedule-plan.service.ts` | 6.23 | 74 | 1 | 8.1 |
| `schedule-plan-definition.service.ts` | 6.84 | 500 | 8 | 7.4 |
| `schedule-plan-mutation.service.ts` | 6.69 | 375 | 4 | 7.1 |
| `schedule-plan-end.service.ts` | 6.11 | 324 | 6 | 7.8 |
| `staff_detail_dialog.dart` | 4.59 | 139 | 8 | 9.3 |
| `staff_detail_controller.dart` | 8.14 | 176 | 6 | 10.0 |
| `schedule_reference_settings.dart` | 4.59 | 57 | 3 | 9.3 |
| `schedule_reference_controller.dart` | 4.29 | 368 | 10 | 9.3 |

Backend hotspot scores are 97% for the compatibility facade and 74–76% for
the freshly extracted definition/mutation/end owners. These are mitigated by
the permanent structural guards, focused runtime tests, exact verify-only
boundary, and independent review; Task M owns fresh LCOV and full-range risk.
