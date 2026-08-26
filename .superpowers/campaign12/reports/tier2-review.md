# Campaign 12 Tier 2 review

## Final status: ACCEPTED

- Tier 2 base: `2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`.
- Integrated lane HEAD: `9403bfbd8fb1c951cbea96085f0cbfc3a914eb68`.
- Final reviewed code/test HEAD: `43f47e363e39c20b0e958900fa539b0969714a81`.
- Independent reviewer: `/root/campaign12_tier2_reviewer`.
- Initial totals: Critical **0**, Important **2**, Minor **2**, plus two coverage/index warnings.
- Final totals: Critical **0**, Important **0**. One production-duplication Minor is explicitly deferred below.

## Accepted lane commits and merges

| Lane | Source commit | Integration merge |
|---|---|---|
| D — Profile | `e57ad45fad6212e206ac1aa48948e6777dd4c1ef` | `dbd19ab6deac0713994b96c24da3ec8bba8217c6` |
| E — Auth | `6a1c4dbd774fe9b0af0d0b77c7539f6c4f6aedc4` | `8acd9f369e763d541fda675dc60f6681e987d8fb` |
| F — LessonTransition | `bb88b9e96097c57c49cd07e20259ae120c0aa781` | `9403bfbd8fb1c951cbea96085f0cbfc3a914eb68` |

The reviewer confirmed merge drift `0/0/0`: every integrated lane blob matched its accepted lane commit. Verify-only controllers, DTOs, Profile policy/linking, Password/Session, platform integrity, settlement, reservation, lifecycle, and constraint-engine sources remained byte-identical to the Tier 2 base.

## Integrated smoke

- Profile: 6 suites, 25/25 tests PASS after the coverage fix.
- Auth: 6 suites, 52/52 tests PASS.
- LessonTransition: metadata/boundary/order 13/13 PASS; named PostgreSQL 3/3 PASS.
- Backend typecheck and `git diff --check`: PASS.
- The executable F8 and T2.3 commands now name `lesson-transition-order.spec.ts`; the runtime-order guard cannot be skipped by the documented focused gate.

## Initial findings

### Important 1 — facade delegation guard

`lesson-transition-boundaries.spec.ts` checked constructor types and method names but did not enforce `private readonly` or exact owner, method, and argument order for the eight facade delegations. An incorrect delegation could pass.

### Important 2 — source-marker order guard

The transition transaction/publication order check used raw-source marker positions. Comments or dead code could satisfy it without proving runtime order.

### Minor 1 — metadata regex ownership guard

The metadata interface, five consumers, and historical re-export were checked with raw-text regex and could be satisfied by comments.

### Minor 2 — duplicated Auth lookup

`auth-verification.service.ts` and `auth-password-recovery.service.ts` contain the same security-sensitive active app-account lookup predicate. The current copies are behaviorally identical, but future predicate drift is possible.

### Review warnings

- Two Profile characterization assertions were lost during the split: empty active branches and the batched eight-count directory projection.
- RepoWise reported the integrated SHA but initially served the old 656-NLOC Profile facade and missed four Profile owners. Those rows were rejected as evidence.

## Fix round 1

| Applied commit | Disposition |
|---|---|
| `83db18ee663a372246f9388108996a607f6381a8` | Restored empty-branch `[]/null` and single-query eight-count projection tests; Profile smoke 25/25. |
| `f5ec03d6646a390a76b8cc8ab5e23e1acf6da29b` | Added exact facade AST delegation/modifier checks with negative mutations, a real command→mutation→commit→publish runtime event test, and AST metadata ownership checks; 13/13 focused tests. |

Scoped re-review verdict: both Important findings **ADDRESSED**. Runtime order invokes the real `LessonTransitionCommandService` and `LessonTransitionCommitService` through the platform mutation mock and proves publication only after mutation resolution. The metadata finding remained a Minor because the first AST version allowed extra/aliased imports, and the boundary spec had grown past 500 NLOC.

## Fix round 2

| Applied commit | Disposition |
|---|---|
| `43f47e363e39c20b0e958900fa539b0969714a81` | Enforced unique/exclusive neutral metadata imports/re-export with adversarial cases and split runtime fixtures into `lesson-transition-order.spec.ts`. |

Final fix review: Critical/Important/Minor **0/0/0** for the fix diff. Metadata ownership is exact and decoy-resistant. The runtime test moved without weakening or duplication. Live spec NLOC is metadata `177`, boundaries `338`, order `303`.

## RepoWise evidence and merge-DAG repair

The first ordinary incremental update advanced the state SHA but did not traverse all merge parents. Because its Profile metrics were demonstrably stale, it was rejected. The deterministic repair was:

`repowise update --index-only --since 2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`

After repair, all 20 literal D/E/F facade/owner targets matched and no extracted owner had a god/brain finding. Owner NLOC is at most 436 and max CCN is 10. Raw owner scores below 7 are preserved only where RepoWise reports the exact stale-LCOV `untested_hotspot` penalty of 1.56; the coverage-adjusted tier view passes, but cannot satisfy final campaign acceptance.

The final global Task M gate must ingest fresh LCOV and prove raw health `>=7.0` for every extracted owner. Existing compatibility facades retain historical churn/defect deductions and are evaluated by direct-facade NLOC/CCN/guard contracts, not the new-owner score gate.

## Deferred Minor ruling

The duplicated Auth `findUserByEmail` query remains open for a later Auth repository consolidation. It is not a current behavior divergence: both predicates are identical, all Auth security tests pass, and no public or transaction contract depends on choosing a new repository boundary during this review fix. Cost if wrong: a focused Auth owner extraction plus its existing 52-test smoke before final campaign review.

Tier 2 is accepted for progression with Critical/Important `0/0`, the explicit Auth duplication Minor above, and the fresh-LCOV Task M blocker retained.
